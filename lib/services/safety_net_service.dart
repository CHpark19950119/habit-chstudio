import 'dart:async';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Colors, showDialog;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/study_date_utils.dart';
import '../models/iot_models.dart';
import 'routine_service.dart';
import '../models/models.dart' show ActionType;
import 'day_service.dart';
import 'geofence_service.dart';
import 'door_sensor_service.dart';
import 'meal_service.dart';
import 'movement_service.dart';
import 'firebase_service.dart';
import '../main.dart' show navigatorKey;
import '../widgets/creature_alert_overlay.dart';

/// 안전망 체크 타입
enum SafetyCheck {
  wakeMiss,      // idle + (문 열림 OR 9시 이후)
  outingMiss,    // not outing + GPS 집 밖
  returnMiss,    // outing + GPS 집 안
  mealMiss,      // studying + 식사 미기록 + 4시간 경과
  abnormalData,  // 시간 순서 이상
  stayLocation,  // outing + still (체류) → 어디에 있어?
}

/// ═══════════════════════════════════════════════════════════
///  SafetyNetService — 센서 누락 감지 안전망
///  5분마다 DayState vs 센서 상태 교차 검증
///  불일치 시 알림 → 확인하면 누락된 액션 실행
/// ═══════════════════════════════════════════════════════════
class SafetyNetService {
  static final SafetyNetService _instance = SafetyNetService._();
  factory SafetyNetService() => _instance;
  SafetyNetService._();

  bool _enabled = false;
  bool _initialized = false;
  Timer? _timer;
  static const Duration _checkInterval = Duration(minutes: 5);
  static const Duration _alertCooldown = Duration(minutes: 30);

  final FlutterLocalNotificationsPlugin _notifPlugin =
      FlutterLocalNotificationsPlugin();

  // 스팸 방지: 같은 알림 30분 쿨다운
  final Map<String, DateTime> _shownAlerts = {};

  // 알림 ID
  static const Map<SafetyCheck, int> _notifIds = {
    SafetyCheck.wakeMiss: 8001,
    SafetyCheck.outingMiss: 8002,
    SafetyCheck.returnMiss: 8003,
    SafetyCheck.mealMiss: 8004,
    SafetyCheck.abnormalData: 8005,
    SafetyCheck.stayLocation: 8006,
  };

  // 액션 ID
  static const String _actionConfirmWake = 'safety_confirm_wake';
  static const String _actionConfirmOuting = 'safety_confirm_outing';
  static const String _actionConfirmReturn = 'safety_confirm_return';
  static const String _actionConfirmMeal = 'safety_confirm_meal';
  static const String _actionDismiss = 'safety_dismiss';
  static const String _actionLocSka = 'safety_loc_ska';
  static const String _actionLocLibrary = 'safety_loc_library';
  static const String _actionLocOther = 'safety_loc_other';

  bool get enabled => _enabled;

  void _log(String msg) => debugPrint('[SafetyNet] $msg');

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('safety_net_enabled') ?? false;

    await _initNotifications();
    await _consumePendingActions();

