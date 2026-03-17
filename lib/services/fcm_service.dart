import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import '../models/models.dart';
import 'day_service.dart';

// ═══════════════════════════════════════════════════════════
//  FCM Background Handler + Geofence Foreground Service
// ═══════════════════════════════════════════════════════════

const String _uid = 'sJ8Pxusw9gR0tNR44RhkIge7OiG2';
const String _myBot = '8514127849:AAF8_F7SBfm51SGHtp9X5lva7yexdnFyapo';
const String _myChat = '8724548311';
const String _gfBot = '8613977898:AAEuuoTVARS-a9nrDp85NWHHOYM0lRvmZmc';
const String _gfChat = '8624466505';

/// Top-level FCM background handler — 앱이 꺼져있어도 실행됨
@pragma('vm:entry-point')
Future<void> onFcmBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM] bg: ${message.data}');

  final type = message.data['type'];

  if (type == 'wake') {
    // DayState = awake 저장
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nfc_state', 'awake');
    await prefs.setString('nfc_state_date', _todayKey());

    // Geofence foreground service 시작
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cheonhong_geofence',
        channelName: '위치 감시',
        channelDescription: '자동 외출/귀가 감지',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(180000), // 3분
        autoRunOnBoot: false,
        allowWakeLock: true,
      ),
    );
    await FlutterForegroundTask.startService(
      notificationTitle: '📍 위치 감시',
      notificationText: '자동 외출/귀가 감지 중',
      callback: _geofenceCallback,
    );
  } else if (type == 'outing') {
    // CF 30분 확정 → DayState = outing
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('nfc_state', 'outing');
    await prefs.setString('nfc_state_date', _todayKey());
  }
}

@pragma('vm:entry-point')
void _geofenceCallback() {
  FlutterForegroundTask.setTaskHandler(_GeofenceHandler());
}

// ═══════════════════════════════════════════════════════════
//  유틸
// ═══════════════════════════════════════════════════════════

String _todayKey([DateTime? dt]) {
  final now = dt ?? DateTime.now();
  final d = now.hour < 4 ? now.subtract(const Duration(days: 1)) : now;
  return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

String _timeStr([DateTime? dt]) {
  final now = dt ?? DateTime.now();
  return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
}

Future<void> _sendBoth(String msg) async {
  try {
    await Future.wait([
      http.post(
        Uri.parse('https://api.telegram.org/bot$_myBot/sendMessage'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'chat_id': _myChat, 'text': msg}),
      ),
      http.post(
        Uri.parse('https://api.telegram.org/bot$_gfBot/sendMessage'),
        headers: {'Content-Type': 'application/json; charset=utf-8'},
        body: jsonEncode({'chat_id': _gfChat, 'text': msg}),
      ),
    ]);
  } catch (_) {}
}

// ═══════════════════════════════════════════════════════════
//  Geofence Foreground Task Handler
//  별도 isolate에서 실행 — 앱 죽어도 GPS 폴링 유지
// ═══════════════════════════════════════════════════════════

class _GeofenceHandler extends TaskHandler {
  bool _isHome = true;
  int _exitCount = 0;
  int _enterCount = 0;
  double? _homeLat;
  double? _homeLng;
  static const double _radius = 150.0;
  static const int _confirm = 2;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final prefs = await SharedPreferences.getInstance();
    _homeLat = prefs.getDouble('geofence_home_lat');
    _homeLng = prefs.getDouble('geofence_home_lng');
    _isHome = prefs.getBool('geofence_is_home') ?? true;
    debugPrint('[GeoTask] start: $_homeLat,$_homeLng isHome=$_isHome');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _check();
  }

  Future<void> _check() async {
    if (_homeLat == null || _homeLng == null) return;
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final dist = Geolocator.distanceBetween(
        _homeLat!, _homeLng!, pos.latitude, pos.longitude,
      );

      if (dist > _radius) {
        _enterCount = 0;
        _exitCount++;
        if (_isHome && _exitCount >= _confirm) {
          _isHome = false;
          _exitCount = 0;
          await _saveHome(false);
          await _onExit(pos);
        }
      } else {
        _exitCount = 0;
        _enterCount++;
        if (!_isHome && _enterCount >= _confirm) {
          _isHome = true;
          _enterCount = 0;
          await _saveHome(true);
          await _onEnter();
        }
      }

      // ★ 매 폴링마다 위치 저장 → 헤드위그 "어디야" 응답용
      FirebaseFirestore.instance.doc('users/$_uid/data/iot').set({
        'lastLocation': {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true)).catchError((_) {});

      FlutterForegroundTask.updateService(
        notificationTitle: '📍 위치 감시',
        notificationText: '${_isHome ? "집" : "외출 중"} · ${dist.toInt()}m',
      );
    } catch (e) {
      debugPrint('[GeoTask] check: $e');
    }
  }

  Future<void> _onExit(Position pos) async {
    final t = _timeStr();
    try {
      // data/iot에만 기록 — CF onIotWrite가 timeRecords + 텔레그램 처리
      await FirebaseFirestore.instance.doc('users/$_uid/data/iot').set({
        'movement': {
          'pending': false,
          'type': 'out',
          'leftAt': FieldValue.serverTimestamp(),
          'leftAtLocal': t,
          'source': 'geofence_fg',
          'confirmedAt': FieldValue.serverTimestamp(),
        },
        'lastLocation': {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'updatedAt': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nfc_state', 'outing');
      await prefs.setString('nfc_state_date', _todayKey());
      debugPrint('[GeoTask] exit event → iot: $t');
    } catch (e) {
      debugPrint('[GeoTask] exit err: $e');
    }
  }

  Future<void> _onEnter() async {
    final t = _timeStr();
    try {
      // data/iot에만 기록 — CF onIotWrite가 timeRecords + 텔레그램 처리
      await FirebaseFirestore.instance.doc('users/$_uid/data/iot').update({
        'movement.type': 'home',
        'movement.returnedAt': FieldValue.serverTimestamp(),
        'movement.returnedAtLocal': t,
        'movement.source': 'geofence_fg',
      });

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('nfc_state', 'returned');
      await prefs.setString('nfc_state_date', _todayKey());
      debugPrint('[GeoTask] enter event → iot: $t');
    } catch (e) {
      debugPrint('[GeoTask] enter err: $e');
    }
  }

  Future<void> _saveHome(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('geofence_is_home', v);
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

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
    }
  }

  Future<void> init() async {
    try {
      await FirebaseMessaging.instance.requestPermission(
        alert: false, badge: false, sound: false,
      );
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.doc('users/$_uid/data/iot').set(
          {'fcmToken': token},
          SetOptions(merge: true),
        );
        debugPrint('[FCM] token: ${token.substring(0, 20)}...');
      }
      FirebaseMessaging.instance.onTokenRefresh.listen((t) {
        FirebaseFirestore.instance.doc('users/$_uid/data/iot').set(
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
