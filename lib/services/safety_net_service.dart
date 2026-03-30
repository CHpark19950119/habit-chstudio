import 'dart:async';
import '../constants.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' show Colors, showDialog;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/study_date_utils.dart';
import '../models/iot_models.dart';
import 'routine_service.dart';
import '../models/models.dart' show ActionType, TimeRecord;
import '../models/order_models.dart' show OrderData;
import '../models/creature_mood.dart';
import 'day_service.dart';
import 'creature_service.dart';
import 'door_sensor_service.dart';
import 'meal_service.dart';
import 'firebase_service.dart';
import 'local_cache_service.dart';
import '../main.dart' show navigatorKey;
import '../widgets/creature_alert_overlay.dart';

/// 안전망 체크 타입
enum SafetyCheck {
  wakeMiss,           // idle + (문 열림 OR 9시 이후)
  outingMiss,         // not outing + GPS 집 밖
  returnMiss,         // outing + GPS 집 안
  mealMiss,           // studying + 식사 미기록 + 4시간 경과
  abnormalData,       // 시간 순서 이상
  stayLocation,       // outing + still (체류) → 어디에 있어?
  // ── v2: 분기 이벤트 ──
  homeDayConfirm,     // awake + 외출 없음 + 180분+ → 홈데이 확인
  autoWakeConfirm,    // 자동 기상 직후 사후 확인
  studyEndConfirm,    // studying + 4시간+ → 아직 공부 중?
  lateMealReminder,   // studying + 마지막 식사/공부 시작 5시간+ → 밥 먹었어?
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
    SafetyCheck.homeDayConfirm: 8007,
    SafetyCheck.autoWakeConfirm: 8008,
    SafetyCheck.studyEndConfirm: 8009,
    SafetyCheck.lateMealReminder: 8010,
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
  // v2: 분기 이벤트 액션
  static const String _actionConfirmHomeDay = 'safety_confirm_homeday';
  static const String _actionConfirmAutoWake = 'safety_confirm_autowake';
  static const String _actionDenyAutoWake = 'safety_deny_autowake';
  static const String _actionStudyEndDone = 'safety_study_end_done';
  static const String _actionStudyEndContinue = 'safety_study_end_continue';
  static const String _actionConfirmLateMeal = 'safety_confirm_latemeal';

  bool get enabled => _enabled;

  void _log(String msg) => debugPrint('[SafetyNet] $msg');

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('safety_net_enabled') ?? true;

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
      // ── v2: 분기 이벤트 액션 ──
      case _actionConfirmHomeDay:
        _handleHomeDayConfirm();
        break;
      case _actionConfirmAutoWake:
        // 기상 기록 유지 (정상 기상)
        CreatureService().setMood(CreatureMood.proud);
        break;
      case _actionDenyAutoWake:
        _handleAutoWakeRollback();
        break;
      case _actionStudyEndDone:
        DayService().manualTestRole(ActionType.study); // studying 토글 → 종료
        break;
      case _actionStudyEndContinue:
        // 30분 쿨다운 (자동 적용)
        break;
      case _actionConfirmLateMeal:
        DayService().manualTestRole(ActionType.meal);
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

    // ── 4. 식사 미기록 ──
    if (routine.state == DayState.studying && !MealService().isMealing) {
      await _checkMealMiss(todayKey, now);
    }

    // ── 5. 비정상 데이터 ──
    await _checkAbnormalData(todayKey);

    // ── 6. 홈데이 확인 (homeDayConfirm) ──
    if (routine.state == DayState.awake) {
      await _checkHomeDayConfirm(todayKey, now);
    }

    // ── 8. 장시간 공부 체크 (studyEndConfirm) ──
    if (routine.state == DayState.studying) {
      await _checkStudyEndConfirm(todayKey, now);
    }

    // ── 9. 식사 리마인더 (lateMealReminder) — 기존 mealMiss 보강 ──
    if (routine.state == DayState.studying && !MealService().isMealing) {
      await _checkLateMealReminder(todayKey, now);
    }

    // ── 10. 캐시 신선도 체크 ──
    _checkCacheFreshness();

    // ── 11. 듀얼 문서 동기화 체크 ──
    await _checkDualDocSync();

