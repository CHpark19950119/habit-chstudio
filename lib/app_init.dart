import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';

import 'services/firebase_service.dart';
import 'services/local_cache_service.dart';
import 'services/day_service.dart';
import 'services/door_sensor_service.dart';
import 'services/report_service.dart';
import 'services/wake_service.dart';
import 'services/sleep_service.dart';
import 'services/widget_render_service.dart';
import 'services/fcm_service.dart';
import 'services/safety_net_service.dart';
import 'services/data_audit_service.dart';
import 'services/write_queue_service.dart';

class AppInit {
  static Future<void> run() async {
    // ── Phase 0: Locale 초기화 (DateFormat 'ko' 사용 전 필수) ──
    await initializeDateFormatting('ko', null);

    // ── Phase 1: Firebase + LocalCache (필수 선행) ──
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

    // ★ Firestore SDK 캐시 복구 (clearPersistence는 settings 전에 호출 필수)
    await _clearPersistenceIfNeeded();

    // ★ Firestore 오프라인 캐시 비활성화 — 반드시 다른 Firestore 호출 전에
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    await LocalCacheService().init();
    await FirestoreWriteQueue().init();

    // ── Phase 1.5: Day Rollover (비블로킹 — Phase 2와 병렬 실행) ──
    final rolloverFuture = FirebaseService().checkDayRollover()
        .timeout(const Duration(seconds: 12))
        .catchError((e) { debugPrint('[AppInit] rollover error: $e'); });

    // ── Phase 2: 서비스 초기화 (병렬, 개별 try-catch) — rollover와 동시 진행 ──
    await Future.wait([
      DayService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
    ]);

    // ★ rollover 완료 대기 (센서 서비스가 today doc에 의존)
    await rolloverFuture;

    // ── Phase 4a: 센서 기반 서비스 ──
    await Future.wait([
      DoorSensorService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
    ]);

    // ── Phase 4b: 의존 서비스 ──
    await Future.wait([
      WakeService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
      FcmService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
      // SleepService — 기본 disabled, 사용자가 설정 화면에서 토글하면 Health Connect 연동
      SleepService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
    ]);

    // ── Phase 4c: 안전망 서비스 ──
    SafetyNetService().init().timeout(const Duration(seconds: 5)).catchError((_) {});

    // ── Phase 5: 데이터 감사 (1일 1회, 비블로킹) ──
    DataAuditService().runIfNeeded().catchError((e) {
      debugPrint('[AppInit] data audit error: $e');
    });

    // ── Phase 6: 주간 리포트 자동 체크 (일요일) ──
    ReportService().checkWeeklyReport().catchError((_) {});

    // ── Phase 7: 홈 위젯 업데이트 ──
    WidgetRenderService().updateWidget().catchError((_) {});
  }

  /// Firestore SDK 캐시가 깨졌을 때 자동 복구
  /// 연속 3회 타임아웃 시 다음 시작에서 clearPersistence 실행
  static Future<void> _clearPersistenceIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final shouldClear = prefs.getBool('fs_clear_next') ?? false;
      if (shouldClear) {
        debugPrint('[AppInit] ★ Firestore clearPersistence 실행');
        await FirebaseFirestore.instance.clearPersistence();
        await prefs.setBool('fs_clear_next', false);
        await prefs.setInt('fs_timeout_count', 0);
        debugPrint('[AppInit] ★ clearPersistence 완료');
      }
    } catch (e) {
      debugPrint('[AppInit] clearPersistence error: $e');
    }
  }

  /// Firestore 타임아웃 발생 시 호출 — 3회 연속이면 다음 시작에서 캐시 초기화
  static Future<void> recordFirestoreTimeout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final count = (prefs.getInt('fs_timeout_count') ?? 0) + 1;
      await prefs.setInt('fs_timeout_count', count);
      if (count >= 3) {
        await prefs.setBool('fs_clear_next', true);
        debugPrint('[AppInit] ★ 타임아웃 $count회 → 다음 시작 시 clearPersistence 예약');
      }
    } catch (_) {}
  }

  /// Firestore 성공 시 카운터 리셋
  static Future<void> resetFirestoreTimeout() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt('fs_timeout_count') ?? 0) > 0) {
        await prefs.setInt('fs_timeout_count', 0);
      }
    } catch (_) {}
  }
}
