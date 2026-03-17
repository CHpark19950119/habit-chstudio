import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'day_service.dart';

/// ═══════════════════════════════════════════════════
///  수면 자동 감지 서비스
///  화면 꺼짐 30분 → 알림 → 10분 무응답 → 취침 기록
/// ═══════════════════════════════════════════════════
class SleepDetectService {
  static final SleepDetectService _instance = SleepDetectService._();
  factory SleepDetectService() => _instance;
  SleepDetectService._();

  static const _channel = MethodChannel('com.cheonhong.cheonhong_studio/sleep');
  static const _prefKey = 'sleep_detect_enabled';

  bool _enabled = false;
  bool get enabled => _enabled;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_prefKey) ?? false;
    if (_enabled) {
      try {
        await _channel.invokeMethod('startMonitoring');
      } catch (e) {
        debugPrint('[SleepDetect] startMonitoring error: $e');
      }
      await checkPendingSleep();
    }
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, value);
    try {
      if (value) {
        await _channel.invokeMethod('startMonitoring');
      } else {
        await _channel.invokeMethod('stopMonitoring');
      }
    } catch (e) {
      debugPrint('[SleepDetect] toggle error: $e');
    }
  }

  /// 앱 재개 시 호출 — 네이티브에서 감지된 수면 이벤트 처리
  Future<void> checkPendingSleep() async {
    if (!_enabled) return;
    try {
      final result = await _channel.invokeMethod<Map>('consumeSleepDetection');
      if (result == null) return;

      final timeStr = result['time'] as String?;
      if (timeStr == null) return;

      final timeMs = int.tryParse(timeStr);
      if (timeMs == null) return;

      final sleepTime = DateTime.fromMillisecondsSinceEpoch(timeMs);
      debugPrint('[SleepDetect] Pending sleep found at $sleepTime');

      await DayService().triggerAutoSleep(sleepTime);
    } catch (e) {
      debugPrint('[SleepDetect] checkPendingSleep error: $e');
    }
  }
}