    // ── 12. 습관 시간 기반 자동 완료 ──
    await _checkTimedHabitTriggers(todayKey, now);
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
  //  v2: 분기 이벤트 체크
  // ═══════════════════════════════════════════

  /// A1. 홈데이 확인 — awake + 외출 없음 + 기상 후 180분+
  Future<void> _checkHomeDayConfirm(String todayKey, DateTime now) async {
    try {
      final records = await FirebaseService().getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr == null || tr.wake == null) return;
      if (tr.outing != null) return; // 외출 기록 있으면 스킵
      if (tr.noOuting) return; // 이미 홈데이 확인됨

      final wakeParts = tr.wake!.split(':');
      final wakeMin = int.parse(wakeParts[0]) * 60 + int.parse(wakeParts[1]);
      final nowMin = now.hour * 60 + now.minute;
      if (nowMin - wakeMin < 180) return; // 3시간 미경과

      final msg = CreatureMessages.pick(CreatureMessages.homeDayConfirm);
      CreatureService().setMood(CreatureMessages.moodForCheck('homeDayConfirm'));
      _maybeAlert(SafetyCheck.homeDayConfirm, todayKey,
          title: msg,
          body: '기상 ${tr.wake}부터 3시간 넘었어',
          confirmActionId: _actionConfirmHomeDay);
    } catch (_) {}
  }

  /// A2. 자동 기상 사후 확인 — WakeService에서 호출
  void triggerAutoWakeConfirm() {
    final todayKey = StudyDateUtils.todayKey();
    final msg = CreatureMessages.pick(CreatureMessages.autoWakeConfirm);
    CreatureService().setMood(CreatureMessages.moodForCheck('autoWakeConfirm'));
    _maybeAlert(SafetyCheck.autoWakeConfirm, todayKey,
        title: msg,
        body: '자동 기상이 감지됐어',
        confirmActionId: _actionConfirmAutoWake,
        denyActionId: _actionDenyAutoWake,
        denyLabel: '아니야');
  }

  /// A3. 장시간 공부 체크 — studying + 4시간+ + studyEnd 없음
  Future<void> _checkStudyEndConfirm(String todayKey, DateTime now) async {
    try {
      final records = await FirebaseService().getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr == null || tr.study == null || tr.studyEnd != null) return;

      final studyParts = tr.study!.split(':');
      final studyMin = int.parse(studyParts[0]) * 60 + int.parse(studyParts[1]);
      final nowMin = now.hour * 60 + now.minute;
      if (nowMin - studyMin < 240) return; // 4시간 미경과

      final msg = CreatureMessages.pick(CreatureMessages.studyEndConfirm);
      CreatureService().setMood(CreatureMessages.moodForCheck('studyEndConfirm'));
      _maybeAlert(SafetyCheck.studyEndConfirm, todayKey,
          title: msg,
          body: '공부 시작(${tr.study})부터 4시간 넘었어',
          confirmActionId: _actionStudyEndDone,
          denyActionId: _actionStudyEndContinue,
          denyLabel: '하는 중');
    } catch (_) {}
  }

  /// A4. 식사 리마인더 — studying + 마지막 식사/공부시작 5시간+
  Future<void> _checkLateMealReminder(String todayKey, DateTime now) async {
    try {
      final records = await FirebaseService().getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr == null || tr.study == null) return;

      final nowMin = now.hour * 60 + now.minute;

      // 기준 시점: 마지막 식사 종료 or 공부 시작
      int baseMin;
      if (tr.meals.isNotEmpty) {
        final lastMeal = tr.meals.last;
        final ref = lastMeal.end ?? lastMeal.start;
        final parts = ref.split(':');
        baseMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      } else {
        final parts = tr.study!.split(':');
        baseMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }

      if (nowMin - baseMin < 300) return; // 5시간 미경과

      final msg = CreatureMessages.pick(CreatureMessages.lateMealReminder);
      CreatureService().setMood(CreatureMessages.moodForCheck('lateMealReminder'));
      _maybeAlert(SafetyCheck.lateMealReminder, todayKey,
          title: msg,
          body: '마지막 식사/공부시작부터 5시간 넘었어',
          confirmActionId: _actionConfirmLateMeal);
    } catch (_) {}
  }

  // ═══════════════════════════════════════════
  //  v2: 분기 이벤트 핸들러
  // ═══════════════════════════════════════════

  /// 홈데이 확인 → noOuting 기록 → 홈 UI 전환
  Future<void> _handleHomeDayConfirm() async {
    try {
      final fb = FirebaseService();
      final todayKey = StudyDateUtils.todayKey();
      final records = await fb.getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr == null) return;

      final updated = tr.copyWith(noOuting: true);
      await fb.updateTimeRecord(todayKey, updated);
      CreatureService().setMood(CreatureMood.proud);

      // 홈 화면 즉시 갱신 — DayService notify → home_screen._onNfcChanged → _load()
      DayService().notifyDataChanged();
      _log('홈데이 확인 기록 완료');
    } catch (e) {
      _log('홈데이 확인 에러: $e');
    }
  }

  /// 자동 기상 롤백 — 기상 기록 삭제 + idle 복원
  Future<void> _handleAutoWakeRollback() async {
    try {
      final fb = FirebaseService();
      final todayKey = StudyDateUtils.todayKey();
      final records = await fb.getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr == null) return;

      final updated = tr.copyWith(clearWake: true);
      await fb.updateTimeRecord(todayKey, updated);

      // idle로 복원
      RoutineService().forceState(DayState.idle);
      _log('자동 기상 롤백 완료');
    } catch (e) {
      _log('자동 기상 롤백 에러: $e');
    }
  }

  /// B4. 캐시 신선도 체크 — 30분+ 미갱신 시 서버 리프레시
  void _checkCacheFreshness() {
    final age = LocalCacheService().getStudyCacheAge();
    if (age != null && age.inMinutes >= 30) {
      _log('캐시 30분+ 경과 → 서버 리프레시');
      FirebaseService().invalidateStudyCache();
      FirebaseService().getStudyData(); // 백그라운드 갱신
    }
  }

  /// B3. 듀얼 문서 동기화 체크 — 최근 5분 내 쓰기 시만
  Future<void> _checkDualDocSync() async {
    if (!LocalCacheService().isWriteProtected()) return; // 최근 쓰기 없으면 스킵
    try {
      final fb = FirebaseService();
      final todayKey = StudyDateUtils.todayKey();

      // study doc에서 timeRecords 읽기
      final studyData = await fb.getStudyData();
      if (studyData == null) return;
      final studyTR = studyData['timeRecords'];
      if (studyTR is! Map) return;
      final studyRecord = studyTR[todayKey];
      if (studyRecord == null) return;

      // today doc에서 timeRecords 읽기
      final todayData = await fb.getTodayDoc();
      if (todayData == null) return;
      final todayRecord = todayData['timeRecords'];
      if (todayRecord == null) return;

      // 핵심 필드 비교
      final sMap = Map<String, dynamic>.from(studyRecord as Map);
      final tMap = Map<String, dynamic>.from(todayRecord as Map);

      bool mismatch = false;
      for (final key in ['wake', 'study', 'studyEnd', 'outing', 'returnHome', 'bedTime']) {
        if (sMap[key] != tMap[key]) {
          mismatch = true;
          _log('듀얼 문서 불일치: $key study=${sMap[key]} today=${tMap[key]}');
        }
      }

      if (mismatch) {
        // lastModified 기준 최신 선택
        final sMod = studyData['lastModified'] as int? ?? 0;
        final tMod = todayData['lastModified'] as int? ?? 0;

        if (sMod >= tMod) {
          // study doc이 최신 → today doc에 동기화
          await fb.updateTodayField('timeRecords', sMap);
          _log('듀얼 동기화: study → today');
        } else {
          // today doc이 최신 → study doc에 동기화
          final tr = TimeRecord.fromMap(todayKey, tMap);
          await fb.updateTimeRecord(todayKey, tr);
          _log('듀얼 동기화: today → study');
        }
      }
    } catch (e) {
      _log('듀얼 동기화 체크 에러: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  습관 시간 기반 자동 완료
  // ═══════════════════════════════════════════

  /// 조건 매핑: autoTrigger → TimeRecord 필드 존재 여부
  static bool _triggerConditionMet(String trigger, TimeRecord tr) {
    switch (trigger) {
      case 'wake': return tr.wake != null;
      case 'study': return tr.study != null;
      case 'outing': return tr.outing != null;
      case 'meal': return tr.meals.isNotEmpty;
      case 'sleep': return tr.bedTime != null;
      default: return false;
    }
  }

  /// triggerTime이 설정된 습관들: now >= triggerTime이고 조건 충족 시 자동 완료
  Future<void> _checkTimedHabitTriggers(String todayKey, DateTime now) async {
    try {
      final fb = FirebaseService();
      final data = await fb.getStudyData();
      if (data == null || data['orderData'] == null) return;
      final orderData = OrderData.fromMap(
          Map<String, dynamic>.from(data['orderData'] as Map));

      // 오늘 TimeRecord
      final records = await fb.getTimeRecords()
          .timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr == null) return;

      final nowMin = now.hour * 60 + now.minute;
      bool changed = false;

      for (final h in orderData.habits) {
        if (h.archived || h.isSettled) continue;
        if (h.autoTrigger == null || h.triggerTime == null) continue;
        if (h.isDoneOn(todayKey)) continue;

        // triggerTime 파싱
        final parts = h.triggerTime!.split(':');
        if (parts.length != 2) continue;
        final triggerMin = int.parse(parts[0]) * 60 + int.parse(parts[1]);

        // 아직 시간 안 됨
        if (nowMin < triggerMin) continue;

        // 조건 충족 확인
        if (!_triggerConditionMet(h.autoTrigger!, tr)) continue;

        // 자동 완료
        h.toggleDate(todayKey);
        changed = true;
        _log('습관 시간 자동완료: ${h.title} (${h.autoTrigger} @ ${h.triggerTime})');
      }

      if (!changed) return;
      await fb.updateField('orderData', orderData.toMap());
      _log('습관 시간 트리거 완료: $todayKey');
    } catch (e) {
      _log('습관 시간 트리거 에러: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  알림 발송 (쿨다운 적용)
  // ═══════════════════════════════════════════

  void _maybeAlert(SafetyCheck check, String dateKey, {
    required String title,
    required String body,
    required String confirmActionId,
    String? denyActionId,
    String? denyLabel,
  }) {
    final key = '${check.name}_$dateKey';

    // 쿨다운 체크
    final lastShown = _shownAlerts[key];
    if (lastShown != null &&
        DateTime.now().difference(lastShown) < _alertCooldown) {
      return;
    }
    _shownAlerts[key] = DateTime.now();

    final effectiveDenyId = denyActionId ?? _actionDismiss;
    final effectiveDenyLabel = denyLabel ?? '아니야';

    // ★ 포그라운드: 크리쳐 오버레이
    final ctx = navigatorKey.currentContext;
    if (ctx != null && WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      _showCreatureOverlay(ctx, check, title, body,
          confirmActionId, effectiveDenyId, effectiveDenyLabel);
      _log('Creature alert: $title — $body');
      return;
    }

    // ★ 백그라운드: 기존 알림
    _showNotification(check, title, body,
        confirmActionId, effectiveDenyId, effectiveDenyLabel);
    _log('Notification alert: $title — $body');
  }

  void _showCreatureOverlay(BuildContext ctx, SafetyCheck check,
      String title, String body, String confirmActionId,
      String denyActionId, String denyLabel) {
    CreatureAlertOverlay.show(
      context: ctx,
      title: title,
      body: body,
      mood: CreatureService().mood,
      confirmLabel: confirmActionId.isNotEmpty ? '맞아' : null,
      dismissLabel: denyLabel,
      onConfirm: confirmActionId.isNotEmpty ? () {
        _onNotificationAction(NotificationResponse(
          notificationResponseType: NotificationResponseType.selectedNotificationAction,
          actionId: confirmActionId,
        ));
      } : null,
      onDismiss: () {
        if (denyActionId != _actionDismiss) {
          _onNotificationAction(NotificationResponse(
            notificationResponseType: NotificationResponseType.selectedNotificationAction,
            actionId: denyActionId,
          ));
        }
        _notifPlugin.cancel(_notifIds[check]!);
      },
    );
  }

  void _showNotification(SafetyCheck check, String title, String body,
      String confirmActionId, String denyActionId, String denyLabel) {
    final actions = <AndroidNotificationAction>[];
    if (confirmActionId.isNotEmpty) {
      actions.add(AndroidNotificationAction(
        confirmActionId, '맞아',
        showsUserInterface: true,
      ));
    }
    actions.add(AndroidNotificationAction(
      denyActionId, denyLabel,
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
