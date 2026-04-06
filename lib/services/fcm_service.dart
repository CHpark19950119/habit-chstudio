import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import '../utils/study_date_utils.dart'; // ★ AUDIT FIX: Q-01
import 'day_service.dart';

// ═══════════════════════════════════════════════════════════
//  FCM Background Handler + Geofence Foreground Service
// ═══════════════════════════════════════════════════════════

/// Top-level FCM background handler — 앱이 꺼져있어도 실행됨
@pragma('vm:entry-point')
Future<void> onFcmBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM] bg: ${message.data}');

  final type = message.data['type'];

  if (type == 'wake') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nfc_state', 'awake');
    await prefs.setString('nfc_state_date', _todayKey());
  } else if (type == 'outing') {
    // CF 30분 확정 → DayState = outing
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nfc_state', 'outing');
    await prefs.setString('nfc_state_date', _todayKey());
  } else if (type == 'sleep') {
    // CF mmWave 취침 감지 → DayState = sleeping
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nfc_state', 'sleeping');
    await prefs.setString('nfc_state_date', _todayKey());
  }
}

// ★ AUDIT FIX: Q-01 — 중복 구현 제거, StudyDateUtils.todayKey 재사용
String _todayKey([DateTime? dt]) => StudyDateUtils.todayKey(dt);

// ═══════════════════════════════════════════════════════════
//  FcmService — Token Registration
// ═══════════════════════════════════════════════════════════

class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  void _handleFcmAction(Map<String, dynamic> data) {
    final type = data['type'];
    // CF가 이미 timeRecords 기록 → UI 상태만 전환
    if (type == 'wake') {
      DayService().forceState(DayState.awake);
    } else if (type == 'outing' || type == 'studying') {
      DayService().forceState(DayState.outing);
    } else if (type == 'returnHome') {
      DayService().forceState(DayState.returned);
    } else if (type == 'sleep') {
      DayService().triggerAutoSleep(DateTime.now());
    }
  }

  Future<void> init() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: false, badge: false, sound: false,
      );
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.doc(kIotDoc).set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
        debugPrint('[FCM] token: ${token.substring(0, 20)}...');
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        FirebaseFirestore.instance.doc(kIotDoc).set(
          {'fcmToken': t}, SetOptions(merge: true),
        );
      });

      // ★ 포그라운드 수신 — 앱 열려있을 때 즉시 반영
      FirebaseMessaging.onMessage.listen((message) {
        debugPrint('[FCM] fg: ${message.data}');
        _handleFcmAction(message.data);
      });

      // ★ 백그라운드→포그라운드 전환 시 (알림 탭 등)
      FirebaseMessaging.onMessageOpenedApp.listen((message) {
        debugPrint('[FCM] opened: ${message.data}');
        _handleFcmAction(message.data);
      });
    } catch (e) {
      debugPrint('[FCM] init: $e');
    }
  }
}
