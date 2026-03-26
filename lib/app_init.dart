import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'firebase_options.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_service.dart';
import 'services/focus_service.dart';
import 'services/local_cache_service.dart';
import 'services/day_service.dart';
import 'services/cradle_service.dart';
import 'services/geofence_service.dart';
import 'services/door_sensor_service.dart';
import 'services/report_service.dart';
import 'services/sleep_detect_service.dart';
import 'services/wake_service.dart';
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
    await LocalCacheService().init();
    await FirestoreWriteQueue().init();

    // ── Phase 1.5: Day Rollover (경량, 블로킹 OK) ──
    try {
      await FirebaseService().checkDayRollover()
          .timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('[AppInit] rollover error: $e');
    }

    // ── Phase 1.6: stuck rollover 플래그 정리 ──
    try {
      final td = await FirebaseService().getTodayDoc();
      if (td != null && td['_rolloverInProgress'] == true) {
        debugPrint('[AppInit] stuck rollover flag — removing');
        await FirebaseService().updateTodayField(
          '_rolloverInProgress', FieldValue.delete(),
        );
      }
    } catch (_) {}

    // ── Phase 2: 서비스 초기화 (병렬, 개별 try-catch) ──
    await Future.wait([
      FocusService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
      DayService().initialize().timeout(const Duration(seconds: 10)).catchError((_) {}),
    ]);

    // ── Phase 3: 상태 복원 (병렬, 개별 try-catch) ──
    await Future.wait([
      FocusService().restoreState().timeout(const Duration(seconds: 8)).catchError((_) {}),
    ]);

    // ── Phase 4a: 센서 기반 서비스 (순서 의존: Door → Wake, Geo → NFC) ──
    await Future.wait([
      DoorSensorService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
      GeofenceService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
      CradleService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
    ]);

    // ── Phase 4b: Door/Geo 의존 서비스 ──
    await Future.wait([
      WakeService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
      SleepDetectService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
      FcmService().init().timeout(const Duration(seconds: 5)).catchError((_) {}),
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
}
