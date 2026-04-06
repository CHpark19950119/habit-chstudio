import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/iot_models.dart';
import '../models/models.dart';
import 'door_sensor_service.dart';
import 'day_service.dart';
import 'safety_net_service.dart';

/// 기상 감지 인터페이스
abstract class WakeDetector {
  Future<void> start();
  void stop();
}

/// 수동 기상 — UI 버튼으로 직접 호출
class ManualWakeDetector implements WakeDetector {
  @override
  Future<void> start() async {}
  @override
  void stop() {}
}

/// 센서 기상 — 도어센서 문 열림으로 자동 감지
class SensorWakeDetector implements WakeDetector {
  StreamSubscription<DoorEvent>? _sub;
  String? _lastWakeDate;

  @override
  Future<void> start() async {
    stop();

    // DoorSensorService가 비활성이면 활성화
    final door = DoorSensorService();
    if (!door.enabled) {
      await door.setEnabled(true);
    }

    _sub = door.eventStream.listen(_onDoorEvent);
    debugPrint('[SensorWake] listening started');
  }

  @override
  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  /// 테스트용: _lastWakeDate 리셋 (설정 화면에서 호출)
  static void resetForTest() {
    final instance = WakeService();
    if (instance._detector is SensorWakeDetector) {
      (instance._detector as SensorWakeDetector)._lastWakeDate = null;
    }
  }

  void _onDoorEvent(DoorEvent event) {
    if (event.type != DoorState.open) return;

    // DayState가 idle일 때만
    final nfcState = DayService().state;
    if (nfcState != DayState.idle) return;

    // 7시 이전 무시 (새벽 화장실 등 오탐 방지)
    final now = DateTime.now();
    if (now.hour < 7) return;

    // 하루 한 번만 (안전망)
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (_lastWakeDate == today) return;
    _lastWakeDate = today;

    debugPrint('[SensorWake] 문 열림 → 기상 (${now.hour}:${now.minute.toString().padLeft(2, '0')})');
    WakeService().recordWake(auto: true);
  }
}

/// WakeService — 기상 기록 전용 서비스
class WakeService {
  static final WakeService _instance = WakeService._internal();
  factory WakeService() => _instance;
  WakeService._internal();

  bool _initialized = false;
  WakeDetector _detector = ManualWakeDetector();
  String _mode = 'sensor'; // 'manual' | 'sensor'
  bool _debugMode = false;
  int _wakeStartMin = 390;  // 6:30 AM (분)
  int _wakeEndMin = 780;    // 1:00 PM (분)

  WakeDetector get detector => _detector;
  String get mode => _mode;
  bool get debugMode => _debugMode;
  int get wakeStartMin => _wakeStartMin;
  int get wakeEndMin => _wakeEndMin;

  /// 초기화 — app_init에서 호출
  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();
    _mode = prefs.getString('wake_mode') ?? 'sensor';
    _debugMode = prefs.getBool('wake_debug_mode') ?? false;
    _wakeStartMin = prefs.getInt('wake_start_min') ?? 390;
    _wakeEndMin = prefs.getInt('wake_end_min') ?? 780;

    if (_mode == 'sensor') {
      _detector = SensorWakeDetector();
    } else {
      _detector = ManualWakeDetector();
    }

    await _detector.start();
    _initialized = true;
    debugPrint('[WakeService] init: mode=$_mode');
  }

  /// 모드 전환
  Future<void> setMode(String newMode) async {
    if (newMode == _mode) return;
    _detector.stop();

    _mode = newMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wake_mode', newMode);

    if (newMode == 'sensor') {
      _detector = SensorWakeDetector();
    } else {
      _detector = ManualWakeDetector();
    }

    await _detector.start();
    debugPrint('[WakeService] mode changed: $_mode');
  }

  /// 디버그 모드 전환
  Future<void> setDebugMode(bool value) async {
    _debugMode = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('wake_debug_mode', value);
    debugPrint('[WakeService] debugMode=$_debugMode');
  }

  /// 감지 시간대 변경 (분 단위, 0~1439)
  Future<void> setWakeWindow(int startMin, int endMin) async {
    _wakeStartMin = startMin;
    _wakeEndMin = endMin;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('wake_start_min', startMin);
    await prefs.setInt('wake_end_min', endMin);
    debugPrint('[WakeService] window=${_fmtMin(startMin)}~${_fmtMin(endMin)}');
  }

  static String _fmtMin(int m) =>
      '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  // ★ AUDIT FIX: Q-03 — deprecated manualTestRole → triggerAction
  /// 기상 기록 — DayService.triggerAction(wake) 위임
  /// auto=true: 센서 자동 기상 → 기록 후 사후 확인 알림
  Future<void> recordWake({bool auto = false}) async {
    final result = await DayService().triggerAction(ActionType.wake);
    debugPrint('[WakeService] recordWake(auto=$auto): $result');
    if (auto) {
      // 자동 기상 사후 확인: 기록은 이미 저장, 크리처가 확인 요청
      Future.delayed(const Duration(seconds: 3), () {
        SafetyNetService().triggerAutoWakeConfirm();
      });
    }
  }
}
