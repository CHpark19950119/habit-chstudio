import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../utils/study_date_utils.dart';
import 'bus_service.dart';
import 'telegram_service.dart';
import 'day_service.dart' show DayState;

/// RoutineService — DayState FSM, 상태 저장/복원, 리마인더
class RoutineService extends ChangeNotifier with WidgetsBindingObserver {
  static final RoutineService _instance = RoutineService._internal();
  factory RoutineService() => _instance;
  RoutineService._internal();

  // ═══ State ═══
  DayState _state = DayState.idle;
  bool _initialized = false;

  // ═══ Reminders ═══
  Timer? _wakeReminder;
  Timer? _mealReminder;

  // ═══ MethodChannel (Activity Recognition 제어용) ═══
  MethodChannel? _nfcChannel;

  // ═══ Getters ═══
  DayState get state => _state;
  bool get isOut => _state == DayState.outing;
  bool get isStudying => _state == DayState.studying;

  // ═══ 로깅 ═══
  String lastDiagnostic = '';
  void _log(String msg) {
    debugPrint('[Routine] $msg');
    lastDiagnostic = '${DateFormat('HH:mm:ss').format(DateTime.now())} $msg';
  }

  String _studyDate([DateTime? dt]) => StudyDateUtils.todayKey(dt);

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> initialize(MethodChannel nfcChannel) async {
    if (_initialized) return;
    _nfcChannel = nfcChannel;
    await _restoreState();
    WidgetsBinding.instance.addObserver(this);
    _initialized = true;
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
    await prefs.reload();
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

  // ═══════════════════════════════════════════
  //  상태 전환
  // ═══════════════════════════════════════════

  /// 외부 이벤트(FCM/CF) → UI 상태만 변경 (timeRecords 쓰기 없음)
  void forceState(DayState newState) {
    if (_state == newState) return;
    _log('forceState: ${_state.name} → ${newState.name}');
    final prevState = _state;
    _state = newState;
    _saveState();
    if (newState == DayState.awake) {
      startWakeReminder();
      BusService().startPolling();
    } else if (newState == DayState.outing) {
      cancelReminders();
      BusService().stopPolling();
      try { _nfcChannel?.invokeMethod('startActivityRecognition'); } catch (_) {}
    }
    // 외출 → 귀가/기타 전환 시 Activity Recognition 끄기
    if (prevState == DayState.outing && newState != DayState.outing) {
      try { _nfcChannel?.invokeMethod('stopActivityRecognition'); } catch (_) {}
    }
    notifyListeners();
  }

  void forceStudyState(bool value) {
    if (value) { _state = DayState.studying; }
    else if (_state == DayState.studying) { _state = DayState.returned; }
    _saveState();
    notifyListeners();
  }

  /// 직접 상태 설정 (action handler용, notifyListeners 호출 안 함)
  void setState(DayState newState) {
    _state = newState;
  }

  // ═══════════════════════════════════════════
  //  상태 저장/복원 (SharedPreferences)
  // ═══════════════════════════════════════════

  Future<void> _saveState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nfc_state', _state.name);
    await prefs.setString('nfc_state_date', _studyDate());
  }

  /// 외부에서 호출 가능한 저장 (action handler에서 사용)
  Future<void> saveState() => _saveState();

  Future<void> _restoreState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString('nfc_state_date');
    if (savedDate == _studyDate()) {
      _state = DayState.values.firstWhere(
        (s) => s.name == (prefs.getString('nfc_state') ?? 'idle'),
        orElse: () => DayState.idle);
      _log('복원: state=${_state.name}');
    } else {
      _state = DayState.idle;
      await _saveState();
      _log('날짜 변경 → 리셋');
    }
  }

  // ═══════════════════════════════════════════
  //  Reminders
  // ═══════════════════════════════════════════

  void startWakeReminder() {
    _wakeReminder?.cancel();
    _wakeReminder = Timer(const Duration(minutes: 60), () {
      if (_state == DayState.awake) {
        TelegramService().sendNfc('⏰ 기상 60분 — 공부 시작하세요!');
      }
    });
  }

  void startMealReminder() {
    _mealReminder?.cancel();
    _mealReminder = Timer(const Duration(hours: 4), () {
      if (_state == DayState.studying) {
        TelegramService().sendNfc('🍽 공부 4시간 — 식사하세요!');
      }
    });
  }

  void cancelReminders() {
    _wakeReminder?.cancel();
    _mealReminder?.cancel();
  }

  // ═══════════════════════════════════════════
  //  Activity Recognition 재시작 (앱 업데이트 대응)
  // ═══════════════════════════════════════════

  Future<void> restartActivityRecognitionIfNeeded() async {
    if (_state == DayState.outing) {
      _log('외출 중 → Activity Recognition 재시작');
      try { await _nfcChannel?.invokeMethod('startActivityRecognition'); } catch (_) {}
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cancelReminders();
    super.dispose();
  }
}
