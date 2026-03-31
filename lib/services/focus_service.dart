import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:hive/hive.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import '../models/models.dart';
import 'firebase_service.dart';
import 'write_queue_service.dart';
import 'creature_service.dart';
import '../utils/study_date_utils.dart';
import '../constants.dart';
import 'widget_render_service.dart';

// ══════════════════════════════════════════
//  FocusService v2 — 단순화
//  시작 / 종료 / 일시정지 / 재개 / 모드전환 / 과목변경
//  Hive-first → Firestore 동기화
// ══════════════════════════════════════════

class FocusService extends ChangeNotifier {
  static final FocusService _instance = FocusService._internal();
  factory FocusService() => _instance;
  FocusService._internal();

  static const _boxName = 'focus_data';

  // ── 상태 ──
  bool _isRunning = false;
  bool _isPaused = false;
  String _currentMode = 'study';
  String _currentSubject = '자료해석';
  DateTime? _sessionStart;
  DateTime? _segmentStart;
  int _totalStudyMin = 0;
  int _totalLectureMin = 0;
  int _totalRestMin = 0;
  final List<FocusSegment> _segments = [];
  int _accumulatedActiveSec = 0;

  // ── 일시정지 ──
  DateTime? _pauseStart;
  int _totalPauseSec = 0;
  String? _preModeBeforePause;

  // ── 오늘 기록 (Hive에서 로드) ──
  List<FocusCycle> _todaySessions = [];
  int _todayStudyMinutes = 0;

  // ── 내부 타이머 ──
  Timer? _uiTimer;
  Timer? _liveSyncTimer;

  // ── Getters ──
  bool get isRunning => _isRunning;
  bool get isPaused => _isPaused;
  String get currentMode => _currentMode;
  String get currentSubject => _currentSubject;
  DateTime? get sessionStart => _sessionStart;
  int get totalPauseSec => _totalPauseSec;

  List<FocusCycle> get todaySessions => List.unmodifiable(_todaySessions);
  int get todayStudyMinutes => _todayStudyMinutes;
  int get todaySessionCount => _todaySessions.length;

  // ── 하위 호환 (UI에서 참조하는 것들) ──
  bool get isBathroomBreak => false;
  int get bathroomSec => 0;
  bool get subTimerActive => false;
  bool get isOnCradle => false;
  bool get cradlePaused => false;
  int get cradleFocusSec => 0;
  int get cradleRestSec => 0;
  int get cradleRestCount => 0;
  int get concentrationRate => 100;
  List<int> get cradleRestDurations => const [];
  DateTime? get problemStart => null;
  List<({int seconds, String subject})> get problemLaps => const [];
  int get problemElapsedSec => 0;

  // ── 초기화 ──
  Future<void> initialize() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'cheonhong_focus_silent',
        channelName: '집중 세션 (조용히)',
        channelDescription: 'CHEONHONG STUDIO 집중 타이머',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(1000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
    await _loadTodaySessions();
  }

  // ══════════════════════════════════════════
  //  Hive 세션 기록 CRUD
  // ══════════════════════════════════════════

  Future<Box> _openBox() async => Hive.openBox(_boxName);

