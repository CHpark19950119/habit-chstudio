import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../utils/study_date_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';
import 'geofence_service.dart';
import 'telegram_service.dart';
import 'bus_service.dart';
import 'location_service.dart';
import 'report_service.dart';
import 'backup_service.dart';

part 'nfc_action_part.dart';

/// ═══════════════════════════════════════════════════
///  DayState FSM — 하루 루틴 상태 (식사 제외)
/// ═══════════════════════════════════════════════════
enum DayState {
  idle,       // 아직 기상 전
  awake,      // 기상 완료
  outing,     // 외출 중
  studying,   // 공부 중
  returned,   // 귀가 완료
  sleeping,   // 취침
}

/// NFC Action — UI 표시용
class NfcAction {
  final String action;
  final String emoji;
  final String message;
  NfcAction(this.action, this.emoji, this.message);
}

const _nfcChannel = MethodChannel('com.cheonhong.cheonhong_studio/nfc');

class NfcService extends ChangeNotifier with WidgetsBindingObserver {
  static final NfcService _instance = NfcService._internal();
  factory NfcService() => _instance;
  NfcService._internal();

  List<NfcTagConfig> _tags = [];
  bool _nfcAvailable = false;
  bool _initialized = false;

  // ═══ FSM (식사 제외) ═══
  DayState _state = DayState.idle;

  // ═══ 식사 독립 추적 ═══
  bool _isMealing = false;

  // ═══ Tag dedup (30s) ═══
  final Map<NfcTagRole, DateTime> _lastTagTime = {};
  static const _dedupWindow = Duration(seconds: 30);

  // ═══ Reminders ═══
  Timer? _wakeReminder;
  Timer? _mealReminder;
  StreamSubscription<bool>? _geofenceSub;
  StreamSubscription<DocumentSnapshot>? _movementSub;

  // ═══ Movement times (Single Source of Truth for UI) ═══
  String? _outingTime;
  String? _returnTime;

  // ═══ Activity Recognition (이동/정지 감지) ═══
  String? _currentActivity;
  List<Map<String, String>> _activityTransitions = [];
  String? _activityDate;

  // ═══ UI ═══
  NfcAction? _lastAction;
  String lastDiagnostic = '';
  bool _silentReaderEnabled = false;
  bool _notifPermissionRequested = false;

  // ═══ Getters ═══
  DayState get state => _state;
  bool get isOut => _state == DayState.outing;
  bool get isStudying => _state == DayState.studying;
  bool get isMealing => _isMealing;
  bool get isAvailable => _nfcAvailable;
  bool get isSilentReaderEnabled => _silentReaderEnabled;
  List<NfcTagConfig> get tags => List.unmodifiable(_tags);
  String? get outingTime => _outingTime;
  String? get returnTime => _returnTime;
  String? get currentActivity => _currentActivity;
  List<Map<String, String>> get activityTransitions =>
      List.unmodifiable(_activityTransitions);

  NfcAction? consumeLastAction() {
    final a = _lastAction;
    _lastAction = null;
    return a;
  }

  void _emitAction(String action, String emoji, String message) {
    _lastAction = NfcAction(action, emoji, message);
    notifyListeners();
  }

  // ═══ State force (home_routine_card 수동 편집용) ═══
  /// 자동 수면 감지에서 호출 — 화면 꺼진 시각 기준으로 취침 처리
  Future<void> triggerAutoSleep(DateTime sleepTime) async {
    if (_state == DayState.idle || _state == DayState.sleeping) {
      _log('Auto-sleep skip (${_state.name})');
      return;
    }
    final dateStr = _studyDate(sleepTime);
    final timeStr = DateFormat('HH:mm').format(sleepTime);
    _log('Auto-sleep triggered: $dateStr $timeStr');
    await _handleSleep(dateStr, timeStr);
  }

