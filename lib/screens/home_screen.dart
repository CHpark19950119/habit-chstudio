import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/botanical_theme.dart';
import '../services/focus_service.dart';
import '../constants.dart';
import '../services/firebase_service.dart';
import '../services/day_service.dart';
import '../services/weather_service.dart';
import '../services/telegram_service.dart';
import '../models/models.dart';
import 'focus/focus_screen.dart';
// NFC screen removed — 자동화 기반으로 전환
import 'settings_screen.dart';
import 'calendar_screen.dart';
import 'statistics_screen.dart';
import 'progress_screen.dart';
import 'painters.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'status_editor_sheet.dart';
import 'insight_screen.dart';
import 'order/order_screen.dart';
import '../models/order_models.dart';
import '../models/plan_models.dart';
import '../services/todo_service.dart';
import '../services/local_cache_service.dart';
import '../services/creature_service.dart';
import '../services/cradle_service.dart';
import '../services/library_service.dart';
import '../services/wake_service.dart';
import '../services/bus_service.dart';
import '../utils/study_date_utils.dart';
import 'library_seat_map_screen.dart';

part 'home_focus_section.dart';
part 'home_daily_log.dart';
part 'home_routine_card.dart';
part 'home_order_section.dart';
part 'home_todo_section.dart';
part 'home_library_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _ft = FocusService();
  final _nfc = DayService();
  final _weather = WeatherService();
  Timer? _ui;
  Timer? _streamDebounce;     // ★ stream listener 디바운스
  bool _isLoading = false;    // ★ _load() 동시 실행 방지
  bool _playedEntryAnim = false;
  String? _wake, _studyStart, _studyEnd;
  String? _outing, _returnHome;
  String? _bedTime;
  String? _prevBedTime; // 어제 취침 (수면시간 계산용)
  String? _mealStart, _mealEnd;
  int? _outingMinutes;
  int _effMin = 0;
  WeatherData? _weatherData;
  bool _noOuting = false; // ★ v10: 외출 안하는 날 (수동)

  /// 수면시간 라벨 (어제 bedTime ~ 오늘 wake)
  String? get _sleepDurationLabel {
    if (_wake == null || _prevBedTime == null) return null;
    try {
      final wp = _wake!.split(':').map(int.parse).toList();
      final bp = _prevBedTime!.split(':').map(int.parse).toList();
      final wakeMin = wp[0] * 60 + wp[1];
      var bedMin = bp[0] * 60 + bp[1];
      // bedTime이 wake보다 크면 전날 (예: 23:30 → 07:00)
      var diff = wakeMin - bedMin;
      if (diff <= 0) diff += 24 * 60;
      final h = diff ~/ 60;
      final m = diff % 60;
      return m > 0 ? '${h}h${m}m' : '${h}h';
    } catch (_) { return null; }
  }

  /// ★ 집 홈데이 자동 감지: 기상 후 3시간+ 외출 없음 OR 수동 _noOuting
  bool get _isHomeDay {
    if (_noOuting) return true;
    if (_wake == null || _outing != null) return false;
    try {
      final now = DateTime.now();
      final p = _wake!.split(':');
      var wakeTime = DateTime(now.year, now.month, now.day,
          int.parse(p[0]), int.parse(p[1]));
      // 자정 넘김: wakeTime이 미래면 전날로 보정
      if (wakeTime.isAfter(now)) {
        wakeTime = wakeTime.subtract(const Duration(days: 1));
      }
      return now.difference(wakeTime).inMinutes >= 180;
    } catch (_) { return false; }
  }

  /// 홈데이 모드 수동 토글
  Future<void> _toggleHomeDay() async {
    final newVal = !_noOuting;
    _safeSetState(() => _noOuting = newVal);
    try {
      final fb = FirebaseService();
      final todayKey = StudyDateUtils.todayKey();
      final records = await fb.getTimeRecords().timeout(const Duration(seconds: 5));
      final tr = records[todayKey];
      if (tr != null) {
        await fb.updateTimeRecord(todayKey, tr.copyWith(noOuting: newVal));
      }
    } catch (_) {}
  }
  int _tab = 0;
  int _pendingTab = 0;
  double _tabFadeValue = 1.0;
  List<MealEntry> _todayMeals = []; // ★ v9: 다회 식사
  List<String> _dailyMemos = [];   // ★ 데일리 메모

  // ★ Creature
  int _creatureLevel = 1;
  int _creatureStage = 0;

  // ★ Focus setup (home tab)
  final _cradle = CradleService();
  String _focusSubj = '자료해석';
  String _focusMode = 'study';
  List<FocusCycle> _focusSessions = [];
  Map<String, int> _focusWeekly = {};
  bool _focusRecordsLoading = false;
  bool _focusScreenOpen = false;

  // ★ Library
  LibraryRoom? _libraryRoom;

  // ★ R2: COMPASS 대시보드 데이터
  OrderData? _orderData;
  // ★ 오늘의 Todo
  TodoDaily? _todayTodos;
  Map<String, double>? _weeklyHistoryCache;
  late String _todoSelectedDate;  // 날짜 네비게이션용

  // Todo 편집용 임시 상태
  String? _editSubject;
  String? _editPriority;
  int? _editMinutes;
  String? _editType;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _fbSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _todaySub;
  int _retryDelay = 5; // ★ 스트림 재연결 지수 백오프 (초)

  late AnimationController _staggerController;
  final List<Animation<double>> _fadeAnims = [];
  final List<Animation<Offset>> _slideAnims = [];
  static const _cardCount = 6;

  late AnimationController _tabFadeCtrl;  // ★ Tab transition (200ms)

  @override
  void initState() {
    super.initState();
    _todoSelectedDate = StudyDateUtils.todayKey();
    _staggerController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
    for (int i = 0; i < _cardCount; i++) {
      final start = i * 0.12;
      final end = (start + 0.35).clamp(0.0, 1.0);
      _fadeAnims.add(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOut)));
      _slideAnims.add(Tween<Offset>(
        begin: const Offset(0, 0.12), end: Offset.zero,
      ).animate(CurvedAnimation(
        parent: _staggerController,
        curve: Interval(start, end, curve: Curves.easeOutCubic))));
    }
    // ★ stagger 애니메이션: _load 완료와 무관하게 즉시 시작
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_playedEntryAnim) {
        _playedEntryAnim = true;
        _staggerController.forward();
      }
    });
    _runStartup();
    WeatherService().checkMorningWeatherAlert(); // ★ 아침 비/눈 Telegram 알림

    _tabFadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));

    _nfc.addListener(_onNfcChanged);
    _ui = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final isOut = _outing != null && _returnHome == null;
      if (_ft.isRunning || isOut) _safeSetState(() {});
    });
  }

  @override
  void dispose() {
    _ui?.cancel();
    _fbSub?.cancel();
    _todaySub?.cancel();
    _streamDebounce?.cancel();
    _nfc.removeListener(_onNfcChanged);
    _staggerController.dispose();
    _tabFadeCtrl.dispose();
    super.dispose();
  }

  void _onNfcChanged() {
    if (!mounted) return;
    // ★ DayService state → UI 즉시 반영 (CF 비동기 대기 불필요)
    if (_nfc.isOut && _nfc.outingTime != null) {
      _outing = _nfc.outingTime;
      _returnHome = null;
    } else if (_nfc.state == DayState.returned && _nfc.returnTime != null) {
      _returnHome = _nfc.returnTime;
    }
    _safeSetState(() {});
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && !_isLoading) _load();
    });
  }

  void _startFirebaseListener() {
    _fbSub?.cancel();
    // ★ 단일 study 문서 스트림 — 모든 데이터가 여기에 있음
    _fbSub = FirebaseService().watchStudyData().listen((snap) {
      if (!mounted) return;
      if (!snap.exists) return;
      _streamDebounce?.cancel();
      _streamDebounce = Timer(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        final data = snap.data();
        if (data == null) return;

        // ★ v10: 스트림에서 timeRecords 파싱 완전 제거
        // → timeRecords는 _doLoad() (today doc)에서만 읽음
        // → 스트림 study doc과 today doc 충돌로 인한 플리커링 근본 해결
        final isProtected = LocalCacheService().isWriteProtected();
        if (!isProtected) {
          FirebaseService().updateCacheFromStream(data);
        }
        final d = _studyDate();

        // ── studyTimeRecords (공부시간만 스트림 업데이트) ──
        int? effMin;
        try {
          final strRaw = data['studyTimeRecords'] as Map<String, dynamic>?;
          if (strRaw != null && strRaw[d] != null) {
            effMin = StudyTimeRecord.fromMap(d, strRaw[d] as Map<String, dynamic>).effectiveMinutes;
          }
        } catch (e) { debugPrint('[Home] stream studyTimeRecords: $e'); }

        // ── orderData ──
        OrderData? orderData;
        try {
          final od = data['orderData'];
          if (od is Map && od.isNotEmpty) {
            orderData = OrderData.fromMap(Map<String, dynamic>.from(od));
          }
        } catch (e) { debugPrint('[Home] stream orderData: $e'); }

        // ── todos ──
        TodoDaily? todayTodos;
        try {
          final todosRaw = data['todos'];
          if (todosRaw is Map) {
            final todosMap = Map<String, dynamic>.from(todosRaw);
            if (todosMap[d] != null) {
              todayTodos = TodoDaily.fromMap(
                  Map<String, dynamic>.from(todosMap[d] as Map));
            }
          }
        } catch (e) { debugPrint('[Home] stream todos: $e'); }

        _safeSetState(() {
          // ★ v10: timeRecords는 스트림에서 업데이트하지 않음 (플리커 방지)
          if (effMin != null) _effMin = effMin;
          if (orderData != null && !isProtected) _orderData = orderData;
          if (todayTodos != null && !isProtected) _todayTodos = todayTodos;
        });
      });
    }, onError: (e) {
      debugPrint('[Home] stream error: $e');
      _fbSub?.cancel();
      Future.delayed(Duration(seconds: _retryDelay), () {
        if (mounted) {
          _startFirebaseListener();
          _retryDelay = (_retryDelay * 2).clamp(5, 60);
        }
      });
    });
    _retryDelay = 5;

    // ★ today doc 실시간 리스너 — CF 외부 쓰기 즉시 반영
    _todaySub?.cancel();
    _todaySub = FirebaseService().watchTodayData().listen((snap) {
      if (!mounted || !snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      if (LocalCacheService().isWriteProtected()) return;
      final d = _studyDate();
      _parseTodayData(data, d);
      _preserveNfcMovementTimes();
      _safeSetState(() {});
    }, onError: (e) {
      debugPrint('[Home] today stream error: $e');
    });
  }

  Future<void> _load() async {
    // NFC 리스너는 initState에서 등록됨 (ChangeNotifier 방식)
    if (_isLoading) return;
    _isLoading = true;
    try {
      await _doLoad(); // ★ 전체 타임아웃 제거 — 각 문서별 개별 타임아웃으로 처리
    } catch (e) {
      debugPrint('[Home] _load error: $e');
    } finally {
      _isLoading = false; // ★ 어떤 상황에서도 반드시 해제
    }
  }

  /// Todo 전용 경량 리로드 (todos 문서만 읽기)
  Future<void> _loadTodosOnly() async {
    // ★ write 보호 중이면 리로드 스킵 (방금 입력한 데이터 보호)
    if (LocalCacheService().isWriteProtected()) {
      debugPrint('[Home] _loadTodosOnly skip: write-protected');
      return;
    }
    try {
      final data = await FirebaseService().getTodosData();
      if (data == null || !mounted) return;
      // ★ 리로드 도중 write가 발생했으면 결과 무시
      if (LocalCacheService().isWriteProtected()) return;
      final d = _studyDate();
      final todosRaw = data['todos'] is Map ? Map<String, dynamic>.from(data['todos'] as Map) : null;
      TodoDaily? todos;
      if (todosRaw != null && todosRaw[d] != null) {
        todos = TodoDaily.fromMap(Map<String, dynamic>.from(todosRaw[d] as Map));
      }
      final history = <String, double>{};
      if (todosRaw != null) {
        final cutoff = DateFormat('yyyy-MM-dd')
            .format(DateTime.now().subtract(const Duration(days: 7)));
        for (final entry in todosRaw.entries) {
          if (entry.key.compareTo(cutoff) >= 0) {
            try {
              final td = TodoDaily.fromMap(Map<String, dynamic>.from(entry.value as Map));
              history[entry.key] = td.completionRate;
            } catch (_) {}
          }
        }
      }
      _safeSetState(() {
        _todayTodos = todos;
        _weeklyHistoryCache = history;
      });
    } catch (e) { debugPrint('[Home] _loadTodosOnly: $e'); }
  }

  /// 특정 날짜 Todo 로드 (날짜 네비게이션용)
  Future<void> _loadTodosForDate(String date) async {
    try {
      final todos = await TodoService().getTodos(date);
      _safeSetState(() {
        _todoSelectedDate = date;
        _todayTodos = todos ?? TodoDaily(date: date);
      });
    } catch (e) { debugPrint('[Home] _loadTodosForDate: $e'); }
  }

  Future<void> _doLoad() async {
    final d = _studyDate();
    final yesterday = DateFormat('yyyy-MM-dd').format(
        DateFormat('yyyy-MM-dd').parse(d).subtract(const Duration(days: 1)));
    final fb = FirebaseService();
    final lc = LocalCacheService();
    debugPrint('[Home] _doLoad 시작 (date=$d)');

    // ═══ 1단계: 로컬 today 캐시에서 즉시 표시 (0ms) ═══
    final localToday = lc.getGeneric('today');
    if (localToday != null) {
      _parseTodayData(localToday, d);
      debugPrint('[Home] today 캐시 즉시 표시 OK');
    } else {
      // fallback: 기존 study 캐시
      final localData = lc.getStudyData();
      if (localData != null) {
        _parseStudyData(localData, d);
        debugPrint('[Home] study 캐시 fallback 표시');
      }
    }
    _preserveNfcMovementTimes();
    _safeSetState(() {});

    // ═══ 2단계: Firebase today 문서 갱신 (1~2KB만 읽기) ═══
    _tryRefresh('today', () async {
      final data = await fb.getTodayDoc();
      if (data != null) {
        _parseTodayData(data, d);
      } else {
        // today 문서가 아직 없으면 study 문서 fallback
        final studyData = await fb.getStudyData();
        if (studyData != null) {
          _parseStudyData(studyData, d);
        }
      }
      // ★ DayService movement times 보존 (Firestore에 없어도 iot 기반 즉시 반영)
      _preserveNfcMovementTimes();
      _safeSetState(() {});
    });

    // ═══ 2.5단계: 어제 bedTime (수면시간 계산용) ═══
    _tryRefresh('prevBed', () async {
      final prevBed = await fb.getPrevBedTime(yesterday);
      if (prevBed != null) _safeSetState(() => _prevBedTime = prevBed);
    });

    // ═══ 3단계: 외부 서비스 (각각 독립, 실패 무관) ═══
    _tryRefresh('weather', () async {
      final w = await _weather.getCurrentWeather();
      if (w != null) _safeSetState(() => _weatherData = w);
    });
    _tryRefresh('creature', () async {
      final c = await CreatureService().getCreature();
      _safeSetState(() {
        _creatureLevel = (c['level'] as num?)?.toInt() ?? 1;
        _creatureStage = (c['stage'] as num?)?.toInt() ?? 0;
      });
    });
  }

  /// study 데이터 파싱 → UI 상태에 반영 (로컬/Firebase 공용)
  void _parseStudyData(Map<String, dynamic> data, String d) {
    // timeRecords
    try {
      final trRaw = data['timeRecords'] as Map<String, dynamic>?;
      if (trRaw != null && trRaw[d] != null) {
        final rec = TimeRecord.fromMap(d, trRaw[d] as Map<String, dynamic>);
        _wake = rec.wake; _studyStart = rec.study; _studyEnd = rec.studyEnd;
        _outing = rec.outing; _returnHome = rec.returnHome; _bedTime = rec.bedTime;
        _mealStart = rec.mealStart; _mealEnd = rec.mealEnd;
        _todayMeals = rec.meals; _noOuting = rec.noOuting;
        _outingMinutes = rec.outingMinutes;
      }
    } catch (e) { debugPrint('[Home] timeRecords: $e'); }

    // studyTimeRecords
    try {
      final strRaw = data['studyTimeRecords'] as Map<String, dynamic>?;
      if (strRaw != null && strRaw[d] != null) {
        _effMin = StudyTimeRecord.fromMap(d, strRaw[d] as Map<String, dynamic>).effectiveMinutes;
      }
    } catch (e) { debugPrint('[Home] studyTimeRecords: $e'); }

    // orderData
    try {
      final od = data['orderData'];
      if (od is Map && od.isNotEmpty) {
        _orderData = OrderData.fromMap(Map<String, dynamic>.from(od));
      }
    } catch (e) { debugPrint('[Home] order: $e'); }

    // todos
    try {
      final todosRaw = data['todos'];
      if (todosRaw is Map) {
        final todosMap = Map<String, dynamic>.from(todosRaw);
        if (todosMap[d] != null) {
          _todayTodos = TodoDaily.fromMap(Map<String, dynamic>.from(todosMap[d] as Map));
        }
        final cutoff = DateFormat('yyyy-MM-dd')
            .format(DateTime.now().subtract(const Duration(days: 7)));
        final history = <String, double>{};
        for (final entry in todosMap.entries) {
          if (entry.key.compareTo(cutoff) >= 0) {
            try {
              final td = TodoDaily.fromMap(Map<String, dynamic>.from(entry.value as Map));
              history[entry.key] = td.completionRate;
            } catch (_) {}
          }
        }
        _weeklyHistoryCache = history;
      }
    } catch (e) { debugPrint('[Home] todos: $e'); }
  }

  /// today 문서 파싱 → UI 상태에 반영 (Phase C: 1~2KB 경량 문서)
  void _parseTodayData(Map<String, dynamic> data, String d) {
    // ★ FIX: 날짜 검증 — today doc의 date가 오늘과 다르면 stale 데이터
    final docDate = data['date'] as String?;
    if (docDate != null && docDate != d) {
      debugPrint('[Home] ⚠️ today doc 날짜 불일치: doc=$docDate, today=$d — stale 데이터 무시');
      return;
    }

    // timeRecords (today 문서에서는 date 키 없이 바로 들어있음)
    try {
      final tr = data['timeRecords'];
      if (tr is Map && tr.isNotEmpty) {
        // today 문서는 flat 구조: timeRecords.wake, timeRecords.outing 등
        // 또는 기존 구조: timeRecords.{date}.{fields}
        if (tr.containsKey('wake') || tr.containsKey('study') || tr.containsKey('outing') || tr.containsKey('studyStart')) {
          // flat 구조 (Phase C)
          _wake = tr['wake'] as String?;
          _studyStart = tr['study'] as String? ?? tr['studyStart'] as String?;
          _studyEnd = tr['studyEnd'] as String?;
          _outing = tr['outing'] as String?;
          _returnHome = tr['returnHome'] as String?;
          _bedTime = tr['bedTime'] as String?;
          _mealStart = tr['mealStart'] as String?;
          _mealEnd = tr['mealEnd'] as String?;
          _noOuting = tr['noOuting'] == true;
          _outingMinutes = (tr['outingMinutes'] as num?)?.toInt();
          if (tr['meals'] is List) {
            _todayMeals = (tr['meals'] as List)
                .map((m) => MealEntry.fromMap(Map<String, dynamic>.from(m as Map)))
                .toList();
          }
        } else if (tr.containsKey(d)) {
          // 기존 구조 (study doc 호환)
          final rec = TimeRecord.fromMap(d, Map<String, dynamic>.from(tr[d] as Map));
          _wake = rec.wake; _studyStart = rec.study; _studyEnd = rec.studyEnd;
          _outing = rec.outing; _returnHome = rec.returnHome; _bedTime = rec.bedTime;
          _mealStart = rec.mealStart; _mealEnd = rec.mealEnd;
          _todayMeals = rec.meals; _noOuting = rec.noOuting;
          _outingMinutes = rec.outingMinutes;
        }
      }
    } catch (e) { debugPrint('[Home] today timeRecords: $e'); }

    // studyTime
    try {
      final st = data['studyTime'];
      if (st is Map) {
        _effMin = (st['total'] as num?)?.toInt() ?? 0;
      }
    } catch (e) { debugPrint('[Home] today studyTime: $e'); }

    // fallback: studyTimeRecords (마이그레이션 직후 호환)
    if (_effMin == 0) {
      try {
        final strRaw = data['studyTimeRecords'];
        if (strRaw is Map && strRaw[d] != null) {
          _effMin = StudyTimeRecord.fromMap(d, Map<String, dynamic>.from(strRaw[d] as Map)).effectiveMinutes;
        }
      } catch (_) {}
    }

    // orderData
    try {
      final od = data['orderData'];
      if (od is Map && od.isNotEmpty) {
        _orderData = OrderData.fromMap(Map<String, dynamic>.from(od));
      }
    } catch (e) { debugPrint('[Home] today order: $e'); }

    // todos (Phase C: List format)
    try {
      final todosRaw = data['todos'];
      if (todosRaw is List) {
        // Phase C: flat list of todo items
        final items = todosRaw.map((t) {
          if (t is Map) {
            return TodoItem(
              id: t['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
              title: t['title']?.toString() ?? '',
              completed: t['done'] == true || t['completed'] == true,
              completedAt: t['completedAt'] as String?,
            );
          }
          return null;
        }).whereType<TodoItem>().toList();
        _todayTodos = TodoDaily(date: d, items: items);
      } else if (todosRaw is Map) {
        // study doc fallback
        final todosMap = Map<String, dynamic>.from(todosRaw);
        if (todosMap[d] != null) {
          _todayTodos = TodoDaily.fromMap(Map<String, dynamic>.from(todosMap[d] as Map));
        }
      }
    } catch (e) { debugPrint('[Home] today todos: $e'); }
  }

  /// 독립 실행 헬퍼 — 실패해도 앱에 영향 없음
  void _tryRefresh(String name, Future<void> Function() fn) {
    Future(() async {
      try {
        await fn().timeout(const Duration(seconds: 15));
      } catch (e) {
        debugPrint('[Home] refresh $name: FAIL — $e');
      }
    });
  }

  /// DayService movement 시간이 Firestore보다 최신이면 보존
  void _preserveNfcMovementTimes() {
    if (_outing == null && _nfc.outingTime != null &&
        (_nfc.isOut || _nfc.state == DayState.returned)) {
      _outing = _nfc.outingTime;
    }
    if (_returnHome == null && _nfc.returnTime != null &&
        _nfc.state == DayState.returned) {
      _returnHome = _nfc.returnTime;
    }
  }

  /// 학습일 계산: 새벽 0~4시는 전날로 취급
  String _studyDate() => StudyDateUtils.todayKey();

  void _switchTab(int newTab) {
    if (newTab == _tab) return;
    HapticFeedback.selectionClick();
    _pendingTab = newTab;
    _tabFadeCtrl.forward(from: 0.0).then((_) {
      if (!mounted) return;
      _safeSetState(() {
        _tab = _pendingTab;
        _tabFadeValue = 0.0;
      });
      _tabFadeCtrl.reverse().then((_) {
        if (!mounted) return;
        _safeSetState(() => _tabFadeValue = 1.0);
      });
    });
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  /// ★ 스트림 + _load(즉시) + 백그라운드 아카이브
  Future<void> _runStartup() async {
    final fb = FirebaseService();
    // 스트림과 로드를 즉시 시작
    _startFirebaseListener();
    _load();
    _loadFocusRecords();
    _loadLibrary();
    // ★ 자동 아카이브 (7일 이전 데이터 → 월별 아카이브, UI 블로킹 없음)
    fb.autoArchive().catchError((e) {
      debugPrint('[Home] autoArchive error: $e');
    });
  }

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _border => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.gold;

  Widget _staggered(int index, Widget child) {
    final i = index.clamp(0, _cardCount - 1);
    return FadeTransition(
      opacity: _fadeAnims[i],
      child: SlideTransition(position: _slideAnims[i], child: child));
  }

  // ══════════════════════════════════════════
  //  빌드: BottomNav (대시보드 / 도구)
  // ══════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        _paperBackground(),
        AnimatedBuilder(
          animation: _tabFadeCtrl,
          builder: (_, child) {
            final v = 1.0 - _tabFadeCtrl.value;
            return Opacity(
              opacity: v.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, (1 - v) * 8),
                child: child,
              ),
            );
          },
          child: IndexedStack(
            index: _tab,
            children: [
              SafeArea(child: _dashboardPage()),
              SafeArea(child: _todoPage()),
              SafeArea(child: _focusPage()),
              SafeArea(child: _recordsPage()),
              const SafeArea(child: ProgressScreen()),
              SafeArea(child: CalendarScreen(embedded: true)),
            ],
          ),
        ),
      ]),
      bottomNavigationBar: _bottomNav(),
      floatingActionButton: _tab == 0 ? _orderFab() : null,
    );
  }

  Widget _paperBackground() {
    // 홈데이모드: 인디고 계열, 일반: 보타니컬 계열
    final colors = _isHomeDay
      ? (_dk
        ? [const Color(0xFF151B2E), const Color(0xFF141928),
           const Color(0xFF161C2D), const Color(0xFF121725)]
        : [const Color(0xFFF2F4FA), const Color(0xFFEDF1F8),
           const Color(0xFFE8ECF5), const Color(0xFFE4E9F2)])
      : (_dk
        ? [const Color(0xFF1C1410), const Color(0xFF1A1210),
           const Color(0xFF1D1512), const Color(0xFF181010)]
        : [const Color(0xFFFDF9F2), const Color(0xFFFAF5EC),
           const Color(0xFFF6F0E5), const Color(0xFFF2ECDF)]);
    return Positioned.fill(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            stops: const [0.0, 0.3, 0.7, 1.0],
            colors: colors,
          ),
        ),
        child: CustomPaint(painter: PaperGrainPainter(_dk)),
      ),
    );
  }

  Widget _bottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _dk ? BotanicalColors.cardDark : Colors.white,
        border: Border(top: BorderSide(color: _border.withOpacity(0.3), width: 0.5)),
        boxShadow: [BoxShadow(
          color: Colors.black.withOpacity(_dk ? 0.3 : 0.04),
          blurRadius: 20, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _navItem(0, Icons.dashboard_rounded, '홈'),
            _navItem(1, Icons.checklist_rounded, 'Todo'),
            _navItem(2, Icons.local_fire_department_rounded, '포커스'),
            _navItem(3, Icons.bar_chart_rounded, '기록'),
            _navItem(4, Icons.trending_up_rounded, '진행도'),
            _navItem(5, Icons.calendar_month_rounded, '캘린더'),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final sel = _tab == index;
    final selColor = _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;
    final c = sel ? selColor : _textMuted;
    final showLive = index == 2 && _ft.isRunning && !sel;
    return GestureDetector(
      onTap: () => _switchTab(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            Icon(icon, size: 22, color: c),
            if (showLive) Positioned(right: -3, top: -2,
              child: Container(width: 7, height: 7,
                decoration: BoxDecoration(
                  color: BotanicalColors.primary, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: BotanicalColors.primary.withOpacity(0.5),
                    blurRadius: 4, spreadRadius: 1)]))),
          ]),
          const SizedBox(height: 3),
          Text(label, style: BotanicalTypo.label(
            size: 10, weight: sel ? FontWeight.w800 : FontWeight.w600, color: c)),
          const SizedBox(height: 3),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: sel ? 16 : 0,
            height: 2.5,
            decoration: BoxDecoration(
              color: sel ? selColor : Colors.transparent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 0: 대시보드
  // ══════════════════════════════════════════

  Widget _dashboardPage() {
    return RefreshIndicator(
      color: BotanicalColors.primary,
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ═══ HEADER ═══
          _staggered(0, _weatherHeaderBar()),
          const SizedBox(height: 14),

          // ═══ STATUS — 지금 상태 ═══
          _staggered(1, _nfcStatusCard()),
          const SizedBox(height: 10),
          _staggered(1, _studyTimeCard()),
          const SizedBox(height: 10),
          _staggered(1, _presenceCard()),
          const SizedBox(height: 10),
          _staggered(2, _libraryCard()),
          if (_ft.isRunning) ...[
            const SizedBox(height: 10),
            _staggered(2, _activeFocusBanner()),
          ],
          // (홈데이 배너는 헤더에 통합됨)
          const SizedBox(height: 16),

          // ═══ TODAY — 오늘 할 것 ═══
          _staggered(3, _dashSectionHeader('TODAY')),
          const SizedBox(height: 8),
          _staggered(3, _orderPortalChip()),
          const SizedBox(height: 14),

          // ═══ LOG — 기록 ═══
          if (_dailyMemos.isNotEmpty || true) ...[
            _staggered(4, _dashboardMemoWidget()),
            const SizedBox(height: 10),
          ],
          _staggered(4, _locationSummaryCard()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _dashSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(title, style: BotanicalTypo.label(
        size: 11, weight: FontWeight.w800, letterSpacing: 2,
        color: _textMuted)),
    );
  }

  // ══════════════════════════════════════════
  //  TAB 2: 도구 (자동화 + 시스템)
  // ══════════════════════════════════════════

  Widget _toolsPage() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Text('도구', style: BotanicalTypo.heading(
          size: 26, weight: FontWeight.w800, color: _textMain)),
        const SizedBox(height: 4),
        Text('자동화와 시스템 관리', style: BotanicalTypo.label(
          size: 13, color: _textMuted)),
        const SizedBox(height: 24),

        _sectionHeader('⚙️', '시스템'),
        const SizedBox(height: 10),
        // ★ #5: 데일리 인사이트
        _toolCard(
          icon: '💡', label: '데일리 인사이트',
          subtitle: '학습 회고 & 인사이트 기록',
          color: const Color(0xFFF59E0B),
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const InsightScreen())),
        ),
        const SizedBox(height: 20),

        _sectionHeader('🔧', '앱 설정'),
        const SizedBox(height: 10),
        _toolCard(
          icon: '⚙️', label: '설정',
          subtitle: '앱 설정 및 데이터 관리',
          color: _textSub,
          onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ══════════════════════════════════════════
  //  TAB 2: 기록
  // ══════════════════════════════════════════

  Widget _recordsPage() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        // ── 컴팩트 헤더 ──
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('기록', style: BotanicalTypo.heading(
              size: 26, weight: FontWeight.w800, color: _textMain)),
            const SizedBox(height: 2),
            Text('학습 통계와 생활 기록', style: BotanicalTypo.label(
              size: 12, color: _textMuted)),
          ]),
          const Spacer(),
          // 오늘 순공 미니뱃지
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _dk
                ? BotanicalColors.primary.withOpacity(0.12)
                : BotanicalColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.timer_outlined, size: 13,
                color: _dk ? BotanicalColors.lanternGold : BotanicalColors.primary),
              const SizedBox(width: 4),
              Text('${_effMin ~/ 60}h ${_effMin % 60}m',
                style: BotanicalTypo.label(size: 11, weight: FontWeight.w800,
                  color: _dk ? BotanicalColors.lanternGold : BotanicalColors.primary)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),

        // ── 통계 화면 (세그먼트 컨트롤 포함) ──
        const StatisticsScreen(embedded: true),

        const SizedBox(height: 40),
      ],
    );
  }

  Widget _sectionHeader(String emoji, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text(title, style: BotanicalTypo.label(
          size: 13, weight: FontWeight.w800, letterSpacing: 0.5, color: _textMain)),
      ]),
    );
  }

  Widget _toolCard({
    required String icon, required String label, required String subtitle,
    required Color color, required VoidCallback onTap,
    bool isLive = false, Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _dk ? color.withOpacity(0.06) : Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _dk
            ? color.withOpacity(0.12) : color.withOpacity(0.08)),
          boxShadow: _dk ? null : [
            BoxShadow(color: color.withOpacity(0.04),
              blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(_dk ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(12)),
            child: Center(
              child: Stack(clipBehavior: Clip.none, children: [
                Text(icon, style: const TextStyle(fontSize: 20)),
                if (isLive)
                  Positioned(right: -3, top: -3,
                    child: Container(width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: BotanicalColors.success, shape: BoxShape.circle,
                        boxShadow: [BoxShadow(
                          color: BotanicalColors.success.withOpacity(0.5),
                          blurRadius: 6, spreadRadius: 1)]))),
              ]),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: BotanicalTypo.body(
              size: 14, weight: FontWeight.w700, color: _textMain)),
            const SizedBox(height: 2),
            Text(subtitle, style: BotanicalTypo.label(
              size: 11, color: _textMuted),
              overflow: TextOverflow.ellipsis, maxLines: 1),
          ])),
          if (trailing != null) ...[const SizedBox(width: 8), trailing],
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded, size: 18, color: _textMuted.withOpacity(0.5)),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  ① 헤더 + 날씨 통합 상단바
  // ══════════════════════════════════════════

  Widget _weatherHeaderBar() {
    if (_isHomeDay) return _homeDayHeader();

    final now = DateTime.now();
    final wd = ['월','화','수','목','금','토','일'][now.weekday - 1];
    final w = _weatherData;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('CHEONHONG', style: BotanicalTypo.brand(
            color: _dk ? BotanicalColors.lanternGold : BotanicalColors.primary)),
          const SizedBox(height: 4),
          Row(children: [
            Text('${now.month}월 ${now.day}일 ($wd)',
              style: BotanicalTypo.heading(size: 22, weight: FontWeight.w800, color: _textMain)),
            if (w != null) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () async {
                  await WeatherService().sendWeatherReport();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('📩 날씨 정보를 Telegram으로 전송했습니다'),
                      duration: Duration(seconds: 2)));
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(8)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(w.emoji, style: const TextStyle(fontSize: 12)),
                    const SizedBox(width: 3),
                    Text('${w.temp.round()}°', style: BotanicalTypo.number(
                      size: 12, weight: FontWeight.w700, color: _textSub)),
                    if (_weather.needsUmbrella(w)) ...[
                      const SizedBox(width: 2),
                      const Text('☂️', style: TextStyle(fontSize: 10)),
                    ],
                  ]),
                ),
              ),
            ],
          ]),
        ])),
        Row(children: [
          _headerIconBtn(Icons.directions_bus_rounded, () async {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('버스 도착정보 조회 중...'), duration: Duration(seconds: 1)));
            await BusService().fetchNow();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('텔레그램으로 전송 완료'), duration: Duration(seconds: 2)));
            }
          }),
          const SizedBox(width: 6),
          _headerIconBtn(Icons.edit_note_rounded, _showAddMemoDialog, size: 20),
          const SizedBox(width: 6),
          _headerIconBtn(Icons.settings_outlined, () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())), size: 18),
        ]),
      ],
    );
  }

  Widget _homeDayHeader() {
    final now = DateTime.now();
    final wd = ['월','화','수','목','금','토','일'][now.weekday - 1];
    final w = _weatherData;
    final hcLight = _dk ? const Color(0xFFA8BFEF) : const Color(0xFF3D5A99);

    // 홈데이 경과시간
    int homeMin = 0;
    if (_wake != null) {
      try {
        final p = _wake!.split(':');
        var wt = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
        if (wt.isAfter(now)) wt = wt.subtract(const Duration(days: 1));
        homeMin = now.difference(wt).inMinutes.clamp(0, 1440);
      } catch (_) {}
    }

    // 기존 헤더와 동일한 구조, 색상만 인디고
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Text('🏡', style: TextStyle(fontSize: 14)),
            const SizedBox(width: 5),
            Text('HOME DAY', style: BotanicalTypo.brand(color: hcLight)),
            if (homeMin > 0) ...[
              const SizedBox(width: 8),
              Text('${homeMin ~/ 60}h ${homeMin % 60}m', style: BotanicalTypo.number(
                size: 11, weight: FontWeight.w700, color: _textMuted)),
            ],
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Text('${now.month}월 ${now.day}일 ($wd)',
              style: BotanicalTypo.heading(size: 22, weight: FontWeight.w800, color: _textMain)),
            if (w != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(w.emoji, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 3),
                  Text('${w.temp.round()}°', style: BotanicalTypo.number(
                    size: 12, weight: FontWeight.w700, color: _textSub)),
                ]),
              ),
            ],
          ]),
        ])),
        Row(children: [
          // 홈데이 해제
          GestureDetector(
            onTap: _toggleHomeDay,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: hcLight.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.home_outlined, size: 16, color: hcLight))),
          const SizedBox(width: 6),
          _headerIconBtn(Icons.settings_outlined, () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())), size: 18),
        ]),
      ],
    );
  }

  Widget _headerIconBtn(IconData icon, VoidCallback onTap, {double size = 16}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: _dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: size, color: _textMuted)),
    );
  }

  // ══════════════════════════════════════════
  //  ★ #9: 데일리 메모 대시보드 위젯
  // ══════════════════════════════════════════

  Widget _dashboardMemoWidget() {
    return GestureDetector(
      onTap: _showAddMemoDialog,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _dk ? const Color(0xFF2A2218).withOpacity(0.6) : const Color(0xFFFFFBF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFB07D3A).withOpacity(_dk ? 0.15 : 0.1)),
          boxShadow: _dk ? null : [
            BoxShadow(color: const Color(0xFFB07D3A).withOpacity(0.04),
              blurRadius: 12, offset: const Offset(0, 3))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFB07D3A).withOpacity(_dk ? 0.15 : 0.08),
                borderRadius: BorderRadius.circular(8)),
              child: const Text('📝', style: TextStyle(fontSize: 12))),
            const SizedBox(width: 8),
            Text('오늘의 메모', style: BotanicalTypo.label(
              size: 12, weight: FontWeight.w700,
              color: _dk ? const Color(0xFFD4A66A) : const Color(0xFFB07D3A))),
            const Spacer(),
            if (_dailyMemos.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFB07D3A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
                child: Text('${_dailyMemos.length}', style: BotanicalTypo.label(
                  size: 10, weight: FontWeight.w800,
                  color: const Color(0xFFB07D3A)))),
            const SizedBox(width: 6),
            Icon(Icons.add_circle_outline_rounded, size: 16,
              color: _textMuted.withOpacity(0.5)),
          ]),
          if (_dailyMemos.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._dailyMemos.take(3).map((memo) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      color: _textMuted.withOpacity(0.3),
                      shape: BoxShape.circle))),
                const SizedBox(width: 8),
                Expanded(child: Text(memo, style: BotanicalTypo.label(
                  size: 11, color: _textSub),
                  maxLines: 1, overflow: TextOverflow.ellipsis)),
              ]),
            )),
            if (_dailyMemos.length > 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('+${_dailyMemos.length - 3}개 더보기',
                  style: BotanicalTypo.label(size: 10, weight: FontWeight.w600,
                    color: _textMuted.withOpacity(0.5)))),
          ] else ...[
            const SizedBox(height: 8),
            Text('탭하여 메모를 추가하세요', style: BotanicalTypo.label(
              size: 11, color: _textMuted.withOpacity(0.5))),
          ],
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════
  //  ★ Stage4: 날씨 + 성적 2컬럼 컴팩트 카드
  // ══════════════════════════════════════════

  Widget _weatherGradeRow() {
    final w = _weatherData;
    final h = _effMin ~/ 60;
    final m = _effMin % 60;
    final pc = _dk ? BotanicalColors.primaryLight : BotanicalColors.primary;

    return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // ── 날씨 디테일 카드 (LEFT) — 체감온도 + 옷차림 팁 ──
      Expanded(child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _dk ? const Color(0xFF1A2535) : const Color(0xFFF0F4FA),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _dk
            ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('체감온도', style: BotanicalTypo.label(
            size: 10, weight: FontWeight.w600, letterSpacing: 1, color: _textMuted)),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
            Text(w != null ? '${w.feelsLike.round()}°' : '--°',
              style: BotanicalTypo.number(size: 28, weight: FontWeight.w700,
                color: _dk ? Colors.white : _textMain)),
            const SizedBox(width: 6),
            if (w != null)
              Text('습도 ${w.humidity}%', style: BotanicalTypo.label(
                size: 10, color: _textMuted)),
          ]),
          const SizedBox(height: 6),
          Text(w != null ? _weather.getClothingAdvice(w) : '날씨 로딩 중',
            style: BotanicalTypo.label(size: 10, color: _textSub),
            maxLines: 2),
        ]),
      )),
      const SizedBox(width: 10),
      // ── 순공시간 카드 (RIGHT) ──
      Expanded(child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: _dk
              ? [const Color(0xFF1E3A2F), const Color(0xFF1A2E26)]
              : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: pc.withOpacity(_dk ? 0.3 : 0.15)),
          boxShadow: [BoxShadow(
            color: pc.withOpacity(_dk ? 0.12 : 0.06),
            blurRadius: 16, offset: const Offset(0, 4))]),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Row(children: [
            Icon(Icons.timer_outlined, size: 14, color: pc),
            const SizedBox(width: 6),
            Text('순공시간', style: BotanicalTypo.label(
              size: 10, weight: FontWeight.w700, letterSpacing: 1, color: pc)),
          ]),
          const SizedBox(height: 6),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
            Text('${h}h ${m}m', style: BotanicalTypo.heading(size: 22, weight: FontWeight.w900, color: pc)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: (_effMin / 480).clamp(0.0, 1.0),
              backgroundColor: _dk ? Colors.white.withOpacity(0.08) : pc.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(pc),
              minHeight: 3)),
        ]),
      )),
    ]));
  }

  // ── (gradeCard 제거됨 — _studyTimeCard 사용) ──

  // ── 순공시간 카드 (full width) ──

  Widget _studyTimeCard() {
    final h = _effMin ~/ 60;
    final m = _effMin % 60;
    final pc = _dk ? BotanicalColors.primaryLight : BotanicalColors.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF1E3A2F), const Color(0xFF1A2E26)]
            : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: BotanicalColors.primary.withOpacity(_dk ? 0.3 : 0.15))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.timer_outlined, size: 14, color: pc),
          const SizedBox(width: 6),
          Text('순공시간', style: BotanicalTypo.label(
            size: 10, weight: FontWeight.w700, color: pc)),
        ]),
        const SizedBox(height: 8),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic, children: [
          Text('$h', style: BotanicalTypo.number(size: 28, weight: FontWeight.w300,
            color: _dk ? Colors.white : BotanicalColors.textMain)),
          Text('h ', style: BotanicalTypo.label(size: 12, weight: FontWeight.w300,
            color: _dk ? Colors.white54 : BotanicalColors.textSub)),
          Text('${m.toString().padLeft(2, '0')}', style: BotanicalTypo.number(
            size: 18, weight: FontWeight.w300,
            color: _dk ? Colors.white70 : BotanicalColors.textSub)),
          Text('m', style: BotanicalTypo.label(size: 10, weight: FontWeight.w300,
            color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (_effMin / 480).clamp(0.0, 1.0),
            backgroundColor: _dk ? Colors.white.withOpacity(0.08) : pc.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation(pc), minHeight: 3)),
        const SizedBox(height: 3),
        Text('${(_effMin / 480 * 100).toInt()}%', style: BotanicalTypo.label(
          size: 9, color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ★ 집 홈데이 배너
  // ══════════════════════════════════════════

  Widget _homeDayBanner() {
    // 기상 후 경과시간
    int homeMinutes = 0;
    if (_wake != null) {
      try {
        final now = DateTime.now();
        final p = _wake!.split(':');
        var wakeTime = DateTime(now.year, now.month, now.day,
            int.parse(p[0]), int.parse(p[1]));
        if (wakeTime.isAfter(now)) {
          wakeTime = wakeTime.subtract(const Duration(days: 1));
        }
        homeMinutes = now.difference(wakeTime).inMinutes.clamp(0, 1440);
      } catch (_) {}
    }
    final homeH = homeMinutes ~/ 60;
    final homeM = homeMinutes % 60;

    // 시간대별 메시지
    final hour = DateTime.now().hour;
    final String mood;
    final String sub;
    if (hour < 12) {
      mood = '조용한 오전';
      sub = '집에서 차분하게 시작하는 하루';
    } else if (hour < 17) {
      mood = '느긋한 오후';
      sub = '바깥 없이도 충분한 하루';
    } else {
      mood = '고요한 저녁';
      sub = '오늘 하루 집에서 보냈어요';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF1B2338), const Color(0xFF1A2030)]
            : [const Color(0xFFF0F0FA), const Color(0xFFEBF0F9)]),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF5B7ABF).withOpacity(_dk ? 0.25 : 0.15))),
      child: Row(children: [
        // 집 아이콘
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF5B7ABF).withOpacity(_dk ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(12)),
          child: const Center(child: Text('🏡', style: TextStyle(fontSize: 20)))),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(mood, style: BotanicalTypo.label(
            size: 13, weight: FontWeight.w800,
            color: _dk ? const Color(0xFFA8BFEF) : const Color(0xFF3D5A99))),
          const SizedBox(height: 2),
          Text(sub, style: BotanicalTypo.label(
            size: 10, color: _textMuted)),
        ])),
        // 홈데이 시간
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF5B7ABF).withOpacity(_dk ? 0.12 : 0.08),
            borderRadius: BorderRadius.circular(10)),
          child: Column(children: [
            Text('${homeH}h ${homeM}m', style: BotanicalTypo.number(
              size: 13, weight: FontWeight.w700,
              color: _dk ? const Color(0xFFA8BFEF) : const Color(0xFF3D5A99))),
            Text('홈데이', style: BotanicalTypo.label(
              size: 9, color: _textMuted)),
          ]),
        ),
        const SizedBox(width: 8),
        // 홈데이 해제 버튼
        GestureDetector(
          onTap: _toggleHomeDay,
          child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              color: _textMuted.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.close_rounded, size: 16, color: _textMuted),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ★ 집 홈데이 전용 대시보드
  // ══════════════════════════════════════════

  Widget _homeDayPage() {
    // 홈데이 경과 시간
    int homeMin = 0;
    if (_wake != null) {
      try {
        final now = DateTime.now();
        final p = _wake!.split(':');
        final wt = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
        homeMin = now.difference(wt).inMinutes.clamp(0, 1440);
      } catch (_) {}
    }
    final homeH = homeMin ~/ 60;
    final homeM = homeMin % 60;

    // 시간대별 인사
    final hour = DateTime.now().hour;
    final String greeting, greetSub;
    if (hour < 12) {
      greeting = '고요한 아침';
      greetSub = '집에서 차분하게 시작하는 하루';
    } else if (hour < 17) {
      greeting = '느긋한 오후';
      greetSub = '나만의 공간에서 집중하는 시간';
    } else if (hour < 21) {
      greeting = '편안한 저녁';
      greetSub = '오늘 하루도 집에서 잘 보냈어요';
    } else {
      greeting = '깊은 밤';
      greetSub = '하루를 마무리할 시간이에요';
    }

    // 색상 팔레트 (코지 인디고)
    const hc = Color(0xFF5B7ABF);
    final hcLight = _dk ? const Color(0xFFA8BFEF) : const Color(0xFF3D5A99);
    final heroBg = _dk
      ? const [Color(0xFF151B2E), Color(0xFF1A2038)]
      : const [Color(0xFFEDF1FA), Color(0xFFE4EAF6)];
    final cardBg = _dk ? Colors.white.withOpacity(0.04) : Colors.white;
    final cardBorder = hc.withOpacity(_dk ? 0.15 : 0.1);

    final now = DateTime.now();
    final wd = ['월','화','수','목','금','토','일'][now.weekday - 1];
    final w = _weatherData;

    return RefreshIndicator(
      color: hc,
      onRefresh: () => _load(),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // ═══ HEADER ═══
          _staggered(0, Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('🏡', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 6),
                Text('HOME DAY', style: BotanicalTypo.label(
                  size: 11, weight: FontWeight.w800, letterSpacing: 2,
                  color: hcLight)),
              ]),
              const SizedBox(height: 4),
              Text('${now.month}월 ${now.day}일 ($wd)',
                style: BotanicalTypo.heading(size: 22, weight: FontWeight.w800, color: _textMain)),
            ])),
            if (w != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: hc.withOpacity(_dk ? 0.1 : 0.06),
                  borderRadius: BorderRadius.circular(10)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(w.emoji, style: const TextStyle(fontSize: 14)),
                  const SizedBox(width: 4),
                  Text('${w.temp.round()}°', style: BotanicalTypo.number(
                    size: 13, weight: FontWeight.w700, color: hcLight)),
                ]),
              ),
            const SizedBox(width: 6),
            _headerIconBtn(Icons.settings_outlined, () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const SettingsScreen())), size: 18),
          ])),
          const SizedBox(height: 18),

          // ═══ 히어로 카드 ═══
          _staggered(1, Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: heroBg),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: hc.withOpacity(_dk ? 0.25 : 0.15))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // 인사
              Text(greeting, style: BotanicalTypo.heading(
                size: 24, weight: FontWeight.w800, color: hcLight)),
              const SizedBox(height: 4),
              Text(greetSub, style: BotanicalTypo.label(
                size: 12, color: _textMuted)),
              const SizedBox(height: 20),
              // 홈데이시간 + 순공시간
              Row(children: [
                _homeDayStatPill('🏡', '${homeH}h ${homeM}m', '홈데이', hc),
                const SizedBox(width: 10),
                _homeDayStatPill('📖', '${_effMin ~/ 60}h ${(_effMin % 60).toString().padLeft(2, '0')}m', '순공', BotanicalColors.primary),
                const SizedBox(width: 10),
                _homeDayStatPill('🍽️', '${_todayMeals.length}회', '식사', const Color(0xFFFF8A65)),
              ]),
            ]),
          )),
          const SizedBox(height: 14),

          // ═══ 퀵 액션 ═══
          _staggered(2, Row(children: [
            _homeDayAction('📖', '공부', _quickStudy,
              active: _studyStart != null && _studyEnd == null),
            const SizedBox(width: 8),
            _homeDayAction('🌙', '취침', _quickSleep,
              active: _bedTime != null),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(
              onTap: () {
                HapticFeedback.mediumImpact();
                Navigator.push(context, PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const OrderScreen(),
                  transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
                  transitionDuration: const Duration(milliseconds: 200),
                )).then((_) => _load());
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: cardBg, borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cardBorder)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('🧭', style: TextStyle(fontSize: 20)),
                  const SizedBox(height: 4),
                  Text('ORDER', style: BotanicalTypo.label(
                    size: 9, weight: FontWeight.w700, color: _textMuted)),
                ]),
              ),
            )),
          ])),
          const SizedBox(height: 14),

          // ═══ 포커스 배너 (진행 중일 때) ═══
          if (_ft.isRunning) ...[
            _staggered(2, _activeFocusBanner()),
            const SizedBox(height: 14),
          ],

          // ═══ COMPASS (컴팩트) ═══
          _staggered(3, _orderPortalChip()),
          const SizedBox(height: 14),

          // ═══ LOG ═══
          _staggered(4, _dashboardMemoWidget()),
          const SizedBox(height: 10),
          _staggered(4, _locationSummaryCard()),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _homeDayStatPill(String emoji, String value, String label, Color c) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: c.withOpacity(_dk ? 0.1 : 0.06),
        borderRadius: BorderRadius.circular(14)),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 4),
        Text(value, style: BotanicalTypo.number(
          size: 14, weight: FontWeight.w700,
          color: _dk ? Colors.white.withOpacity(0.85) : c)),
        Text(label, style: BotanicalTypo.label(
          size: 9, color: _textMuted)),
      ]),
    ));
  }

  Widget _homeDayAction(String emoji, String label, VoidCallback onTap,
      {bool active = false}) {
    final c = active
      ? (_dk ? const Color(0xFF5B7ABF) : const Color(0xFF3D5A99))
      : _textMuted;
    return Expanded(child: GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: active
            ? const Color(0xFF5B7ABF).withOpacity(_dk ? 0.15 : 0.08)
            : (_dk ? Colors.white.withOpacity(0.04) : Colors.white),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: active
              ? const Color(0xFF5B7ABF).withOpacity(0.3)
              : (_dk ? Colors.white.withOpacity(0.06) : const Color(0xFFE8E4DF)))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(label, style: BotanicalTypo.label(
            size: 9, weight: active ? FontWeight.w800 : FontWeight.w600, color: c)),
        ]),
      ),
    ));
  }

  // ══════════════════════════════════════════
  //  ② 히어로 카드 (레거시 — 직접 호출 안 함)
  // ══════════════════════════════════════════

  Widget _heroStatsRow() {
    final h = _effMin ~/ 60;
    final m = _effMin % 60;
    final pc = _dk ? BotanicalColors.primaryLight : BotanicalColors.primary;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF1E3A2F), const Color(0xFF1A2E26)]
            : [const Color(0xFFE8F5E9), const Color(0xFFF1F8E9)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: BotanicalColors.primary.withOpacity(_dk ? 0.3 : 0.15)),
        boxShadow: [BoxShadow(
          color: BotanicalColors.primary.withOpacity(_dk ? 0.15 : 0.08),
          blurRadius: 20, offset: const Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: BotanicalColors.primary.withOpacity(_dk ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.timer_outlined, size: 14, color: pc)),
          const SizedBox(width: 8),
          Text('순공시간', style: BotanicalTypo.label(
            size: 11, weight: FontWeight.w700, color: pc)),
        ]),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic, children: [
          Text('$h', style: BotanicalTypo.number(size: 38, weight: FontWeight.w300,
            color: _dk ? Colors.white : BotanicalColors.textMain)),
          Text('h ', style: BotanicalTypo.label(size: 15, weight: FontWeight.w300,
            color: _dk ? Colors.white54 : BotanicalColors.textSub)),
          Text('${m.toString().padLeft(2, '0')}', style: BotanicalTypo.number(
            size: 26, weight: FontWeight.w300,
            color: _dk ? Colors.white70 : BotanicalColors.textSub)),
          Text('m', style: BotanicalTypo.label(size: 13, weight: FontWeight.w300,
            color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: (_effMin / 480).clamp(0.0, 1.0),
            backgroundColor: _dk
              ? Colors.white.withOpacity(0.08)
              : BotanicalColors.primary.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation(pc),
            minHeight: 4)),
        const SizedBox(height: 3),
        Text('목표 8h · ${(_effMin / 480 * 100).toInt()}%',
          style: BotanicalTypo.label(size: 10,
            color: _dk ? Colors.white38 : BotanicalColors.textMuted)),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ③ 스코어 브레이크다운
  // ══════════════════════════════════════════

  Widget _scoreBreakdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      decoration: BotanicalDeco.card(_dk),
      child: Row(children: [
        _infoCell('기상', _fmt12h(_wake),
          BotanicalColors.gold, Icons.wb_sunny_outlined),
        _infoDivider(),
        _infoCell('공부시작', _fmt12h(_studyStart),
          BotanicalColors.subjectData, Icons.menu_book_outlined),
        _infoDivider(),
        _infoCell('순공', '${_effMin ~/ 60}h${_effMin % 60}m',
          BotanicalColors.primary, Icons.schedule_outlined),
      ]),
    );
  }

  Widget _infoCell(String label, String value,
      Color color, IconData icon) {
    return Expanded(child: Column(children: [
      Icon(icon, size: 16, color: color.withOpacity(0.7)),
      const SizedBox(height: 6),
      Text(value, style: BotanicalTypo.label(
        size: 13, weight: FontWeight.w700, color: _textMain)),
      const SizedBox(height: 2),
      Text(label, style: BotanicalTypo.label(size: 10, color: _textMuted)),
    ]));
  }

  Widget _infoDivider() => Container(
    width: 1, height: 45, color: _border.withOpacity(0.4));

  // ══════════════════════════════════════════
  //  포커스 활성 배너
  // ══════════════════════════════════════════

  Widget _activeFocusBanner() {
    final st = _ft.getCurrentState();
    final mc = BotanicalColors.subjectColor(st.subject);
    return GestureDetector(
      onTap: () => _switchTab(2), // 포커스 탭으로 이동
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [mc.withOpacity(_dk ? 0.15 : 0.06), mc.withOpacity(_dk ? 0.05 : 0.02)]),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: mc.withOpacity(0.2))),
        child: Row(children: [
          Container(width: 10, height: 10,
            decoration: BoxDecoration(color: mc, shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: mc.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)])),
          const SizedBox(width: 12),
          Text('${st.mode == 'study' ? '📖' : st.mode == 'lecture' ? '🎧' : '☕'} ${st.subject}',
            style: BotanicalTypo.label(size: 13, weight: FontWeight.w600, color: _textMain)),
          const Spacer(),
          Text(st.mainTimerFormatted, style: BotanicalTypo.number(
            size: 20, weight: FontWeight.w600, color: mc)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: mc.withOpacity(_dk ? 0.15 : 0.08),
              borderRadius: BorderRadius.circular(8)),
            child: Text('순공 ${st.effectiveTimeFormatted}',
              style: BotanicalTypo.label(size: 10, weight: FontWeight.w700, color: mc))),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_ios_rounded, size: 12, color: _textMuted),
        ]),
      ),
    );
  }

}