  Future<Map<String, List<FocusCycle>>> getHiveSessionsForMonth(String monthPrefix) async {
    final result = <String, List<FocusCycle>>{};
    try {
      final box = await _openBox();
      for (final key in box.keys) {
        if (key is! String || !key.startsWith('sessions_$monthPrefix')) continue;
        final dateStr = key.replaceFirst('sessions_', '');
        final raw = box.get(key);
        if (raw == null) continue;
        final list = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
        final sessions = <FocusCycle>[];
        for (final e in list) {
          try {
            if (e is Map) sessions.add(FocusCycle.fromMap(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
        if (sessions.isNotEmpty) result[dateStr] = sessions;
      }
    } catch (e) {
      debugPrint('[Focus] getHiveSessionsForMonth error: $e');
    }
    return result;
  }

  Future<void> _loadTodaySessions() async {
    final dateStr = StudyDateUtils.todayKey();
    Box? box;
    try {
      box = await _openBox();
      final raw = box.get('sessions_$dateStr');
      if (raw != null) {
        final list = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
        _todaySessions = [];
        for (final e in list) {
          try {
            if (e is Map) _todaySessions.add(FocusCycle.fromMap(Map<String, dynamic>.from(e)));
          } catch (_) {}
        }
      } else {
        _todaySessions = [];
      }
    } catch (e) {
      debugPrint('[Focus] Hive load error: $e');
      _todaySessions = [];
    }

    // Firestore pendingSessions 머지
    try {
      box ??= await _openBox();
      await _mergeFirestoreSessions(dateStr, box);
    } catch (e) {
      debugPrint('[Focus] merge error: $e');
    }

    _todayStudyMinutes = _todaySessions.fold(0, (s, c) => s + c.effectiveMin);
    debugPrint('[Focus] loaded ${_todaySessions.length} sessions ($dateStr, ${_todayStudyMinutes}min)');
  }

  Future<void> _mergeFirestoreSessions(String dateStr, Box box) async {
    try {
      final studyData = await FirebaseService().getStudyData();
      if (studyData == null) return;
      final rawPending = studyData['pendingSessions'];
      if (rawPending == null || rawPending is! Map) return;
      final pending = Map<String, dynamic>.from(rawPending);
      if (pending[dateStr] == null) return;
      final rawDay = pending[dateStr];
      final List<dynamic> remoteList;
      if (rawDay is List) {
        remoteList = rawDay;
      } else if (rawDay is Map) {
        remoteList = (Map<String, dynamic>.from(rawDay)).values.toList();
      } else {
        return;
      }
      if (remoteList.isEmpty) return;
      final localIds = _todaySessions.map((s) => s.id).toSet();
      int merged = 0;
      for (final item in remoteList) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        final id = m['id'] as String? ?? '';
        if (id.isNotEmpty && !localIds.contains(id)) {
          _todaySessions.add(FocusCycle(
            id: id, date: dateStr,
            startTime: m['startTime'] as String? ?? '',
            endTime: m['endTime'] as String? ?? '',
            subject: m['subject'] as String? ?? '',
            segments: [],
            studyMin: m['studyMinutes'] as int? ?? 0,
            lectureMin: m['lectureMinutes'] as int? ?? 0,
            effectiveMin: m['studyMinutes'] as int? ?? 0,
            restMin: m['restMinutes'] as int? ?? 0,
          ));
          merged++;
        }
      }
      if (merged > 0) {
        await box.put('sessions_$dateStr', _todaySessions.map((c) => c.toMap()).toList());
        debugPrint('[Focus] merged $merged pending sessions');
      }
      try {
        FirestoreWriteQueue().enqueue(kStudyDoc, {'pendingSessions.$dateStr': FieldValue.delete()});
      } catch (_) {}
    } catch (e) {
      debugPrint('[Focus] mergePending error: $e');
    }
  }

  Future<void> _saveSessionToHive(FocusCycle cycle) async {
    try {
      final box = await _openBox();
      final dateStr = cycle.date;
      final raw = box.get('sessions_$dateStr');
      List<Map<String, dynamic>> list = [];
      if (raw != null) {
        final decoded = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
        list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      list.add(cycle.toMap());
      await box.put('sessions_$dateStr', list);
      await box.put('todayStudyMin_$dateStr',
          list.fold<int>(0, (s, m) => s + ((m['effectiveMin'] as int?) ?? 0)));
      debugPrint('[Focus] saved to Hive: ${cycle.id} (${cycle.effectiveMin}min)');
    } catch (e) {
      debugPrint('[Focus] saveSessionToHive error: $e');
    }
  }

  Future<void> refreshTodaySessions() async {
    await _loadTodaySessions();
    notifyListeners();
  }

  Future<List<FocusCycle>> getSessionsForDate(String dateStr) async {
    try {
      final box = await _openBox();
      final raw = box.get('sessions_$dateStr');
      if (raw != null) {
        final list = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
        final sessions = list.map((e) => FocusCycle.fromMap(Map<String, dynamic>.from(e as Map))).toList();
        if (sessions.isNotEmpty) return sessions;
      }
    } catch (_) {}
    try {
      final cycles = await FirebaseService().getFocusCycles(dateStr).timeout(const Duration(seconds: 3));
      if (cycles.isNotEmpty) {
        try {
          final box = await _openBox();
          await box.put('sessions_$dateStr', cycles.map((c) => c.toMap()).toList());
        } catch (_) {}
      }
      return cycles;
    } catch (_) {}
    return [];
  }

  Future<Map<String, int>> getWeeklyStudyMinutes() async {
    final result = <String, int>{};
    final now = DateTime.now();
    for (int i = 6; i >= 0; i--) {
      final dt = now.subtract(Duration(days: i));
      final dateStr = DateFormat('yyyy-MM-dd').format(dt);
      final sessions = await getSessionsForDate(dateStr);
      result[dateStr] = sessions.fold(0, (s, c) => s + c.effectiveMin);
    }
    return result;
  }

  // ══════════════════════════════════════════
  //  세션 시작 / 종료 / 일시정지 / 재개
  // ══════════════════════════════════════════

  Future<void> startSession({required String subject, String mode = 'study'}) async {
    _currentSubject = subject;
    _currentMode = mode;
    _sessionStart = DateTime.now();
    _segmentStart = DateTime.now();
    _totalStudyMin = 0;
    _totalLectureMin = 0;
    _totalRestMin = 0;
    _accumulatedActiveSec = 0;
    _segments.clear();
    _isRunning = true;
    _isPaused = false;
    _pauseStart = null;
    _totalPauseSec = 0;
    _preModeBeforePause = null;

    await _recordStudyStartIfFirst();
    await FlutterForegroundTask.startService(
      notificationTitle: _notifTitle(),
      notificationText: '시작됨',
      callback: _focusCallback,
    );
    _startLiveSync();
    _startUiTimer();
    await _saveState();
    notifyListeners();
  }

  Future<FocusCycle> endSession() async {
    _endSegment();
    _isRunning = false;
    _isPaused = false;
    _uiTimer?.cancel();
    _uiTimer = null;
    _stopLiveSync();
    await FlutterForegroundTask.stopService();

    final effectiveMin = _totalStudyMin + (_totalLectureMin * 0.5).round();
    final cycle = FocusCycle(
      id: 'fc_${_sessionStart!.millisecondsSinceEpoch}',
      date: StudyDateUtils.todayKey(_sessionStart!),
      startTime: _sessionStart!.toIso8601String(),
      endTime: DateTime.now().toIso8601String(),
      subject: _currentSubject,
      segments: List.from(_segments),
      studyMin: _totalStudyMin,
      lectureMin: _totalLectureMin,
      effectiveMin: effectiveMin,
      restMin: _totalRestMin,
    );

    _todaySessions.add(cycle);
    _todayStudyMinutes += effectiveMin;
    await _saveSessionToHive(cycle);
    await _clearState();
    notifyListeners();

    _syncToFirebase(cycle);
    try { await FirebaseService().clearLiveFocus(cycle.date); } catch (_) {}

    return cycle;
  }

  /// 일시정지
  Future<void> pause() async {
    if (!_isRunning || _isPaused) return;
    _preModeBeforePause = _currentMode;
    _pauseStart = DateTime.now();
    // 현재 세그먼트의 활성 시간 누적
    if (_currentMode == 'study' || _currentMode == 'lecture') {
      final segSec = _segmentStart != null ? DateTime.now().difference(_segmentStart!).inSeconds : 0;
      _accumulatedActiveSec += segSec;
    }
    _endSegment();
    _isPaused = true;
    _currentMode = 'rest';
    _segmentStart = DateTime.now();
    await FlutterForegroundTask.updateService(
      notificationTitle: '⏸️ 일시정지',
      notificationText: _notifText(),
    );
    await _saveState();
    notifyListeners();
  }

  /// 재개
  Future<void> resume() async {
    if (!_isRunning || !_isPaused) return;
    _endSegment();
    if (_pauseStart != null) {
      _totalPauseSec += DateTime.now().difference(_pauseStart!).inSeconds;
      _pauseStart = null;
    }
    _isPaused = false;
    _currentMode = _preModeBeforePause ?? 'study';
    _preModeBeforePause = null;
    _segmentStart = DateTime.now();
    await FlutterForegroundTask.updateService(
      notificationTitle: _notifTitle(),
      notificationText: _notifText(),
    );
    await _saveState();
    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  모드 전환 / 과목 변경
  // ══════════════════════════════════════════

  Future<void> switchMode(String newMode) async {
    if (_currentMode == newMode) return;
    if (_currentMode == 'study' || _currentMode == 'lecture') {
      final segSec = _segmentStart != null ? DateTime.now().difference(_segmentStart!).inSeconds : 0;
      _accumulatedActiveSec += segSec;
    }
    _endSegment();
    _currentMode = newMode;
    _segmentStart = DateTime.now();
    if (_isPaused && newMode != 'rest') _isPaused = false;
    await FlutterForegroundTask.updateService(
      notificationTitle: _notifTitle(),
      notificationText: _notifText(),
    );
    await _saveState();
    notifyListeners();
  }

  Future<void> changeSubject(String subject) async {
    if (_currentMode == 'study' || _currentMode == 'lecture') {
      final segSec = _segmentStart != null ? DateTime.now().difference(_segmentStart!).inSeconds : 0;
      _accumulatedActiveSec += segSec;
    }
    _endSegment();
    _currentSubject = subject;
    _segmentStart = DateTime.now();
    await FlutterForegroundTask.updateService(
      notificationTitle: _notifTitle(),
      notificationText: _notifText(),
    );
    await _saveState();
    notifyListeners();
  }

  // ══════════════════════════════════════════
  //  현재 상태 스냅샷
  // ══════════════════════════════════════════

  FocusTimerState getCurrentState() {
    if (!_isRunning || _segmentStart == null) return FocusTimerState.idle();
    final now = DateTime.now();
    final segSec = now.difference(_segmentStart!).inSeconds;
    final effMin = _totalStudyMin + (_totalLectureMin * 0.5).round();
    int curMin = segSec ~/ 60;
    int dispEff = effMin;
    if (_currentMode == 'study') {
      dispEff += curMin;
    } else if (_currentMode == 'lecture') {
      dispEff += (curMin * 0.5).round();
    }
    final totalActive = _totalStudyMin + _totalLectureMin + curMin;
    final sessionSec = _sessionStart != null ? now.difference(_sessionStart!).inSeconds : 0;
    int activeElapsedSec = _accumulatedActiveSec;
    if ((_currentMode == 'study' || _currentMode == 'lecture') && !_isPaused) {
      activeElapsedSec += segSec;
    }

    return FocusTimerState(
      isRunning: true,
      mode: _currentMode,
      subject: _currentSubject,
      segmentElapsedSeconds: segSec,
      sessionElapsedSeconds: sessionSec,
      activeElapsedSeconds: activeElapsedSec,
      totalStudyMin: _currentMode == 'study' ? _totalStudyMin + curMin : _totalStudyMin,
      totalLectureMin: _currentMode == 'lecture' ? _totalLectureMin + curMin : _totalLectureMin,
      totalRestMin: _currentMode == 'rest' ? _totalRestMin + curMin : _totalRestMin,
      effectiveMin: dispEff,
      cycleProgress: (totalActive % 90) / 90.0,
      cycleCount: totalActive ~/ 90,
      sessionStartTime: _sessionStart,
    );
  }

  // ══════════════════════════════════════════
  //  포커스 기록 삭제 + studyTimeRecord 보정
  // ══════════════════════════════════════════

  Future<void> deleteFocusCycle(String date, String cycleId) async {
    try {
      final fb = FirebaseService();
      final cycles = await fb.getFocusCycles(date);
      final target = cycles.firstWhere((c) => c.id == cycleId,
          orElse: () => FocusCycle(id: '', date: date, startTime: '', subject: ''));
      cycles.removeWhere((c) => c.id == cycleId);
      await fb.overwriteFocusCycles(date, cycles);

      if (target.id.isNotEmpty) {
        final existing = await fb.getStudyTimeRecords();
        final prev = existing[date];
        if (prev != null) {
          final record = StudyTimeRecord(
            date: date,
            totalMinutes: (prev.totalMinutes - target.studyMin - target.lectureMin).clamp(0, 999999),
            studyMinutes: (prev.studyMinutes - target.studyMin).clamp(0, 999999),
            lectureMinutes: (prev.lectureMinutes - target.lectureMin).clamp(0, 999999),
            effectiveMinutes: (prev.effectiveMinutes - target.effectiveMin).clamp(0, 999999),
          );
          await fb.updateStudyTimeRecord(date, record, effectiveDelta: -target.effectiveMin);
        }
      }

      try {
        final box = await _openBox();
        final raw = box.get('sessions_$date');
        if (raw != null) {
          final list = List<dynamic>.from(raw is String ? jsonDecode(raw) : raw);
          list.removeWhere((e) => (Map<String, dynamic>.from(e as Map))['id'] == cycleId);
          await box.put('sessions_$date', list);
        }
      } catch (_) {}

      if (date == StudyDateUtils.todayKey()) {
        _todaySessions.removeWhere((c) => c.id == cycleId);
        _todayStudyMinutes = _todaySessions.fold(0, (s, c) => s + c.effectiveMin);
        notifyListeners();
      }
    } catch (_) {}
  }

  // ══════════════════════════════════════════
  //  Firestore 동기화
  // ══════════════════════════════════════════

  Future<void> _syncToFirebase(FocusCycle cycle) async {
    final totalSec = (cycle.studyMin + cycle.lectureMin + cycle.restMin) * 60;
    if (totalSec < 10 && cycle.effectiveMin == 0) {
      debugPrint('[Focus] 10초 미만 세션 무시');
      return;
    }
    final addedMin = cycle.studyMin + cycle.lectureMin;
    final fb = FirebaseService();

    // 1. focusCycles
    try {
      await fb.saveFocusCycle(cycle.date, cycle);
      debugPrint('[Focus] saveFocusCycle OK');
    } catch (e) {
      debugPrint('[Focus] saveFocusCycle FAIL: $e');
    }

    // 2. studyTimeRecords — Hive 합계 기준
    try {
      int totalStudy = 0, totalLecture = 0, totalEffective = 0;
      for (final s in _todaySessions) {
        totalStudy += s.studyMin;
        totalLecture += s.lectureMin;
        totalEffective += s.effectiveMin;
      }
      final record = StudyTimeRecord(
        date: cycle.date,
        totalMinutes: totalStudy + totalLecture,
        studyMinutes: totalStudy,
        lectureMinutes: totalLecture,
        effectiveMinutes: totalEffective,
      );
      await fb.updateStudyTimeRecord(cycle.date, record, effectiveDelta: cycle.effectiveMin);
      debugPrint('[Focus] studyTimeRecord OK: effective=$totalEffective');
    } catch (e) {
      debugPrint('[Focus] studyTimeRecord FAIL: $e');
    }

    // 3. today doc subjects
    if (addedMin > 0) {
      try {
        final subjectMin = <String, int>{};
        for (final seg in cycle.segments) {
          if (seg.mode == 'study' || seg.mode == 'lecture') {
            subjectMin[seg.subject] = (subjectMin[seg.subject] ?? 0) + seg.durationMin;
          }
        }
        for (final entry in subjectMin.entries) {
          await fb.updateTodayField('studyTime.subjects.${entry.key}', FieldValue.increment(entry.value));
        }
      } catch (e) {
        debugPrint('[Focus] today subjects FAIL: $e');
      }
    }

    // 4. history
    try {
      fb.appendFocusSessionToHistory(cycle.date, {
        'subject': cycle.subject,
        'start': cycle.startTime,
        'end': cycle.endTime ?? DateTime.now().toIso8601String(),
        'minutes': addedMin,
        'effectiveMin': cycle.effectiveMin,
      });
    } catch (e) {
      debugPrint('[Focus] history FAIL: $e');
    }

    // 5. 위젯 + 보상
    WidgetRenderService().updateWidget().catchError((_) {});
    if (addedMin > 0) {
      try { await CreatureService().addStudyReward(addedMin); } catch (_) {}
    }

    debugPrint('[Focus] sync done: ${cycle.date} +${cycle.effectiveMin}min');

    // 6. HTTP 백업
    try { await _httpBackupSync(cycle); } catch (_) {}
  }

  static const _cfBase = 'https://us-central1-cheonhong-studio.cloudfunctions.net/checkDoorManual';

  Future<void> _httpBackupSync(FocusCycle cycle) async {
    final addedMin = cycle.studyMin + cycle.lectureMin;
    if (addedMin <= 0) return;
    int totalStudy = 0, totalLecture = 0, totalEffective = 0;
    for (final s in _todaySessions) {
      totalStudy += s.studyMin;
      totalLecture += s.lectureMin;
      totalEffective += s.effectiveMin;
    }
    final strJson = Uri.encodeComponent(jsonEncode({
      '_finalized': false,
      'totalMinutes': totalStudy + totalLecture,
      'studyMinutes': totalStudy,
      'lectureMinutes': totalLecture,
      'effectiveMinutes': totalEffective,
    }));
    await http.get(Uri.parse(
      '$_cfBase?q=write&doc=study&field=studyTimeRecords.${cycle.date}&value=$strJson',
    )).timeout(const Duration(seconds: 10));
    debugPrint('[Focus] http backup OK');
  }

  // ── 실시간 동기화 (30초마다) ──

  void _startLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 30), (_) => _syncLiveProgress());
  }

  void _stopLiveSync() {
    _liveSyncTimer?.cancel();
    _liveSyncTimer = null;
  }

  Future<void> _syncLiveProgress() async {
    if (!_isRunning) return;
    try {
      final st = getCurrentState();
      final dateStr = StudyDateUtils.todayKey(_sessionStart!);
      await FirebaseService().updateLiveFocus(dateStr, {
        'isRunning': true,
        'isPaused': _isPaused,
        'mode': st.mode,
        'subject': st.subject,
        'effectiveMin': st.effectiveMin,
        'studyMin': st.totalStudyMin,
        'lectureMin': st.totalLectureMin,
        'restMin': st.totalRestMin,
        'lastUpdate': DateTime.now().toIso8601String(),
        'lastDevice': 'android',
      });
    } catch (_) {}
  }

  // ── 내부 헬퍼 ──

  void _startUiTimer() {
    _uiTimer?.cancel();
    _uiTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning) return;
      notifyListeners();
    });
  }

  void _endSegment() {
    if (_segmentStart == null) return;
    final now = DateTime.now();
    final dur = now.difference(_segmentStart!).inMinutes;
    if (dur > 0) {
      _segments.add(FocusSegment(
        startTime: _segmentStart!.toIso8601String(),
        endTime: now.toIso8601String(),
        subject: _currentSubject,
        mode: _currentMode,
        durationMin: dur,
      ));
      switch (_currentMode) {
        case 'study': _totalStudyMin += dur; break;
        case 'lecture': _totalLectureMin += dur; break;
        case 'rest': _totalRestMin += dur; break;
      }
    }
  }

  String _notifTitle() {
    final e = _currentMode == 'study' ? '📖' : _currentMode == 'lecture' ? '🎧' : '☕';
    final t = _currentMode == 'study' ? '집중공부' : _currentMode == 'lecture' ? '강의듣기' : '휴식';
    return '$e $t · $_currentSubject';
  }

  String _notifText() {
    final eff = _totalStudyMin + (_totalLectureMin * 0.5).round();
    final sessionMin = _sessionStart != null ? DateTime.now().difference(_sessionStart!).inMinutes : 0;
    return '순공 ${eff ~/ 60}h${eff % 60}m · 세션 ${sessionMin}분';
  }

  Future<void> _recordStudyStartIfFirst() async {
    final dateStr = StudyDateUtils.todayKey();
    final timeStr = DateFormat('HH:mm').format(DateTime.now());
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final existing = records[dateStr];
      if (existing?.study != null) return;
      await fb.updateTimeRecord(dateStr, TimeRecord(date: dateStr, wake: existing?.wake, study: timeStr));
    } catch (_) {
      try {
        final box = await _openBox();
        await box.put('study_start_$dateStr', timeStr);
      } catch (_) {}
    }
  }

  // ── 상태 저장/복원 (Hive) ──

  Future<void> _saveState() async {
    try {
      final box = await _openBox();
      await box.put('focus_running', _isRunning);
      await box.put('focus_paused', _isPaused);
      await box.put('focus_mode', _currentMode);
      await box.put('focus_subject', _currentSubject);
      if (_sessionStart != null) await box.put('focus_session_start', _sessionStart!.toIso8601String());
      if (_segmentStart != null) await box.put('focus_segment_start', _segmentStart!.toIso8601String());
      await box.put('focus_study_min', _totalStudyMin);
      await box.put('focus_lecture_min', _totalLectureMin);
      await box.put('focus_rest_min', _totalRestMin);
      await box.put('focus_accumulated_active_sec', _accumulatedActiveSec);
      await box.put('focus_total_pause_sec', _totalPauseSec);
      if (_preModeBeforePause != null) await box.put('focus_pre_pause_mode', _preModeBeforePause!);
    } catch (e) {
      debugPrint('[Focus] saveState error: $e');
    }
  }

  Future<bool> restoreState() async {
    try {
      final box = await _openBox();
      _isRunning = box.get('focus_running', defaultValue: false) as bool;
      if (!_isRunning) return false;
      _isPaused = box.get('focus_paused', defaultValue: false) as bool;
      _currentMode = box.get('focus_mode', defaultValue: 'study') as String;
      _currentSubject = box.get('focus_subject', defaultValue: '자료해석') as String;
      final ss = box.get('focus_session_start') as String?;
      if (ss != null) _sessionStart = DateTime.parse(ss);
      final sg = box.get('focus_segment_start') as String?;
      if (sg != null) _segmentStart = DateTime.parse(sg);
      _totalStudyMin = box.get('focus_study_min', defaultValue: 0) as int;
      _totalLectureMin = box.get('focus_lecture_min', defaultValue: 0) as int;
      _totalRestMin = box.get('focus_rest_min', defaultValue: 0) as int;
      _accumulatedActiveSec = box.get('focus_accumulated_active_sec', defaultValue: 0) as int;
      _totalPauseSec = box.get('focus_total_pause_sec', defaultValue: 0) as int;
      _preModeBeforePause = box.get('focus_pre_pause_mode') as String?;
      _startLiveSync();
      _startUiTimer();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[Focus] restoreState error: $e');
      return false;
    }
  }

  Future<void> _clearState() async {
    try {
      final box = await _openBox();
      for (final k in [
        'focus_running', 'focus_paused', 'focus_mode', 'focus_subject',
        'focus_session_start', 'focus_segment_start',
        'focus_study_min', 'focus_lecture_min', 'focus_rest_min',
        'focus_accumulated_active_sec', 'focus_total_pause_sec', 'focus_pre_pause_mode',
      ]) {
        await box.delete(k);
      }
    } catch (e) {
      debugPrint('[Focus] clearState error: $e');
    }
  }

  // ── 하위 호환 no-op 메서드 ──
  Future<void> startBathroomBreak() async => pause();
  Future<void> endBathroomBreak() async => resume();
  void toggleSubTimer() {}
  void resetSubTimer() {}
  void onCradleChanged(bool onCradle) {}
}