  void forceOutState(bool value) {
    if (value) { _state = DayState.outing; }
    else if (_state == DayState.outing) { _state = DayState.returned; }
    _saveState();
    notifyListeners();
  }

  /// 외부 이벤트(FCM/CF) → UI 상태만 변경 (timeRecords 쓰기 없음)
  void forceState(DayState newState) {
    if (_state == newState) return;
    _log('forceState: ${_state.name} → ${newState.name}');
    _state = newState;
    _saveState();
    if (newState == DayState.awake) {
      _startWakeReminder();
      BusService().startPolling();
    } else if (newState == DayState.outing) {
      _cancelReminders();
      BusService().stopPolling();
    }
    notifyListeners();
  }

  void forceStudyState(bool value) {
    if (value) { _state = DayState.studying; }
    else if (_state == DayState.studying) { _state = DayState.returned; }
    _saveState();
    notifyListeners();
  }

  void _log(String msg) {
    debugPrint('[NFC] $msg');
    lastDiagnostic = '${DateFormat('HH:mm:ss').format(DateTime.now())} $msg';
  }

  String _studyDate([DateTime? dt]) => StudyDateUtils.todayKey(dt);

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> initialize() async {
    if (_initialized) return;
    _log('초기화 시작');

    try { _nfcAvailable = await NfcManager.instance.isAvailable(); }
    catch (_) { _nfcAvailable = false; }

    await _loadTags();
    await _restoreState();
    _setupMethodChannel();

    try { await _nfcChannel.invokeMethod('flutterReady'); } catch (_) {}

    // 대기 중인 NFC Intent
    try {
      final pending = await _nfcChannel.invokeMethod<Map>('getPendingNfcIntent');
      if (pending != null) {
        final role = _argStr(pending, 'role');
        final tagUid = _argStr(pending, 'tagUid');
        if (role.isNotEmpty) {
          final parsed = NfcTagRole.values.where((r) => r.name == role);
          if (parsed.isNotEmpty) await _dispatch(parsed.first, tagUid: tagUid.isNotEmpty ? tagUid : null);
        } else if (tagUid.isNotEmpty) {
          final matched = _matchTag(tagUid);
          if (matched != null) await _dispatch(matched.role, tagUid: tagUid, tagName: matched.name);
        }
      }
    } catch (_) {}

    await _requestNotificationPermissionOnce();

    // ★ Geofence 자동 외출/귀가 연결
    _geofenceSub?.cancel();
    _geofenceSub = GeofenceService().homeStream.listen(_onGeofenceEvent);

    // ★ Bixby movement 실시간 감지 (data/iot movement 필드)
    _startMovementListener();

    // ★ 백그라운드→포그라운드 전환 시 상태 재로딩
    WidgetsBinding.instance.addObserver(this);

    _initialized = true;
    _log('초기화 완료 (state=${_state.name}, mealing=$_isMealing)');
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState lifecycleState) {
    if (lifecycleState == AppLifecycleState.resumed) {
      _syncStateFromPrefs();
    }
  }

