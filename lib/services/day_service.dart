import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

part 'day_action_part.dart';

/// ═══════════════════════════════════════════════════
///  DayState FSM — 하루 루틴 상태
/// ═══════════════════════════════════════════════════
enum DayState {
  idle,       // 아직 기상 전
  awake,      // 기상 완료
  outing,     // 외출 중
  studying,   // 공부 중
  returned,   // 귀가 완료
  sleeping,   // 취침
}

// ActionType은 models.dart에서 정의됨

/// Day Action — UI 표시용
class DayAction {
  final String action;
  final String emoji;
  final String message;
  DayAction(this.action, this.emoji, this.message);
}

const _appChannel = MethodChannel('com.cheonhong.cheonhong_studio/nfc');

/// ═══════════════════════════════════════════════════
///  DayService — 자동화 기반 하루 루틴 관리
///  도어센서, GPS, 빅스비, SafetyNet, 위젯으로 구동
/// ═══════════════════════════════════════════════════
class DayService extends ChangeNotifier {
  static final DayService _instance = DayService._internal();
  factory DayService() => _instance;
  DayService._internal();

  bool _initialized = false;

  // ═══ Action dedup (30s) ═══
  final Map<ActionType, DateTime> _lastActionTime = {};
  static const _dedupWindow = Duration(seconds: 30);

  // ═══ UI ═══
  DayAction? _lastAction;
  String lastDiagnostic = '';
  bool _notifPermissionRequested = false;

  // ═══ Sub-service refs ═══
  final _routine = RoutineService();
  final _meal = MealService();
  final _movement = MovementService();

  // ═══ Getters ═══
  DayState get state => _routine.state;
  bool get isOut => _routine.isOut;
  bool get isStudying => _routine.isStudying;
  bool get isMealing => _meal.isMealing;
  String? get outingTime => _movement.outingTime;
  String? get returnTime => _movement.returnTime;
  String? get currentActivity => _movement.currentActivity;
  List<Map<String, String>> get activityTransitions => _movement.activityTransitions;

  DayAction? consumeLastAction() {
    final a = _lastAction;
    _lastAction = null;
    return a;
  }

  void _emitAction(String action, String emoji, String message) {
    _lastAction = DayAction(action, emoji, message);
    notifyListeners();
  }

  // ═══ State force (외부 호출용) ═══

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

  /// 외부 서비스에서 UI 갱신 트리거 (SafetyNet 등)
  void notifyDataChanged() => notifyListeners();

  // ═══ 로깅 ═══
  void _log(String msg) {
    debugPrint('[Day] $msg');
    lastDiagnostic = '${DateFormat('HH:mm:ss').format(DateTime.now())} $msg';
  }

  String _studyDate([DateTime? dt]) => StudyDateUtils.todayKey(dt);

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> initialize() async {
    if (_initialized) return;
    _log('초기화 시작');

    // Sub-services 초기화
    await _routine.initialize(_appChannel);
    await _meal.initialize();

    // Sub-service 변경 → DayService notifyListeners 전파
    _routine.addListener(notifyListeners);
    _meal.addListener(notifyListeners);
    _movement.addListener(notifyListeners);

    // Movement action callback
    _movement.onAction = (action, emoji, message) {
      _emitAction(action, emoji, message);
    };

    _log('복원: state=${_routine.state.name}, meal=${_meal.isMealing}');

    // ★ Firestore 기상 기록 복원 — FCM 미도달 시 안전망
    if (_routine.state == DayState.idle) {
      await _recoverWakeFromFirestore();
    }

    try { await _appChannel.invokeMethod('flutterReady'); } catch (_) {}

    await _requestNotificationPermissionOnce();

    // Movement 서비스 초기화
    await _movement.initialize();

    // 외출 중이면 Activity Recognition 재시작
    await _routine.restartActivityRecognitionIfNeeded();

    _initialized = true;
    _log('초기화 완료 (state=${_routine.state.name}, mealing=${_meal.isMealing})');
    notifyListeners();
  }

  /// Firestore에서 오늘 wake 기록 확인 → 상태 복원
  /// (FCM 미도달 / SharedPrefs 유실 대비 안전망)
  Future<void> _recoverWakeFromFirestore() async {
    try {
      final dateStr = _studyDate();
      final records = await FirebaseService()
          .getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[dateStr];
      if (tr?.wake != null) {
        _routine.setState(DayState.awake);
        await _routine.saveState();
        _routine.startWakeReminder();
        BusService().startPolling();
        _log('Firestore 기상 복원: ${tr!.wake} → awake');
      }
    } catch (e) {
      _log('기상 복원 실패 (무시): $e');
    }
  }

  // ═══════════════════════════════════════════
  //  Action dedup (30s)
  // ═══════════════════════════════════════════

  bool _isDuplicate(ActionType type) {
    final now = DateTime.now();
    final last = _lastActionTime[type];
    if (last != null && now.difference(last) < _dedupWindow) {
      _log('중복 액션: ${type.name} (${now.difference(last).inSeconds}s ago)');
      return true;
    }
    _lastActionTime[type] = now;
    return false;
  }

  // ═══════════════════════════════════════════
  //  Unified dispatch
  // ═══════════════════════════════════════════

  Future<void> _dispatch(ActionType type) async {
    if (_isDuplicate(type)) return;

    final now = DateTime.now();
    final dateStr = _studyDate(now);
    final timeStr = DateFormat('HH:mm').format(now);

    // Auto-wake
    if (_routine.state == DayState.idle && type != ActionType.wake) {
      _log('Auto-wake: ${type.name}');
      await _handleWake(dateStr, timeStr, auto: true);
    }

    switch (type) {
      case ActionType.wake:   await _handleWake(dateStr, timeStr); break;
      case ActionType.outing: await _handleOuting(dateStr, timeStr); break;
      case ActionType.study:  await _handleStudy(dateStr, timeStr); break;
      case ActionType.meal:   await _handleMeal(dateStr, timeStr); break;
      case ActionType.sleep:  await _handleSleep(dateStr, timeStr); break;
    }
    notifyListeners();
  }

  /// 외부에서 액션 트리거 (도어센서, SafetyNet, 홈 버튼 등)
  Future<String> triggerAction(ActionType type) async {
    _lastActionTime.remove(type);
    try {
      await _dispatch(type);
      return '${type.name} OK (state=${_routine.state.name}, meal=${_meal.isMealing})';
    } catch (e) { return '에러: $e'; }
  }

  /// @deprecated Use triggerAction instead
  Future<String> manualTestRole(ActionType role) => triggerAction(role);

  /// @deprecated Use triggerAction instead
  Future<void> triggerRole(ActionType role) => triggerAction(role);

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
    try { await _appChannel.invokeMethod('requestNotificationPermission'); } catch (_) {}
  }

  @override
  void dispose() {
    _routine.removeListener(notifyListeners);
    _meal.removeListener(notifyListeners);
    _movement.removeListener(notifyListeners);
    super.dispose();
  }
}