// ── Foreground Task Callback ──

@pragma('vm:entry-point')
void _focusCallback() {
  FlutterForegroundTask.setTaskHandler(_FocusHandler());
}

class _FocusHandler extends TaskHandler {
  int _tick = 0;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async { _tick = 0; }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _tick++;
    if (_tick % 10 == 0) {
      Hive.openBox('focus_data').then((box) {
        final sm = box.get('focus_study_min', defaultValue: 0) as int;
        final lm = box.get('focus_lecture_min', defaultValue: 0) as int;
        final mode = box.get('focus_mode', defaultValue: 'study') as String;
        final subject = box.get('focus_subject', defaultValue: '') as String;
        final paused = box.get('focus_paused', defaultValue: false) as bool;
        final sgStr = box.get('focus_segment_start') as String?;
        final ssStr = box.get('focus_session_start') as String?;
        int cur = 0;
        if (sgStr != null) cur = DateTime.now().difference(DateTime.parse(sgStr)).inMinutes;
        int sessionMin = 0;
        if (ssStr != null) sessionMin = DateTime.now().difference(DateTime.parse(ssStr)).inMinutes;
        final ts = mode == 'study' ? sm + cur : sm;
        final tl = mode == 'lecture' ? lm + cur : lm;
        final eff = ts + (tl * 0.5).round();
        final modeEmoji = paused ? '⏸️' : (mode == 'study' ? '📖' : mode == 'lecture' ? '🎧' : '☕');
        final modeLabel = paused ? '일시정지' : (mode == 'study' ? '집중' : mode == 'lecture' ? '강의' : '휴식');
        FlutterForegroundTask.updateService(
          notificationTitle: '$modeEmoji $modeLabel · $subject',
          notificationText: '순공 ${eff ~/ 60}h${eff % 60}m · 세션 ${sessionMin}분',
        );
      }).catchError((_) {});
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

// ── FocusTimerState (읽기 전용 스냅샷) ──

class FocusTimerState {
  final bool isRunning;
  final String mode;
  final String subject;
  final int segmentElapsedSeconds;
  final int sessionElapsedSeconds;
  final int activeElapsedSeconds;
  final int totalStudyMin;
  final int totalLectureMin;
  final int totalRestMin;
  final int effectiveMin;
  final double cycleProgress;
  final int cycleCount;
  final DateTime? sessionStartTime;

  FocusTimerState({
    required this.isRunning, required this.mode, required this.subject,
    required this.segmentElapsedSeconds,
    this.sessionElapsedSeconds = 0, this.activeElapsedSeconds = 0,
    required this.totalStudyMin, required this.totalLectureMin, required this.totalRestMin,
    required this.effectiveMin, required this.cycleProgress, required this.cycleCount,
    this.sessionStartTime,
  });

  factory FocusTimerState.idle() => FocusTimerState(
    isRunning: false, mode: 'study', subject: '',
    segmentElapsedSeconds: 0, sessionElapsedSeconds: 0, activeElapsedSeconds: 0,
    totalStudyMin: 0, totalLectureMin: 0, totalRestMin: 0,
    effectiveMin: 0, cycleProgress: 0, cycleCount: 0);

  String get effectiveTimeFormatted => '${effectiveMin ~/ 60}h ${effectiveMin % 60}m';

  String get mainTimerFormatted {
    final sec = mode == 'rest' ? segmentElapsedSeconds : activeElapsedSeconds;
    return _formatSec(sec);
  }

  String get segmentTimeFormatted => _formatSec(segmentElapsedSeconds);
  String get sessionTimeFormatted => _formatSec(sessionElapsedSeconds);

  static String _formatSec(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}
