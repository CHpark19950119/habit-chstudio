import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import '../theme/botanical_theme.dart';
import '../constants.dart';
import '../services/firebase_service.dart';
import '../services/day_service.dart';
import '../services/weather_service.dart';
import '../models/models.dart';
import 'settings_screen.dart';
import 'calendar_screen.dart';
import 'statistics_screen.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'status_editor_sheet.dart';
import 'order/order_screen.dart';
import '../models/order_models.dart';
import '../models/todo_models.dart';
import '../services/todo_service.dart';
import '../services/local_cache_service.dart';
import '../utils/date_utils.dart';
import 'package:app_links/app_links.dart';
import '../data/sleep_protocol.dart';

part 'home_daily_log.dart';
part 'home_routine_card.dart';
part 'home_order_section.dart';
part 'home_todo_section.dart';
part 'home_sleep_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _day = DayService();
  final _weather = WeatherService();
  Timer? _ui;
  Timer? _streamDebounce;     // ★ stream listener 디바운스
  bool _isLoading = false;    // ★ _load() 동시 실행 방지
  bool _playedEntryAnim = false;
  String? _wake;
  String? _outing, _returnHome;
  String? _bedTime;
  String? _prevBedTime; // 어제 취침 (수면시간 계산용)
  String? _mealStart, _mealEnd;
  WeatherData? _weatherData;
  bool _noOuting = false; // ★ v10: 외출 안하는 날 (수동)
  Map<String, dynamic>? _specialDay; // ★ 특별한 날 (노는 날 등)

  // ★ 수면 교정 (WB 10주 위상전진 프로토콜)
  SleepProtocol? _sleepProto;
  Map<String, dynamic> _sleepLog = {}; // date -> {actualWake, actualSleep, tasks, ...}

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
    // TODO: getTimeRecords/updateTimeRecord removed — persist noOuting via new data layer
    try {
      final fb = FirebaseService();
      await fb.updateTodayField('noOuting', newVal);
    } catch (_) {}
  }
  int _tab = 0;
  int _pendingTab = 0;
  int _statsRefreshTrigger = 0;
  List<MealEntry> _todayMeals = []; // ★ v9: 다회 식사
  List<String> _dailyMemos = [];   // ★ 데일리 메모
  String? _mood;                   // ★ E: 오늘의 무드 이모지

  // ★ R2: COMPASS 대시보드 데이터
  OrderData? _orderData;
  // ★ 오늘의 Todo
  TodoDaily? _todayTodos;
  Map<String, double>? _weeklyHistoryCache;
  late String _todoSelectedDate;  // 날짜 네비게이션용

  // Todo 편집용 임시 상태
  String? _editPriority;
  int? _editMinutes;
  String? _editType;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _fbSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _todaySub;
  int _retryDelay = 5; // ★ 스트림 재연결 지수 백오프 (초)
  Completer<void>? _loadCompleter; // ★ _load() in-flight dedup

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

    _day.addListener(_onDayChanged);
    _initDeepLinks();
    _ui = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final isOut = _outing != null && _returnHome == null;
      if (isOut) _safeSetState(() {});
    });
  }

  // ═══ Deep Link 처리 ═══
  StreamSubscription<Uri>? _deepLinkSub;

  void _initDeepLinks() {
    final appLinks = AppLinks();
    // 앱이 이미 실행 중일 때 들어오는 딥링크
    _deepLinkSub = appLinks.uriLinkStream.listen((uri) {
      _handleDeepLink(uri);
    });
    // 앱이 딥링크로 처음 열렸을 때
    appLinks.getInitialLink().then((uri) {
      if (uri != null) _handleDeepLink(uri);
    });
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('[DeepLink] $uri');
    if (uri.host == 'app') {
      // 앱 제어 (탭 전환 등)
      final tab = uri.queryParameters['tab'];
      if (tab != null) {
        final tabIndex = int.tryParse(tab) ?? 0;
        _safeSetState(() {
          _tab = tabIndex;
          if (tabIndex == 2) _statsRefreshTrigger++;
        });
      }
    } else if (uri.host == 'wake') {
      _day.triggerAction(ActionType.wake).then((msg) {
        debugPrint('[DeepLink] wake → $msg');
        if (mounted && !_isLoading) _load();
      });
    } else if (uri.host == 'sleep') {
      _day.triggerAction(ActionType.sleep).then((msg) {
        debugPrint('[DeepLink] sleep → $msg');
        if (mounted && !_isLoading) _load();
      });
    } else if (uri.host == 'outing') {
      _day.triggerAction(ActionType.outing).then((msg) {
        debugPrint('[DeepLink] outing → $msg');
        if (mounted && !_isLoading) _load();
      });
    } else if (uri.host == 'meal') {
      _day.triggerAction(ActionType.meal).then((msg) {
        debugPrint('[DeepLink] meal → $msg');
        if (mounted && !_isLoading) _load();
      });
    } else if (uri.host == 'order') {
      if (mounted) {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => const OrderScreen(),
        ));
      }
    }
  }

  @override
  void dispose() {
    _deepLinkSub?.cancel();
    _ui?.cancel();
    _fbSub?.cancel();
    _todaySub?.cancel();
    _streamDebounce?.cancel();
    _day.removeListener(_onDayChanged);
    _staggerController.dispose();
    _tabFadeCtrl.dispose();
    super.dispose();
  }

  void _onDayChanged() {
    if (!mounted) return;
    // ★ DayService state → UI 즉시 반영 (CF 비동기 대기 불필요)
    if (_day.isOut && _day.outingTime != null) {
      _outing = _day.outingTime;
      _returnHome = null;
    } else if (_day.state == DayState.returned && _day.returnTime != null) {
      _returnHome = _day.returnTime;
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

        // ── prevBedTime (수면시간) — 스트림에서 최신값 갱신 ──
        String? prevBed;
        try {
          final yesterday = DateFormat('yyyy-MM-dd').format(
              DateFormat('yyyy-MM-dd').parse(d).subtract(const Duration(days: 1)));
          final tr = data['timeRecords'] as Map<String, dynamic>?;
          if (tr != null && tr[yesterday] is Map) {
            prevBed = (tr[yesterday] as Map)['bedTime'] as String?;
          }
        } catch (_) {}

        _retryDelay = 5; // ★ 스트림 데이터 수신 성공 → 백오프 리셋
        _safeSetState(() {
          if (orderData != null && !isProtected) _orderData = orderData;
          if (todayTodos != null && !isProtected) _todayTodos = todayTodos;
          if (prevBed != null) _prevBedTime = prevBed;
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
    // ★ _retryDelay 리셋은 onData 콜백 내부에서 수행 (위 _safeSetState 블록)
    // 스트림 등록 직후 리셋하면 지수 백오프가 깨짐

    // ★ today doc 실시간 리스너 — CF 외부 쓰기 즉시 반영
    _todaySub?.cancel();
    _todaySub = FirebaseService().watchTodayData().listen((snap) {
      if (!mounted || !snap.exists) return;
      final data = snap.data();
      if (data == null) return;
      if (LocalCacheService().isWriteProtected()) return;
      // ★ 로컬 캐시도 서버 값으로 갱신 (다음 앱 시작 시 stale 방지)
      LocalCacheService().saveGeneric('today', data);
      final d = _studyDate();
      _parseTodayData(data, d);
      _preserveMovementTimes();
      _safeSetState(() {});
    }, onError: (e) {
      debugPrint('[Home] today stream error: $e');
    });
  }

  Future<void> _load({bool forceServer = false}) async {
    // DayService 리스너는 initState에서 등록됨 (ChangeNotifier 방식)
    // ★ in-flight dedup: 이미 로딩 중이면 같은 Future 재사용
    if (_isLoading && _loadCompleter != null) {
      return _loadCompleter!.future;
    }
    _isLoading = true;
    _loadCompleter = Completer<void>();
    try {
      if (forceServer) FirebaseService().invalidateAllCaches();
      await _doLoad(); // ★ 전체 타임아웃 제거 — 각 문서별 개별 타임아웃으로 처리
      _loadCompleter!.complete();
    } catch (e) {
      debugPrint('[Home] _load error: $e');
      _loadCompleter!.completeError(e);
    } finally {
      _isLoading = false; // ★ 어떤 상황에서도 반드시 해제
      _loadCompleter = null;
    }
  }

  /// Todo 전용 경량 리로드 (todos 문서만 읽기)
  Future<void> _loadTodosOnly({bool forceServer = false}) async {
    // ★ write 보호 중이면 리로드 스킵 (방금 입력한 데이터 보호)
    if (LocalCacheService().isWriteProtected()) {
      debugPrint('[Home] _loadTodosOnly skip: write-protected');
      return;
    }
    try {
      if (forceServer) FirebaseService().invalidateStudyCache();
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
    _preserveMovementTimes();
    _safeSetState(() {});

    // ═══ 2단계: Firebase today 문서 갱신 (1~2KB만 읽기) ═══
    _tryRefresh('today', () async {
      final data = await fb.getTodayDoc();
      if (data != null) {
        _parseTodayData(data, d);
        // ★ 로컬 캐시도 서버 값으로 갱신 (외부 수정 반영)
        lc.saveGeneric('today', data);
      } else {
        // today 문서가 아직 없으면 study 문서 fallback
        final studyData = await fb.getStudyData();
        if (studyData != null) {
          _parseStudyData(studyData, d);
        }
      }
      // ★ DayService movement times 보존 (Firestore에 없어도 iot 기반 즉시 반영)
      _preserveMovementTimes();
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

    // ═══ 4단계: 수면 프로토콜 (없으면 default 생성 후 저장) ═══
    _tryRefresh('sleepProto', _loadSleepProtocol);
  }

  /// 수면 프로토콜 문서 로드. 없으면 default 생성 후 Firestore 기록.
  Future<void> _loadSleepProtocol() async {
    final docPath = 'users/$kUid/data/sleepProtocol';
    try {
      final snap = await FirebaseFirestore.instance
          .doc(docPath)
          .get()
          .timeout(const Duration(seconds: 8));
      if (snap.exists && snap.data() != null && snap.data()!.isNotEmpty) {
        _safeSetState(() {
          _sleepProto = SleepProtocol.fromMap(snap.data()!);
        });
        return;
      }
      // 문서가 없으면 default 로 생성하고 저장
      final proto = SleepProtocol.defaultForUser();
      _safeSetState(() => _sleepProto = proto);
      await FirebaseFirestore.instance
          .doc(docPath)
          .set(proto.toMap(), SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('[Home] loadSleepProtocol: $e');
      // 최소 기본값으로라도 카드가 보이게
      _safeSetState(() => _sleepProto ??= SleepProtocol.defaultForUser());
    }
  }

  /// study 데이터 파싱 → UI 상태에 반영 (로컬/Firebase 공용)
  /// ★ timeRecords는 today doc에서만 읽음 (study doc과 충돌 방지)
  void _parseStudyData(Map<String, dynamic> data, String d) {

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
        if (tr.containsKey('wake') || tr.containsKey('outing')) {
          // flat 구조 (Phase C)
          _wake = tr['wake'] as String?;
          _outing = tr['outing'] as String?;
          _returnHome = tr['returnHome'] as String?;
          _bedTime = tr['bedTime'] as String?;
          _mealStart = tr['mealStart'] as String?;
          _mealEnd = tr['mealEnd'] as String?;
          _noOuting = tr['noOuting'] == true;
          if (tr['meals'] is List) {
            _todayMeals = (tr['meals'] as List)
                .map((m) => MealEntry.fromMap(Map<String, dynamic>.from(m as Map)))
                .toList();
          }
        } else if (tr.containsKey(d)) {
          // 기존 구조 (study doc 호환)
          final rec = TimeRecord.fromMap(d, Map<String, dynamic>.from(tr[d] as Map));
          _wake = rec.wake;
          _outing = rec.outing; _returnHome = rec.returnHome; _bedTime = rec.bedTime;
          _mealStart = rec.mealStart; _mealEnd = rec.mealEnd;
          _todayMeals = rec.meals; _noOuting = rec.noOuting;
        }
      }
    } catch (e) { debugPrint('[Home] today timeRecords: $e'); }

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

    // ★ E: mood
    try {
      final m = data['mood'];
      if (m is String && m.isNotEmpty) _mood = m;
    } catch (_) {}

    // ★ E: dailyMemos
    try {
      final memos = data['dailyMemos'];
      if (memos is List) {
        _dailyMemos = memos.map((e) => e.toString()).toList();
      }
    } catch (_) {}

    // ★ specialDay (노는 날 등 특별한 날 표시)
    try {
      final sd = data['specialDay'];
      if (sd is Map && sd.isNotEmpty) {
        _specialDay = Map<String, dynamic>.from(sd);
      }
    } catch (_) {}

    // ★ sleepLog (수면 교정 카드)
    try {
      final sl = data['sleepLog'];
      if (sl is Map) {
        _sleepLog = Map<String, dynamic>.from(sl);
      }
    } catch (_) {}
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
  void _preserveMovementTimes() {
    if (_outing == null && _day.outingTime != null &&
        (_day.isOut || _day.state == DayState.returned)) {
      _outing = _day.outingTime;
    }
    if (_returnHome == null && _day.returnTime != null &&
        _day.state == DayState.returned) {
      _returnHome = _day.returnTime;
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
        if (_pendingTab == 2) _statsRefreshTrigger++;
      });
      _tabFadeCtrl.reverse();
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
    await _load();
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
              SafeArea(child: _recordsPage()),
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
    final colors = _dk
      ? [BotanicalColors.scaffoldDark, BotanicalColors.scaffoldDark]
      : [BotanicalColors.scaffoldLight, const Color(0xFFF1F5F9)];
    return Positioned.fill(
      child: Container(color: colors[0]),
    );
  }

  Widget _bottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: _dk ? const Color(0xFF1E293B) : Colors.white,
        boxShadow: [
          BoxShadow(
            color: (_dk ? Colors.black : Colors.blueGrey).withValues(alpha: _dk ? 0.3 : 0.08),
            blurRadius: 16, offset: const Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _navItem(0, Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, '홈'),
            _navItem(1, Icons.check_circle_outline_rounded, Icons.check_circle_rounded, 'Todo'),
            _navItem(2, Icons.timeline_outlined, Icons.timeline_rounded, '기록'),
            _navItem(3, Icons.calendar_today_outlined, Icons.calendar_today_rounded, '캘린더'),
          ]),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, IconData activeIcon, String label) {
    final sel = _tab == index;
    final selColor = _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;
    final c = sel ? selColor : _textMuted;
    return GestureDetector(
      onTap: () => _switchTab(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(clipBehavior: Clip.none, children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(sel ? activeIcon : icon, key: ValueKey(sel), size: 22, color: c),
            ),
          ]),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(
            fontSize: 10, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, color: c,
            letterSpacing: -0.2)),
          const SizedBox(height: 2),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: sel ? 16 : 0, height: 2.5,
            decoration: BoxDecoration(
              color: sel ? selColor : Colors.transparent,
              borderRadius: BorderRadius.circular(2))),
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
      onRefresh: () => _load(forceServer: true),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ═══ HEADER ═══
          _staggered(0, _weatherHeaderBar()),
          const SizedBox(height: 10),

          // ═══ SPECIAL DAY BANNER ═══
          if (_specialDay != null) ...[
            _staggered(0, _specialDayBanner()),
            const SizedBox(height: 10),
          ],

          // ═══ SLEEP PROTOCOL (WB 10주 위상전진) ═══
          _staggered(1, _sleepCard()),
          const SizedBox(height: 14),

          // ═══ STATUS ═══
          _staggered(2, _routineStatusCard()),
          const SizedBox(height: 14),

          // ═══ TODAY ═══
          _staggered(3, _dashSectionHeader('TODAY')),
          const SizedBox(height: 6),
          _staggered(3, _orderPortalChip()),
          const SizedBox(height: 12),

          // ═══ LOG ═══
          _staggered(4, _locationSummaryCard()),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _specialDayBanner() {
    final label = _specialDay?['label'] as String? ?? '특별한 날';
    final note = _specialDay?['note'] as String? ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _dk
            ? [const Color(0xFF1E3A5F), const Color(0xFF2D1B69)]
            : [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.3),
            blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white,
            letterSpacing: 0.5)),
          if (note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(note, style: TextStyle(
              fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
          ],
        ],
      ),
    );
  }

  Widget _dashSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2, top: 4),
      child: Text(title, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1.5,
        color: _textMuted)),
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
            Text('생활 기록', style: BotanicalTypo.label(
              size: 12, color: _textMuted)),
          ]),
        ]),
        const SizedBox(height: 16),

        // ── 통계 화면 (세그먼트 컨트롤 포함) ──
        StatisticsScreen(embedded: true, refreshTrigger: _statsRefreshTrigger),

        const SizedBox(height: 40),
      ],
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

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('${now.month}월 ${now.day}일', style: TextStyle(
            fontSize: 20, fontWeight: FontWeight.w800, color: _textMain,
            letterSpacing: -0.5)),
          Text(' $wd', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w500, color: _textMuted)),
          if (w != null) ...[
            const SizedBox(width: 10),
            GestureDetector(
              onTap: () async {
                await WeatherService().sendWeatherReport();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text('📩 날씨 정보를 Telegram으로 전송했습니다'),
                    duration: Duration(seconds: 2)));
                }
              },
              child: Text('${w.emoji} ${w.temp.round()}°${_weather.needsUmbrella(w) ? ' ☂️' : ''}',
                style: TextStyle(fontSize: 13, color: _textSub)),
            ),
          ],
          const Spacer(),
          _headerIconBtn(Icons.settings_outlined, () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())), size: 18),
        ]),
        const SizedBox(height: 4),
        // ★ 센서 상태 인라인
        _presenceBadge(),
      ]),
    );
  }

  /// 센서 상태를 헤더 아래에 작은 뱃지로 표시
  Widget _presenceBadge() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.doc(kIotDoc).snapshots(),
      builder: (ctx, snap) {
        String emoji = '📡', label = '센서 대기';
        Color color = _textMuted;
        String? timerStr;

        if (snap.hasError) {
          label = '연결 오류';
        } else if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>? ?? {};
          final presence = data['presence'] as Map<String, dynamic>?;
          final config = data['config'] as Map<String, dynamic>?;
          final bedThreshold = (config?['bedThresholdCm'] as num?)?.toInt() ?? 220;
          if (presence != null) {
            final state = presence['state'] as String? ?? 'unknown';
            final filtRaw = presence['filteredDistance'];
            final rawDist = presence['distance'];
            final filtDist = filtRaw is num ? filtRaw.toInt() : null;
            final dist = rawDist is num ? rawDist.toInt() : null;
            final zoneDist = filtDist ?? dist;
            final since = presence['stationarySince'];

            switch (state) {
              case 'peaceful':
                final isBed = zoneDist != null && zoneDist <= bedThreshold;
                emoji = isBed ? '🛏️' : '🪑';
                label = isBed ? '침대' : '책상';
                color = isBed ? const Color(0xFF8B5CF6) : BotanicalColors.primary;
                break;
              case 'presence':
                emoji = '🚶'; label = '움직임'; color = BotanicalColors.warning;
                break;
              case 'none':
                emoji = '—'; label = '비어있음'; color = _textMuted;
                break;
              default:
                emoji = '📡'; label = state; color = _textMuted;
            }

            if (since != null && since is Timestamp && state == 'peaceful'
                && zoneDist != null && zoneDist <= bedThreshold) {
              final min = DateTime.now().difference(since.toDate()).inMinutes;
              timerStr = min < 60 ? '${min}분' : '${min ~/ 60}h${min % 60}m';
            }
          }
        }

        return Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(emoji, style: const TextStyle(fontSize: 10)),
              const SizedBox(width: 3),
              Text(label, style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: color)),
              if (timerStr != null) ...[
                const SizedBox(width: 4),
                Text(timerStr, style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, color: color.withValues(alpha: 0.7))),
              ],
            ]),
          ),
          if (_sleepDurationLabel != null) ...[
            const SizedBox(width: 6),
            Text('😴 $_sleepDurationLabel', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted)),
          ],
        ]);
      },
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(
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
                  color: _dk ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
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
                color: hcLight.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(Icons.home_outlined, size: 16, color: hcLight))),
          const SizedBox(width: 6),
          _headerIconBtn(Icons.settings_outlined, () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const SettingsScreen())), size: 18),
        ]),
      ],
    ),
    const SizedBox(height: 4),
    _presenceBadge(),
    ]);
  }

  Widget _headerIconBtn(IconData icon, VoidCallback onTap, {double size = 16}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: _dk ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: size, color: _textMuted)),
    );
  }



}