  /// 백그라운드 FCM/Geofence가 SharedPreferences에 저장한 상태를 읽어 UI 반영
  Future<void> _syncStateFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload(); // isolate 간 동기화
    final savedDate = prefs.getString('nfc_state_date');
    if (savedDate != _studyDate()) return;
    final savedName = prefs.getString('nfc_state') ?? 'idle';
    final saved = DayState.values.firstWhere(
      (s) => s.name == savedName, orElse: () => DayState.idle);
    if (saved != _state) {
      _log('resume 동기화: $_state → $saved');
      _state = saved;
      notifyListeners();
    }
  }

  void _onGeofenceEvent(bool entering) {
    final now = DateTime.now();
    final dateStr = _studyDate(now);
    final timeStr = DateFormat('HH:mm').format(now);

    if (!entering && _state != DayState.outing) {
      // EXIT → data/iot에 이벤트 기록 (CF onIotWrite가 timeRecords 처리)
      if (_state == DayState.idle || _state == DayState.sleeping) return;
      _log('Geofence EXIT → iot 이벤트 기록');
      _outingTime = timeStr;
      _returnTime = null;
      _writeGeofenceToIot(type: 'out', timeStr: timeStr);
      forceState(DayState.outing);
      _emitAction('outing_start', '🚪', '외출 $timeStr (GPS)');
    } else if (entering && _state == DayState.outing) {
      // ENTER → data/iot에 이벤트 기록
      _log('Geofence ENTER → iot 이벤트 기록');
      _returnTime = timeStr;
      _writeGeofenceToIot(type: 'home', timeStr: timeStr);
      forceState(DayState.returned);
      _emitAction('outing_end', '🏠', '귀가 $timeStr (GPS)');
    }
  }

  Future<void> _writeGeofenceToIot({required String type, required String timeStr}) async {
    try {
      final ref = FirebaseFirestore.instance.doc(_iotDocPath);
      if (type == 'out') {
        await ref.set({
          'movement': {
            'pending': false,
            'type': 'out',
            'leftAt': FieldValue.serverTimestamp(),
            'leftAtLocal': timeStr,
            'source': 'geofence',
            'confirmedAt': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));
      } else {
        await ref.update({
          'movement.type': 'home',
          'movement.returnedAt': FieldValue.serverTimestamp(),
          'movement.returnedAtLocal': timeStr,
          'movement.source': 'geofence',
        }).timeout(const Duration(seconds: 5));
      }
    } catch (e) {
      _log('iot 기록 에러: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  Activity Recognition 파싱
  // ═══════════════════════════════════════════

  void _parseActivityData(Map<String, dynamic> data) {
    final activity = data['activity'] as Map?;
    if (activity == null) return;
    final actDate = activity['date'] as String?;
    final todayStr = _studyDate(DateTime.now());
    if (actDate != todayStr) {
      // 날짜 다르면 무시
      if (_activityTransitions.isNotEmpty) {
        _activityTransitions = [];
        _currentActivity = null;
        _activityDate = null;
        notifyListeners();
      }
      return;
    }
    bool changed = false;
    final newCurrent = activity['current'] as String?;
    if (newCurrent != _currentActivity) {
      _currentActivity = newCurrent;
      _activityDate = actDate;
      changed = true;
    }
    final transitions = activity['transitions'] as List?;
    if (transitions != null) {
      final newList = transitions
          .map((t) {
            final m = Map<String, dynamic>.from(t as Map);
            return {
              'type': m['type']?.toString() ?? '',
              'time': m['time']?.toString() ?? '',
            };
          })
          .toList();
      if (newList.length != _activityTransitions.length) {
        _activityTransitions = newList;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  Bixby movement 실시간 감지
  // ═══════════════════════════════════════════

  static const String _iotDocPath = 'users/sJ8Pxusw9gR0tNR44RhkIge7OiG2/data/iot';
  String? _lastMovementType;
  bool _movementFirstSnapshot = true;

  void _startMovementListener() {
    _movementSub?.cancel();
    _movementFirstSnapshot = true;
    _movementSub = FirebaseFirestore.instance
        .doc(_iotDocPath)
        .snapshots()
        .listen(_onMovementSnapshot, onError: (e) {
      _log('movement 스트림 에러: $e');
      Future.delayed(const Duration(seconds: 5), _startMovementListener);
    });
  }

  void _onMovementSnapshot(DocumentSnapshot snapshot) {
    if (!snapshot.exists) return;
    try {
      final data = Map<String, dynamic>.from(snapshot.data() as Map);

      // ── Activity Recognition 파싱 (movement 변경 무관하게 항상 처리) ──
      _parseActivityData(data);

      final movement = data['movement'] as Map?;
      if (movement == null) return;

      final pending = movement['pending'] as bool? ?? false;
      final type = movement['type'] as String? ?? '';

      final key = '${pending}_$type';
      final leftLocal = movement['leftAtLocal'] as String?;
      final returnLocal = movement['returnedAtLocal'] as String?;

      // 첫 스냅샷: 상태 동기화 (앱 재설치/업데이트 포함)
      if (_movementFirstSnapshot) {
        _movementFirstSnapshot = false;
        _lastMovementType = key;
        _log('movement 초기 동기화: type=$type, pending=$pending, state=${_state.name}');
        // 시간 복원
        if (leftLocal != null) _outingTime = leftLocal;
        if (returnLocal != null) _returnTime = returnLocal;
        // ★ 조건 완화: SharedPrefs 날림 후에도 iot 기준으로 복원
        if (type == 'out' && !pending) {
          if (_state != DayState.outing) {
            _log('초기 동기화 → 외출 반영');
            _returnTime = null;
            forceState(DayState.outing);
          } else {
            notifyListeners(); // 상태 같아도 시간값 전파
          }
        } else if (type == 'home') {
          if (_state != DayState.returned && _state != DayState.studying
              && _state != DayState.sleeping) {
            _log('초기 동기화 → 귀가 반영');
            forceState(DayState.returned);
          } else {
            notifyListeners(); // 시간값 전파
          }
        } else {
          notifyListeners(); // pending 등 기타 — 시간값만 전파
        }
        return;
      }

      // 중복 처리 방지
      if (key == _lastMovementType) return;
      _lastMovementType = key;

      final now = DateTime.now();
      final dateStr = _studyDate(now);
      final timeStr = DateFormat('HH:mm').format(now);

      final source = movement['source'] as String? ?? '';

      if (type == 'out' && !pending && _state != DayState.outing
          && !source.startsWith('geofence')) {
        // CF가 확정 → UI 상태만 전환 (geofence는 자체 처리)
        _log('Bixby → 외출 확정 ($leftLocal) — UI만 반영');
        _outingTime = leftLocal ?? timeStr;
        _returnTime = null;
        forceState(DayState.outing);
        _emitAction('outing_start', '🚪', '외출 ${leftLocal ?? timeStr}');
      } else if (type == 'home' && _state == DayState.outing) {
        // 귀가 → UI 상태만 전환
        _log('Bixby → 귀가 — UI만 반영');
        _returnTime = returnLocal ?? timeStr;
        forceState(DayState.returned);
        _emitAction('outing_end', '🏠', '귀가 ${returnLocal ?? timeStr}');
      } else if (pending && _state != DayState.outing) {
        // pending 상태 — UI 알림만 (상태 전환 X)
        _log('Bixby → 외출 pending ($leftLocal) — 대기');
        _emitAction('outing_pending', '🚶', '외출 감지 ${leftLocal ?? timeStr} — 확인 중');
        notifyListeners();
      } else if (type == 'cancelled') {
        // 빠른 복귀 → pending 취소
        _log('Bixby → 외출 취소 (빠른 복귀)');
        _emitAction('outing_cancelled', '✅', '복귀 — 외출 취소');
        notifyListeners();
      }
    } catch (e) {
      _log('movement 파싱 에러: $e');
    }
  }

  Future<void> reloadTags() async {
    await _loadTags();
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  Tag dedup (30s)
  // ═══════════════════════════════════════════

  bool _isDuplicate(NfcTagRole role) {
    final now = DateTime.now();
    final last = _lastTagTime[role];
    if (last != null && now.difference(last) < _dedupWindow) {
      _log('중복 태그: ${role.name} (${now.difference(last).inSeconds}s ago)');
      return true;
    }
    _lastTagTime[role] = now;
    return false;
  }

  // ═══════════════════════════════════════════
  //  무진동 리더
  // ═══════════════════════════════════════════

  Future<void> enableSilentReader() async {
    if (!_nfcAvailable) return;
    try {
      await _nfcChannel.invokeMethod('enableSilentReader');
      _silentReaderEnabled = true;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> disableSilentReader() async {
    try {
      await _nfcChannel.invokeMethod('disableSilentReader');
      _silentReaderEnabled = false;
      notifyListeners();
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  //  MethodChannel
  // ═══════════════════════════════════════════

  void _setupMethodChannel() {
    _nfcChannel.setMethodCallHandler((call) async {
      if (call.method != 'onNfcTagFromIntent') return;
      final args = call.arguments;
      final role = _argStr(args, 'role');
      final tagUid = _argStr(args, 'tagUid');
      _log('Intent: role="$role", tagUid="$tagUid"');

      if (role.isNotEmpty) {
        final parsed = NfcTagRole.values.where((r) => r.name == role);
        if (parsed.isNotEmpty) await _dispatch(parsed.first, tagUid: tagUid.isNotEmpty ? tagUid : null);
      } else if (tagUid.isNotEmpty) {
        final matched = _matchTag(tagUid);
        if (matched != null) await _dispatch(matched.role, tagUid: tagUid, tagName: matched.name);
      }
    });
  }

  String _argStr(dynamic args, String key) {
    try { if (args is Map) { final v = args[key]; if (v != null) return v.toString(); } }
    catch (_) {}
    return '';
  }

  // ═══════════════════════════════════════════
  //  Unified dispatch
  // ═══════════════════════════════════════════

  Future<void> _dispatch(NfcTagRole role, {
    String? tagUid, String? tagName, bool saveEvent = true,
  }) async {
    if (_isDuplicate(role)) return;

    final now = DateTime.now();
    final dateStr = _studyDate(now);
    final timeStr = DateFormat('HH:mm').format(now);

    // Auto-wake
    if (_state == DayState.idle && role != NfcTagRole.wake) {
      _log('Auto-wake: ${role.name}');
      await _handleWake(dateStr, timeStr, auto: true);
    }

    // 이벤트 저장
    if (saveEvent) {
      final event = NfcEvent(
        id: 'nfc_${now.millisecondsSinceEpoch}',
        date: dateStr, timestamp: now.toIso8601String(),
        role: role,
        tagName: tagName ?? _findTagName(tagUid) ?? role.name,
        action: _resolveAction(role),
      );
      FirebaseService().saveNfcEvent(dateStr, event)
          .timeout(const Duration(seconds: 5))
          .catchError((_) {});
    }

    switch (role) {
      case NfcTagRole.wake:  await _handleWake(dateStr, timeStr); break;
      case NfcTagRole.outing: await _handleOuting(dateStr, timeStr); break;
      case NfcTagRole.study: await _handleStudy(dateStr, timeStr); break;
      case NfcTagRole.meal:  await _handleMeal(dateStr, timeStr); break;
      case NfcTagRole.sleep: await _handleSleep(dateStr, timeStr); break;
    }
    notifyListeners();
  }

  String? _resolveAction(NfcTagRole role) {
    switch (role) {
      case NfcTagRole.outing: return _state == DayState.outing ? 'end' : 'start';
      case NfcTagRole.study:
        if (_state == DayState.studying) return 'end';
        if (_state == DayState.outing) return 'resume';
        return 'start';
      case NfcTagRole.meal: return _isMealing ? 'end' : 'start';
      default: return null;
    }
  }

  /// FCM/외부 트리거에서 호출 — dedup 적용, 이벤트 저장
  Future<void> triggerRole(NfcTagRole role) async {
    await _dispatch(role);
  }

  Future<String> manualTestRole(NfcTagRole role) async {
    _lastTagTime.remove(role);
    try {
      await _dispatch(role, saveEvent: false);
      return '${role.name} OK (state=${_state.name}, meal=$_isMealing)';
    } catch (e) { return '에러: $e'; }
  }

  String? _findTagName(String? uid) {
    if (uid == null) return null;
    for (final t in _tags) {
      if (t.nfcId?.toLowerCase() == uid.toLowerCase()) return t.name;
    }
    return null;
  }

  // ═══════════════════════════════════════════
  //  NFC 스캔
  // ═══════════════════════════════════════════

  Future<void> startScan({
    required Function(NfcTagConfig? matchedTag, String nfcUid) onDetected,
    required Function(String error) onError,
    bool executeOnMatch = true,
  }) async {
    if (!_nfcAvailable) { onError('NFC 사용 불가'); return; }
    if (_silentReaderEnabled) await disableSilentReader();
    try { NfcManager.instance.stopSession(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 300));

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (NfcTag tag) async {
        try {
          final uid = _extractUid(tag);
          if (uid == null) { onError('UID 읽기 실패'); NfcManager.instance.stopSession(); return; }
          final matched = _matchTag(uid);
          onDetected(matched, uid);
          if (executeOnMatch && matched != null) {
            await _dispatch(matched.role, tagUid: uid, tagName: matched.name);
          }
          NfcManager.instance.stopSession();
        } catch (e) { onError('태그 읽기 실패: $e'); NfcManager.instance.stopSession(); }
      },
    );
  }

  void stopScan() { try { NfcManager.instance.stopSession(); } catch (_) {} }

  String? _extractUid(NfcTag tag) {
    try {
      for (final key in ['nfca', 'nfcb', 'nfcf', 'nfcv', 'mifareclassic', 'mifareultralight']) {
        final tech = tag.data[key];
        if (tech is Map) {
          final id = tech['identifier'];
          if (id is List) return id.cast<int>().map((b) => b.toRadixString(16).padLeft(2, '0')).join(':');
        }
      }
    } catch (_) {}
    return null;
  }

  NfcTagConfig? _matchTag(String uid) {
    for (final t in _tags) {
      if (t.nfcId != null && t.nfcId!.toLowerCase() == uid.toLowerCase()) return t;
    }
    return null;
  }

  // ═══════════════════════════════════════════
  //  NDEF 쓰기
  // ═══════════════════════════════════════════

  Future<bool> writeNdefToTag({
    required NfcTagRole role, required String tagId,
    required Function(String) onStatus,
  }) async {
    if (!_nfcAvailable) return false;
    if (_silentReaderEnabled) await disableSilentReader();
    try { NfcManager.instance.stopSession(); } catch (_) {}
    await Future.delayed(const Duration(milliseconds: 200));

    final completer = Completer<bool>();
    onStatus('태그를 가까이 대세요...');

    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443},
      onDiscovered: (NfcTag tag) async {
        try {
          final uri = 'cheonhong://nfc?role=${role.name}&tagId=$tagId';
          final msg = NdefMessage([
            NdefRecord.createUri(Uri.parse(uri)),
            NdefRecord(
              typeNameFormat: NdefTypeNameFormat.nfcExternal,
              type: Uint8List.fromList('android.com:pkg'.codeUnits),
              identifier: Uint8List(0),
              payload: Uint8List.fromList('com.cheonhong.cheonhong_studio'.codeUnits)),
          ]);
          final ndef = Ndef.from(tag);
          bool ok = false;
          if (ndef != null && ndef.isWritable) { await ndef.write(msg); ok = true; }
          else { onStatus(ndef == null ? 'NDEF 미지원' : '쓰기 금지'); }
          NfcManager.instance.stopSession();
          if (ok) onStatus('NDEF 쓰기 완료!');
          if (!completer.isCompleted) completer.complete(ok);
        } catch (e) {
          NfcManager.instance.stopSession(errorMessage: '실패');
          onStatus('쓰기 실패: $e');
          if (!completer.isCompleted) completer.complete(false);
        }
      },
      onError: (_) async {
        onStatus('NFC 세션 오류');
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    Future.delayed(const Duration(seconds: 30), () {
      if (!completer.isCompleted) {
        try { NfcManager.instance.stopSession(); } catch (_) {}
        completer.complete(false);
      }
    });
    return completer.future;
  }

  // ═══════════════════════════════════════════
  //  태그 CRUD
  // ═══════════════════════════════════════════

  Future<NfcTagConfig> registerTag({
    required String name, required NfcTagRole role,
    required String nfcUid, String? placeName,
  }) async {
    final tag = NfcTagConfig(
      id: 'nfc_tag_${DateTime.now().millisecondsSinceEpoch}',
      name: name, role: role, nfcId: nfcUid, placeName: placeName,
      createdAt: DateTime.now().toIso8601String());
    _tags.add(tag);
    await FirebaseService().saveNfcTags(_tags);
    notifyListeners();
    return tag;
  }

  Future<void> removeTag(String tagId) async {
    _tags.removeWhere((t) => t.id == tagId);
    await FirebaseService().saveNfcTags(_tags);
    notifyListeners();
  }

  Future<void> updateTagRole(String tagId, NfcTagRole newRole) async {
    final idx = _tags.indexWhere((t) => t.id == tagId);
    if (idx < 0) return;
    final old = _tags[idx];
    _tags[idx] = NfcTagConfig(id: old.id, name: old.name, role: newRole,
      nfcId: old.nfcId, placeName: old.placeName, createdAt: old.createdAt);
    await FirebaseService().saveNfcTags(_tags);
    notifyListeners();
  }

  Future<void> _loadTags() async {
    try { _tags = await FirebaseService().getNfcTags(); } catch (_) { _tags = []; }
  }

  // ═══════════════════════════════════════════
  //  FSM 상태 저장/복원 (SharedPreferences)
  // ═══════════════════════════════════════════

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nfc_state', _state.name);
    await prefs.setBool('nfc_is_mealing', _isMealing);
    await prefs.setString('nfc_state_date', _studyDate());
  }

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('nfc_state_date');
    if (savedDate == _studyDate()) {
      _state = DayState.values.firstWhere(
        (s) => s.name == (prefs.getString('nfc_state') ?? 'idle'),
        orElse: () => DayState.idle);
      _isMealing = prefs.getBool('nfc_is_mealing') ?? false;
      _log('복원: state=${_state.name}, meal=$_isMealing');
    } else {
      _state = DayState.idle;
      _isMealing = false;
      _outingTime = null;
      _returnTime = null;
      await _saveState();
      _log('날짜 변경 → 리셋');
    }
  }

  // ═══════════════════════════════════════════
  //  Reminders
  // ═══════════════════════════════════════════

  void _startWakeReminder() {
    _wakeReminder?.cancel();
    _wakeReminder = Timer(const Duration(minutes: 60), () {
      if (_state == DayState.awake) {
        _sendNfc('⏰ 기상 60분 — 공부 시작하세요!');
        _notifyNative(title: '활동 리마인더', body: '기상 60분 경과');
      }
    });
  }

  void _startMealReminder() {
    _mealReminder?.cancel();
    _mealReminder = Timer(const Duration(hours: 4), () {
      if (_state == DayState.studying && !_isMealing) {
        _sendNfc('🍽 공부 4시간 — 식사하세요!');
        _notifyNative(title: '식사 리마인더', body: '공부 4시간 경과');
      }
    });
  }

  void _cancelReminders() { _wakeReminder?.cancel(); _mealReminder?.cancel(); }

  // ═══════════════════════════════════════════
  //  이동시간 요약
  // ═══════════════════════════════════════════

  Future<Map<String, int?>> getTodayTravelSummary() async {
    try {
      final records = await FirebaseService().getTimeRecords();
      final tr = records[_studyDate()];
      if (tr == null) return {};
      return {'commuteTo': tr.commuteToMinutes, 'commuteFrom': tr.commuteFromMinutes, 'stayTime': tr.stayMinutes};
    } catch (_) { return {}; }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelReminders();
    _geofenceSub?.cancel();
    super.dispose();
  }
}