    if (_enabled) _startTimer();
    _initialized = true;
    _log('init: enabled=$_enabled');
  }

  Future<void> _initNotifications() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);

    await _notifPlugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationAction,
    );

    final androidPlugin = _notifPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'safety_net',
      '안전망 알림',
      description: '센서 누락 감지 알림',
      importance: Importance.high,
    ));
  }

  /// 알림 버튼 탭 콜백
  void _onNotificationAction(NotificationResponse response) {
    final actionId = response.actionId ?? '';
    if (actionId == _actionDismiss || actionId.isEmpty) return;

    _log('action confirmed: $actionId');

    switch (actionId) {
      case _actionConfirmWake:
        DayService().manualTestRole(ActionType.wake);
        break;
      case _actionConfirmOuting:
        DayService().manualTestRole(ActionType.outing);
        break;
      case _actionConfirmReturn:
        DayService().manualTestRole(ActionType.outing); // 토글 → 귀가
        break;
      case _actionConfirmMeal:
        DayService().manualTestRole(ActionType.meal);
        break;
      case _actionLocSka:
        _recordStayLocation('스카');
        break;
      case _actionLocLibrary:
        _recordStayLocation('도서관');
        break;
      case _actionLocOther:
        _recordStayLocation('기타');
        break;
    }
  }

  /// 앱 재시작 시 SharedPreferences에 저장된 pending action 처리
  Future<void> _consumePendingActions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getString('safety_pending_action');
      if (pending != null) {
        await prefs.remove('safety_pending_action');
        _log('consuming pending action: $pending');
        switch (pending) {
          case 'wake': DayService().manualTestRole(ActionType.wake); break;
          case 'outing': DayService().manualTestRole(ActionType.outing); break;
          case 'meal': DayService().manualTestRole(ActionType.meal); break;
        }
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  //  타이머
  // ═══════════════════════════════════════════

  void _startTimer() {
    _stopTimer();
    _timer = Timer.periodic(_checkInterval, (_) => runChecks());
    // 초기화 후 1분 뒤 첫 체크 (서비스들이 안정화될 시간)
    Future.delayed(const Duration(minutes: 1), () => runChecks());
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  // ═══════════════════════════════════════════
  //  핵심: 5분마다 교차 검증
  // ═══════════════════════════════════════════

  Future<void> runChecks() async {
    if (!_enabled) return;
    final routine = RoutineService();
    final geofence = GeofenceService();
    final door = DoorSensorService();
    final now = DateTime.now();
    final todayKey = StudyDateUtils.todayKey(now);

    // ── 1. 기상 미감지 ──
    if (routine.state == DayState.idle) {
      // ★ 실제 Firestore wake 기록 확인 — 기록 있으면 스킵
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final todayRecord = records[todayKey];
      final alreadyWoke = todayRecord?.wake != null;

      if (!alreadyWoke) {
        final doorOpened = door.lastDoorState == DoorState.open
            && door.lastEventTime != null
            && door.lastEventTime!.day == now.day;
        final pastNine = now.hour >= 9;

        if (doorOpened || pastNine) {
          _maybeAlert(SafetyCheck.wakeMiss, todayKey,
              title: '아직 자고 있어?',
              body: pastNine ? '9시가 넘었어요' : '문이 열렸는데 기상 안 됨',
              confirmActionId: _actionConfirmWake);
        }
      }
    }

    // ── 2. 외출 미감지 ──
    if (routine.state != DayState.outing
        && routine.state != DayState.idle
        && routine.state != DayState.sleeping
        && geofence.enabled && geofence.hasHome && !geofence.isHome) {
      _maybeAlert(SafetyCheck.outingMiss, todayKey,
          title: '나간 거야?',
          body: 'GPS가 집 밖인데 외출 상태가 아니에요',
          confirmActionId: _actionConfirmOuting);
    }

    // ── 3. 귀가 미감지 ──
    if (routine.state == DayState.outing
        && geofence.enabled && geofence.hasHome && geofence.isHome) {
      _maybeAlert(SafetyCheck.returnMiss, todayKey,
          title: '돌아온 거야?',
          body: 'GPS가 집인데 아직 외출 중이에요',
          confirmActionId: _actionConfirmReturn);
    }

    // ── 4. 식사 미기록 ──
    if (routine.state == DayState.studying && !MealService().isMealing) {
      await _checkMealMiss(todayKey, now);
    }

    // ── 5. 비정상 데이터 ──
    await _checkAbnormalData(todayKey);

    // ── 6. 체류 감지 시 장소 확인 ──
    if (routine.state == DayState.outing) {
      final activity = MovementService().currentActivity;
      if (activity == 'still') {
        _maybeLocationAlert(todayKey);
      }
    }
  }

  Future<void> _checkMealMiss(String todayKey, DateTime now) async {
    try {
      final records = await FirebaseService().getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr == null || tr.study == null) return;

      // 오늘 식사 기록 있으면 스킵
      if (tr.meals.isNotEmpty) return;

      // 공부 시작 후 4시간 경과?
      final studyParts = tr.study!.split(':');
      final studyMin = int.parse(studyParts[0]) * 60 + int.parse(studyParts[1]);
      final nowMin = now.hour * 60 + now.minute;
      if (nowMin - studyMin >= 240) {
        _maybeAlert(SafetyCheck.mealMiss, todayKey,
            title: '밥 먹었어?',
            body: '공부 시작(${tr.study})부터 4시간 넘었어요',
            confirmActionId: _actionConfirmMeal);
      }
    } catch (_) {}
  }

  Future<void> _checkAbnormalData(String todayKey) async {
    try {
      final records = await FirebaseService().getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr == null) return;

      int? toMin(String? t) {
        if (t == null) return null;
        final p = t.split(':');
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }

      final wake = toMin(tr.wake);
      final study = toMin(tr.study);
      final outing = toMin(tr.outing);
      final ret = toMin(tr.returnHome);

      bool abnormal = false;
      if (study != null && wake != null && study < wake) abnormal = true;
      if (ret != null && outing != null && ret < outing) abnormal = true;
      if (outing != null && wake != null && outing < wake) abnormal = true;

      if (abnormal) {
        _maybeAlert(SafetyCheck.abnormalData, todayKey,
            title: '데이터 이상 감지',
            body: '시간 순서가 맞지 않아요 — 확인 필요',
            confirmActionId: '');
      }
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  //  알림 발송 (쿨다운 적용)
  // ═══════════════════════════════════════════

  void _maybeAlert(SafetyCheck check, String dateKey, {
    required String title,
    required String body,
    required String confirmActionId,
  }) {
    final key = '${check.name}_$dateKey';

    // 쿨다운 체크
    final lastShown = _shownAlerts[key];
    if (lastShown != null &&
        DateTime.now().difference(lastShown) < _alertCooldown) {
      return;
    }
    _shownAlerts[key] = DateTime.now();

    // ★ 포그라운드: 크리쳐 오버레이
    final ctx = navigatorKey.currentContext;
    if (ctx != null && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _showCreatureOverlay(ctx, check, title, body, confirmActionId);
      _log('Creature alert: $title — $body');
      return;
    }

    // ★ 백그라운드: 기존 알림
    _showNotification(check, title, body, confirmActionId);
    _log('Notification alert: $title — $body');
  }

  void _showCreatureOverlay(BuildContext ctx, SafetyCheck check,
      String title, String body, String confirmActionId) {
    CreatureAlertOverlay.show(
      context: ctx,
      title: title,
      body: body,
      confirmLabel: confirmActionId.isNotEmpty ? '맞아' : null,
      dismissLabel: '아니야',
      onConfirm: confirmActionId.isNotEmpty ? () {
        _onNotificationAction(NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: confirmActionId,
        ));
      } : null,
      onDismiss: () {
        _notifPlugin.cancel(_notifIds[check]!);
      },
    );
  }

  void _showNotification(SafetyCheck check, String title, String body,
      String confirmActionId) {
    final actions = <AndroidNotificationAction>[];
    if (confirmActionId.isNotEmpty) {
      actions.add(AndroidNotificationAction(
        confirmActionId, '맞아',
        showsUserInterface: true,
      ));
    }
    actions.add(const AndroidNotificationAction(
      _actionDismiss, '아니야',
    ));

    _notifPlugin.show(
      _notifIds[check]!,
      title,
      body,
      NotificationDetails(android: AndroidNotificationDetails(
        'safety_net', '안전망 알림',
        importance: Importance.high,
        priority: Priority.high,
        actions: actions,
      )),
      payload: check.name,
    );
  }

  // ═══════════════════════════════════════════
  //  외부에서 알림 해제 (정상 액션 발생 시)
  // ═══════════════════════════════════════════

  void clearAlert(SafetyCheck check) {
    _notifPlugin.cancel(_notifIds[check]!);
    final todayKey = StudyDateUtils.todayKey();
    _shownAlerts.remove('${check.name}_$todayKey');
  }

  // ═══════════════════════════════════════════
  //  설정
  // ═══════════════════════════════════════════

  // ═══════════════════════════════════════════
  //  체류 장소 확인 알림
  // ═══════════════════════════════════════════

  void _maybeLocationAlert(String dateKey) {
    final key = '${SafetyCheck.stayLocation.name}_$dateKey';
    final lastShown = _shownAlerts[key];
    if (lastShown != null &&
        DateTime.now().difference(lastShown) < _alertCooldown) {
      return;
    }
    _shownAlerts[key] = DateTime.now();

    // ★ 포그라운드: 크리쳐 장소 오버레이
    final ctx = navigatorKey.currentContext;
    if (ctx != null && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _showLocationOverlay(ctx);
      _log('Creature location alert');
      return;
    }

    _notifPlugin.show(
      _notifIds[SafetyCheck.stayLocation]!,
      '어디에 있어?',
      '체류 중인 것 같아요',
      NotificationDetails(android: AndroidNotificationDetails(
        'safety_net', '안전망 알림',
        importance: Importance.high,
        priority: Priority.high,
        actions: const [
          AndroidNotificationAction(_actionLocSka, '스카', showsUserInterface: true),
          AndroidNotificationAction(_actionLocLibrary, '도서관', showsUserInterface: true),
          AndroidNotificationAction(_actionLocOther, '기타', showsUserInterface: true),
        ],
      )),
      payload: 'stayLocation',
    );
    _log('Alert: 어디에 있어? (체류 감지)');
  }

  void _showLocationOverlay(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => CreatureAlertOverlay(
        title: '어디에 있어?',
        body: '체류 중인 것 같아요',
        confirmLabel: null,
        dismissLabel: null,
        onConfirm: null,
        onDismiss: null,
      ),
    );
    // 3개 버튼 별도 다이얼로그 — 크리쳐 오버레이 위에 장소 선택
    Future.delayed(const Duration(milliseconds: 500), () {
      if (ctx.mounted) {
        Navigator.of(ctx).pop(); // 기본 오버레이 닫기
        _showLocationPickerOverlay(ctx);
      }
    });
  }

  void _showLocationPickerOverlay(BuildContext ctx) {
    CreatureAlertOverlay.show(
      context: ctx,
      title: '어디에 있어?',
      body: '체류 중인 것 같아요',
      confirmLabel: '스카',
      dismissLabel: '도서관',
      onConfirm: () => _recordStayLocation('스카'),
      onDismiss: () => _recordStayLocation('도서관'),
    );
  }

  /// 체류 장소 Firestore 기록
  static void _recordStayLocation(String location) {
    try {
      final now = DateTime.now();
      final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final dateStr = StudyDateUtils.todayKey(now);

      FirebaseFirestore.instance
          .doc(kIotDoc)
          .update({
        'stayLocation': {
          'place': location,
          'time': timeStr,
          'date': dateStr,
        }
      });
      debugPrint('[SafetyNet] 체류 장소 기록: $location ($timeStr)');
    } catch (e) {
      debugPrint('[SafetyNet] 체류 장소 기록 에러: $e');
    }
  }

  /// 테스트용: 강제 알림 발송
  void testAlert() {
    _maybeAlert(SafetyCheck.mealMiss, 'test_${DateTime.now().millisecondsSinceEpoch}',
        title: '밥 먹었어?',
        body: '안전망 테스트 알림이에요',
        confirmActionId: _actionConfirmMeal);
    _log('테스트 알림 발송');
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('safety_net_enabled', value);
    if (value) _startTimer(); else _stopTimer();
    _log('enabled=$value');
  }
}
