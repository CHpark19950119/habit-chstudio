import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../models/order_models.dart';
import '../utils/study_date_utils.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_service.dart';
import 'geofence_service.dart';
import 'telegram_service.dart';
import 'bus_service.dart';
import 'location_service.dart';
import 'report_service.dart';
import 'backup_service.dart';
import 'routine_service.dart';
import 'meal_service.dart';
import 'movement_service.dart';
import 'safety_net_service.dart';

part 'nfc_action_part.dart';

/// ═══════════════════════════════════════════════════
///  DayState FSM — 하루 루틴 상태 (식사 제외)
///  ※ 외부 호환을 위해 여기 선언, RoutineService에서 import해서 사용
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

class NfcService extends ChangeNotifier {
  static final NfcService _instance = NfcService._internal();
  factory NfcService() => _instance;
  NfcService._internal();

  // ═══ NFC 전용 ═══
  List<NfcTagConfig> _tags = [];
  bool _nfcAvailable = false;
  bool _initialized = false;

  // ═══ Tag dedup (30s) ═══
  final Map<NfcTagRole, DateTime> _lastTagTime = {};
  static const _dedupWindow = Duration(seconds: 30);

  // ═══ UI ═══
  NfcAction? _lastAction;
  String lastDiagnostic = '';
  bool _silentReaderEnabled = false;
  bool _notifPermissionRequested = false;

  // ═══ Sub-service refs ═══
  final _routine = RoutineService();
  final _meal = MealService();
  final _movement = MovementService();

  // ═══ Getters (delegate to sub-services) ═══
  DayState get state => _routine.state;
  bool get isOut => _routine.isOut;
  bool get isStudying => _routine.isStudying;
  bool get isMealing => _meal.isMealing;
  bool get isAvailable => _nfcAvailable;
  bool get isSilentReaderEnabled => _silentReaderEnabled;
  List<NfcTagConfig> get tags => List.unmodifiable(_tags);
  String? get outingTime => _movement.outingTime;
  String? get returnTime => _movement.returnTime;
  String? get currentActivity => _movement.currentActivity;
  List<Map<String, String>> get activityTransitions => _movement.activityTransitions;

  NfcAction? consumeLastAction() {
    final a = _lastAction;
    _lastAction = null;
    return a;
  }

  void _emitAction(String action, String emoji, String message) {
    _lastAction = NfcAction(action, emoji, message);
    notifyListeners();
  }

  // ═══ State force (외부 호출용 facade) ═══

  Future<void> triggerAutoSleep(DateTime sleepTime) async {
    if (_routine.state == DayState.idle || _routine.state == DayState.sleeping) {
      _log('Auto-sleep skip (${_routine.state.name})');
      return;
    }
    final dateStr = _studyDate(sleepTime);
    final timeStr = DateFormat('HH:mm').format(sleepTime);
    _log('Auto-sleep triggered: $dateStr $timeStr');
    await _handleSleep(dateStr, timeStr);
  }

  void forceOutState(bool value) {
    if (value) { _routine.setState(DayState.outing); }
    else if (_routine.state == DayState.outing) { _routine.setState(DayState.returned); }
    _routine.saveState();
    notifyListeners();
  }

  void forceState(DayState newState) => _routine.forceState(newState);
  void forceStudyState(bool value) => _routine.forceStudyState(value);

  // ═══ 로깅 ═══
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

    // Sub-services 초기화
    await _routine.initialize(_nfcChannel);
    await _meal.initialize();

    // Sub-service 변경 → NfcService notifyListeners 전파
    _routine.addListener(notifyListeners);
    _meal.addListener(notifyListeners);
    _movement.addListener(notifyListeners);

    // Movement action callback → NfcService _emitAction으로 전파
    _movement.onAction = (action, emoji, message) {
      _emitAction(action, emoji, message);
    };

    _log('복원: state=${_routine.state.name}, meal=${_meal.isMealing}');

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

    // Movement 서비스 초기화 (Geofence + Bixby movement 리스너)
    await _movement.initialize();

    // 외출 중이면 Activity Recognition 재시작 (앱 업데이트 대응)
    await _routine.restartActivityRecognitionIfNeeded();

    _initialized = true;
    _log('초기화 완료 (state=${_routine.state.name}, mealing=${_meal.isMealing})');
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
    if (_routine.state == DayState.idle && role != NfcTagRole.wake) {
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
      case NfcTagRole.outing: return _routine.state == DayState.outing ? 'end' : 'start';
      case NfcTagRole.study:
        if (_routine.state == DayState.studying) return 'end';
        if (_routine.state == DayState.outing) return 'resume';
        return 'start';
      case NfcTagRole.meal: return _meal.isMealing ? 'end' : 'start';
      default: return null;
    }
  }

  Future<void> triggerRole(NfcTagRole role) async {
    await _dispatch(role);
  }

  Future<String> manualTestRole(NfcTagRole role) async {
    _lastTagTime.remove(role);
    try {
      await _dispatch(role, saveEvent: false);
      return '${role.name} OK (state=${_routine.state.name}, meal=${_meal.isMealing})';
    } catch (e) { return '에러: $e'; }
  }

  String? _findTagName(String? uid) {
    if (uid == null) return null;
    for (final t in _tags) {
      if (t.nfcId?.toLowerCase() == uid.toLowerCase()) return t.name;
    }
    return null;
  }

  Future<void> reloadTags() async {
    await _loadTags();
    notifyListeners();
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
  //  이동시간 요약 (delegate)
  // ═══════════════════════════════════════════

  Future<Map<String, int?>> getTodayTravelSummary() => _movement.getTodayTravelSummary();

  // ═══════════════════════════════════════════
  //  알림 권한
  // ═══════════════════════════════════════════

  Future<void> _requestNotificationPermissionOnce() async {
    if (_notifPermissionRequested) return;
    _notifPermissionRequested = true;
    try { await _nfcChannel.invokeMethod('requestNotificationPermission'); } catch (_) {}
  }

  @override
  void dispose() {
    _routine.removeListener(notifyListeners);
    _meal.removeListener(notifyListeners);
    _movement.removeListener(notifyListeners);
    super.dispose();
  }
}
