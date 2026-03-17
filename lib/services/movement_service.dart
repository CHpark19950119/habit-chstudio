import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../utils/study_date_utils.dart';
import 'routine_service.dart';
import 'day_service.dart' show DayState;
import 'firebase_service.dart';
import 'geofence_service.dart';
import 'location_service.dart';
import 'telegram_service.dart';

/// NFC Action — UI 표시용 (movement에서 발생하는 이벤트)
class MovementAction {
  final String action;
  final String emoji;
  final String message;
  MovementAction(this.action, this.emoji, this.message);
}

/// MovementService — 이동/체류 감지, Bixby movement, Geofence, Activity Recognition
class MovementService extends ChangeNotifier {
  static final MovementService _instance = MovementService._internal();
  factory MovementService() => _instance;
  MovementService._internal();

  static const String _iotDocPath = 'users/sJ8Pxusw9gR0tNR44RhkIge7OiG2/data/iot';

  // ═══ Movement times ═══
  String? _outingTime;
  String? _returnTime;

  // ═══ Activity Recognition ═══
  String? _currentActivity;
  List<Map<String, String>> _activityTransitions = [];
  String? _activityDate;

  // ═══ Movement listener ═══
  String? _lastMovementType;
  bool _movementFirstSnapshot = true;
  StreamSubscription<bool>? _geofenceSub;
  StreamSubscription<DocumentSnapshot>? _movementSub;

  // ═══ Action callback ═══
  void Function(String action, String emoji, String message)? onAction;

  bool _initialized = false;

  // ═══ Getters ═══
  String? get outingTime => _outingTime;
  String? get returnTime => _returnTime;
  String? get currentActivity => _currentActivity;
  List<Map<String, String>> get activityTransitions =>
      List.unmodifiable(_activityTransitions);

  void _log(String msg) => debugPrint('[Movement] $msg');
  String _studyDate([DateTime? dt]) => StudyDateUtils.todayKey(dt);

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> initialize() async {
    if (_initialized) return;
    _geofenceSub?.cancel();
    _geofenceSub = GeofenceService().homeStream.listen(_onGeofenceEvent);
    _startMovementListener();
    _initialized = true;
  }

  // ═══════════════════════════════════════════
  //  Geofence 이벤트 처리
  // ═══════════════════════════════════════════

  void _onGeofenceEvent(bool entering) {
    final routine = RoutineService();
    final now = DateTime.now();
    final timeStr = DateFormat('HH:mm').format(now);

    if (!entering && routine.state != DayState.outing) {
      if (routine.state == DayState.idle || routine.state == DayState.sleeping) return;
      _log('Geofence EXIT → iot 이벤트 기록');
      _outingTime = timeStr;
      _returnTime = null;
      _writeGeofenceToIot(type: 'out', timeStr: timeStr);
      routine.forceState(DayState.outing);
      onAction?.call('outing_start', '🚪', '외출 $timeStr (GPS)');
    } else if (entering && routine.state == DayState.outing) {
      _log('Geofence ENTER → iot 이벤트 기록');
      _returnTime = timeStr;
      _writeGeofenceToIot(type: 'home', timeStr: timeStr);
      routine.forceState(DayState.returned);
      onAction?.call('outing_end', '🏠', '귀가 $timeStr (GPS)');
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
    final routine = RoutineService();
    try {
      final data = Map<String, dynamic>.from(snapshot.data() as Map);

      // Activity Recognition 파싱 (movement 변경 무관하게 항상 처리)
      _parseActivityData(data);

      final movement = data['movement'] as Map?;
      if (movement == null) return;

      final pending = movement['pending'] as bool? ?? false;
      final type = movement['type'] as String? ?? '';

      final key = '${pending}_$type';
      final leftLocal = movement['leftAtLocal'] as String?;
      final returnLocal = movement['returnedAtLocal'] as String?;

      // 첫 스냅샷: 상태 동기화
      if (_movementFirstSnapshot) {
        _movementFirstSnapshot = false;
        _lastMovementType = key;

        final mvDate = movement['date'] as String?;
        final mvLeftAt = movement['leftAt'];
        bool isStale = false;
        if (mvDate != null && mvDate != _studyDate()) {
          isStale = true;
        } else if (mvLeftAt != null && mvDate == null) {
          try {
            final leftDt = (mvLeftAt as Timestamp).toDate();
            if (_studyDate(leftDt) != _studyDate()) isStale = true;
          } catch (_) {}
        }

        if (isStale) {
          _log('movement 초기 동기화 스킵 — stale 데이터 (date=$mvDate)');
          notifyListeners();
          return;
        }

        _log('movement 초기 동기화: type=$type, pending=$pending, state=${routine.state.name}');
        if (leftLocal != null) _outingTime = leftLocal;
        if (returnLocal != null) _returnTime = returnLocal;
        if (type == 'out' && !pending) {
          if (routine.state != DayState.outing) {
            _log('초기 동기화 → 외출 반영');
            _returnTime = null;
            routine.forceState(DayState.outing);
          } else {
            notifyListeners();
          }
        } else if (type == 'home') {
          if (routine.state != DayState.returned && routine.state != DayState.studying
              && routine.state != DayState.sleeping) {
            _log('초기 동기화 → 귀가 반영');
            routine.forceState(DayState.returned);
          } else {
            notifyListeners();
          }
        } else {
          notifyListeners();
        }
        return;
      }

      // 중복 처리 방지
      if (key == _lastMovementType) return;
      _lastMovementType = key;

      final now = DateTime.now();
      final timeStr = DateFormat('HH:mm').format(now);

      final source = movement['source'] as String? ?? '';

      if (type == 'out' && !pending && routine.state != DayState.outing
          && !source.startsWith('geofence')) {
        _log('Bixby → 외출 확정 ($leftLocal) — UI만 반영');
        _outingTime = leftLocal ?? timeStr;
        _returnTime = null;
        routine.forceState(DayState.outing);
        onAction?.call('outing_start', '🚪', '외출 ${leftLocal ?? timeStr}');
      } else if (type == 'home' && routine.state == DayState.outing) {
        _log('Bixby → 귀가 — UI만 반영');
        _returnTime = returnLocal ?? timeStr;
        routine.forceState(DayState.returned);
        onAction?.call('outing_end', '🏠', '귀가 ${returnLocal ?? timeStr}');
      } else if (pending && routine.state != DayState.outing) {
        _log('Bixby → 외출 pending ($leftLocal) — 대기');
        onAction?.call('outing_pending', '🚶', '외출 감지 ${leftLocal ?? timeStr} — 확인 중');
        notifyListeners();
      } else if (type == 'cancelled') {
        _log('Bixby → 외출 취소 (빠른 복귀)');
        onAction?.call('outing_cancelled', '✅', '복귀 — 외출 취소');
        notifyListeners();
      }
    } catch (e) {
      _log('movement 파싱 에러: $e');
    }
  }

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

  /// 외출 시간 설정 (action handler에서 사용)
  void setOutingTime(String? time) {
    _outingTime = time;
    notifyListeners();
  }

  /// 귀가 시간 설정 (action handler에서 사용)
  void setReturnTime(String? time) {
    _returnTime = time;
    notifyListeners();
  }

  /// 날짜 변경 시 리셋
  void reset() {
    _outingTime = null;
    _returnTime = null;
    _activityTransitions = [];
    _currentActivity = null;
    _activityDate = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _geofenceSub?.cancel();
    _movementSub?.cancel();
    super.dispose();
  }
}
