import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:intl/date_symbol_data_local.dart';
import '../theme/botanical_theme.dart';
import '../models/models.dart';
import '../services/firebase_service.dart';
import '../utils/date_utils.dart';
import 'memo_screen.dart';

/// ═══════════════════════════════════════════════════════════
/// 통계 화면 — 트렌디 모션 리디자인
/// Staggered entrance · Animated counters · Mesh glow
/// Interactive donut · Morphing blob · Cyber pulse
/// ═══════════════════════════════════════════════════════════

class StatisticsScreen extends StatefulWidget {
  final bool embedded;
  final int refreshTrigger;
  const StatisticsScreen({super.key, this.embedded = false, this.refreshTrigger = 0});
  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen>
    with TickerProviderStateMixin {
  final _fb = FirebaseService();

  bool _loading = true;

  // ── 데일리 일기 ──
  String _diaryText = '';
  String? _diaryMood;
  DailyDiary? _todayDiary;
  bool _diaryLoading = false;
  final _diaryController = TextEditingController();

  List<_SleepPoint> _sleepPattern = [];

  // ★ 루틴 통계 (7일 평균)
  int? _avgPrepMin;
  int? _avgCommuteToMin;
  int? _avgCommuteFromMin;
  int? _avgStudyDurMin;
  int? _avgFreeMin;
  int? _avgSleepMin;

  // ★ 데일리 로그 — 시간 사용 분석
  Map<String, int> _timeUsage7d = {};
  List<int> _wakeTrend = [];
  List<int> _bedTrend = [];
  int? _todayPrepMin;
  int? _todayCommuteMin;
  int? _todayStudyMin;
  int? _todayFreeMin;

  late AnimationController _enterCtrl;
  late AnimationController _chartCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _countCtrl;
  late AnimationController _glowCtrl;
  late Animation<double> _chartAnim;
  late Animation<double> _countAnim;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;
  Color get _border => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
    _chartCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
    _countCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
    _glowCtrl  = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000))..repeat(reverse: true);
    _chartAnim = CurvedAnimation(parent: _chartCtrl, curve: Curves.easeOutCubic);
    _countAnim = CurvedAnimation(parent: _countCtrl, curve: Curves.easeOutExpo);
    _load();
    _loadTodayDiary();
  }

  @override
  void didUpdateWidget(covariant StatisticsScreen old) {
    super.didUpdateWidget(old);
    if (old.refreshTrigger != widget.refreshTrigger) _load();
  }

  @override
  void dispose() {
    _enterCtrl.dispose(); _chartCtrl.dispose();
    _pulseCtrl.dispose(); _countCtrl.dispose(); _glowCtrl.dispose();
    _diaryController.dispose();
    super.dispose();
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

  Animation<double> _stagger(double begin, double end) =>
    CurvedAnimation(parent: _enterCtrl,
      curve: Interval(begin.clamp(0, 1), end.clamp(0, 1), curve: Curves.easeOutCubic));

  Future<void> _load() async {
    if (!mounted) return;
    _safeSetState(() => _loading = true);
    final now = DateTime.now();
    // ★ 4AM 경계 적용 — Firestore 키와 일치하도록
    final today = StudyDateUtils.effectiveDate(now);

    // ── 0. Locale 안전 보장 ──
    try { DateFormat('E', 'ko').format(now); } catch (_) {
      try { await initializeDateFormatting('ko', null); } catch (_) {}
    }

    String _dayLabel(DateTime d) {
      try { return DateFormat('E', 'ko').format(d); } catch (_) {
        const labels = ['일', '월', '화', '수', '목', '금', '토'];
        return labels[d.weekday % 7];
      }
    }

    // ── 시간기록 로드 ──
    Map<String, TimeRecord> tr = {};
    try {
      tr = await _fb.getTimeRecords();
    } catch (e) { debugPrint('[Statistics] Firebase records error: $e'); }

    // ── 수면 패턴 ──
    final sleepPts = <_SleepPoint>[];
    try {
      for (int i = 6; i >= 0; i--) {
        final d = today.subtract(Duration(days: i));
        final ds = DateFormat('yyyy-MM-dd').format(d);
        final rec = tr[ds];
        sleepPts.add(_SleepPoint(label: _dayLabel(d),
          wakeMin: rec?.wake != null ? _t2m(rec!.wake!) : null,
          bedMin: rec?.bedTime != null ? _t2m(rec!.bedTime!) : null));
      }
    } catch (e) { debugPrint('[Statistics] Sleep pattern error: $e'); }

    // ── 4b. 루틴 통계 (7일 평균) ──
    int? avgPrep, avgCommTo, avgCommFrom, avgStudy, avgFree, avgSleep;
    try {
      final prepList = <int>[];
      final freeList = <int>[];
      final sleepList = <int>[];

      for (int i = 0; i < 7; i++) {
        final ds = DateFormat('yyyy-MM-dd').format(today.subtract(Duration(days: i)));
        final rec = tr[ds];
        if (rec == null) continue;

        // 준비시간: 기상→외출
        if (rec.wake != null && rec.outing != null) {
          final wp = rec.wake!.split(':'); final ep = rec.outing!.split(':');
          final wm = int.parse(wp[0]) * 60 + int.parse(wp[1]);
          final em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
          var prep = em - wm;
          if (prep < 0) prep += 1440;
          if (prep > 0 && prep < 300) prepList.add(prep); // 5시간 미만만 유효
        }
        // 자유시간: 귀가→취침
        if (rec.returnHome != null && rec.bedTime != null) {
          final rp = rec.returnHome!.split(':'); final bp = rec.bedTime!.split(':');
          var rm = int.parse(rp[0]) * 60 + int.parse(rp[1]);
          var bm = int.parse(bp[0]) * 60 + int.parse(bp[1]);
          if (bm < rm) bm += 1440;
          final free = bm - rm;
          if (free > 0 && free < 720) freeList.add(free);
        }
      }
      // 수면시간: sleepPattern에서 계산
      for (final p in sleepPts) {
        if (p.bedMin != null && p.wakeMin != null) {
          final bedAdj = p.bedMin! < 600 ? p.bedMin! + 1440 : p.bedMin!;
          final wakeAdj = p.wakeMin! < 600 ? p.wakeMin! + 1440 : p.wakeMin!;
          var dur = wakeAdj > bedAdj ? wakeAdj - bedAdj : (wakeAdj + 1440) - bedAdj;
          if (dur > 0 && dur < 960) sleepList.add(dur);
        }
      }

      if (prepList.isNotEmpty) avgPrep = prepList.reduce((a, b) => a + b) ~/ prepList.length;
      if (freeList.isNotEmpty) avgFree = freeList.reduce((a, b) => a + b) ~/ freeList.length;
      if (sleepList.isNotEmpty) avgSleep = sleepList.reduce((a, b) => a + b) ~/ sleepList.length;
    } catch (e) { debugPrint('[Statistics] Routine stats error: $e'); }

    // ── 데일리 로그 — 시간 사용 분석 ──
    final timeUsage = <String, int>{};
    final wakes = <int>[];
    final beds = <int>[];
    int? tdPrep, tdCommute, tdStudy, tdFree;

    try {
      for (int i = 0; i < 7; i++) {
        final ds = DateFormat('yyyy-MM-dd').format(today.subtract(Duration(days: i)));
        final rec = tr[ds];
        if (rec == null) continue;

        // 기상/취침 트렌드
        if (rec.wake != null) {
          final wm = _t2m(rec.wake!);
          wakes.add(wm);
        }
        if (rec.bedTime != null) {
          final bm = _t2m(rec.bedTime!);
          beds.add(bm < 600 ? bm + 1440 : bm); // 자정 넘김 보정
        }

        // 카테고리별 시간 합산
        int _dur(String? s, String? e) {
          if (s == null || e == null) return 0;
          final sm = _t2m(s); var em = _t2m(e);
          if (em < sm) em += 1440;
          return (em - sm).clamp(0, 1440);
        }

        final prep = _dur(rec.wake, rec.outing);
        if (prep > 0 && prep < 300) timeUsage['준비'] = (timeUsage['준비'] ?? 0) + prep;

        if (rec.returnHome != null && rec.bedTime != null) {
          final free = _dur(rec.returnHome!, rec.bedTime!);
          if (free > 0 && free < 720) timeUsage['자유'] = (timeUsage['자유'] ?? 0) + free;
        }

        if (rec.mealStart != null && rec.mealEnd != null) {
          final meal = _dur(rec.mealStart!, rec.mealEnd!);
          if (meal > 0 && meal < 300) timeUsage['식사'] = (timeUsage['식사'] ?? 0) + meal;
        }

        // 오늘 데이터
        if (i == 0) {
          tdPrep = prep > 0 && prep < 300 ? prep : null;
          tdCommute = null;
          tdStudy = null;
          if (rec.returnHome != null && rec.bedTime != null) {
            final f = _dur(rec.returnHome!, rec.bedTime!);
            tdFree = f > 0 && f < 720 ? f : null;
          }
        }
      }
    } catch (e) { debugPrint('[Statistics] Time usage error: $e'); }


    if (!mounted) return;
    _safeSetState(() {
      _sleepPattern = sleepPts.isEmpty
        ? List.generate(7, (i) => _SleepPoint(label: _dayLabel(today.subtract(Duration(days: 6 - i)))))
        : sleepPts;
      _loading = false;
      // 루틴 통계
      _avgPrepMin = avgPrep; _avgCommuteToMin = avgCommTo;
      _avgCommuteFromMin = avgCommFrom; _avgStudyDurMin = avgStudy;
      _avgFreeMin = avgFree; _avgSleepMin = avgSleep;
      // 데일리 로그 강화
      _timeUsage7d = timeUsage;
      _wakeTrend = wakes; _bedTrend = beds;
      _todayPrepMin = tdPrep; _todayCommuteMin = tdCommute;
      _todayStudyMin = tdStudy; _todayFreeMin = tdFree;
    });
    _enterCtrl.forward(from: 0);
    _chartCtrl.forward(from: 0);
    _countCtrl.forward(from: 0);
  }

  int _t2m(String t) {
    try {
      // Handle ISO 8601 or HH:mm
      if (t.contains('T')) t = t.substring(t.indexOf('T') + 1).substring(0, 5);
      final p = t.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    } catch (_) { return 0; }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) return _body();
    return Scaffold(body: Stack(children: [_bgGradient(), SafeArea(child: _body())]));
  }

  Widget _body() {
    if (_loading) {
      return widget.embedded
        ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
        : Center(child: CircularProgressIndicator(color: _accent));
    }

    final dailyChildren = <Widget>[
      _animCard(0, _todaySummaryGlassCard()),
      const SizedBox(height: 14),
      _animCard(1, _dailyDiaryCard()),
      const SizedBox(height: 20),

      _animCard(2, _embeddedSectionLabel('⏱️', '시간 분석')),
      const SizedBox(height: 10),
      _animCard(2, _timeUsageCard()),
      const SizedBox(height: 20),

      _animCard(3, _embeddedSectionLabel('🌙', '생활 패턴')),
      const SizedBox(height: 10),
      _animCard(3, _dailyTrendCard()),
      const SizedBox(height: 14),
      _animCard(3, _routineCard()),
      const SizedBox(height: 14),
      _animCard(4, _sleepCard()),
      const SizedBox(height: 20),

      _animCard(5, Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _dailySectionHeader('📝', '생활 기록'),
          const SizedBox(height: 10),
          _dailyToolCard(
            icon: '💡', label: '메모', subtitle: '할일 및 메모 관리',
            color: const Color(0xFF8B6BAF),
            onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const MemoScreen())),
          ),
        ],
      )),
      const SizedBox(height: 20),
    ];

    if (widget.embedded) {
      return Column(mainAxisSize: MainAxisSize.min, children: dailyChildren);
    }

    return RefreshIndicator(
      color: _accent,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [_header(), const SizedBox(height: 24), ...dailyChildren],
      ),
    );
  }

  Widget _animCard(int i, Widget child) {
    final a = _stagger(i * 0.1, (i * 0.1 + 0.4).clamp(0, 1));
    return AnimatedBuilder(animation: a, builder: (_, __) =>
      Transform.translate(offset: Offset(0, 30 * (1 - a.value)),
        child: Opacity(opacity: a.value, child: child)));
  }

  Widget _embeddedSectionLabel(String emoji, String title) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 6),
      Text(title, style: BotanicalTypo.label(
        size: 12, weight: FontWeight.w800, letterSpacing: 1.0, color: _textMuted)),
      const SizedBox(width: 8),
      Expanded(child: Container(height: 0.5, color: _border.withValues(alpha: 0.3))),
    ]),
  );

  Widget _bgGradient() => Positioned.fill(child: Container(
    decoration: BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topCenter, end: Alignment.bottomCenter,
      stops: const [0.0, 0.3, 0.7, 1.0],
      colors: _dk
        ? [const Color(0xFF1C1410), const Color(0xFF1A1210), const Color(0xFF1D1512), const Color(0xFF181010)]
        : [const Color(0xFFFDF9F2), const Color(0xFFFAF5EC), const Color(0xFFF6F0E5), const Color(0xFFF2ECDF)]))));

  Widget _header() => Row(children: [
    GestureDetector(onTap: () => Navigator.pop(context),
      child: Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _dk ? BotanicalColors.surfaceDark : BotanicalColors.surfaceLight,
          borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _textSub))),
    const SizedBox(width: 14),
    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('통계', style: BotanicalTypo.heading(size: 26, weight: FontWeight.w800, color: _textMain)),
      Text('학습 분석과 생활 패턴', style: BotanicalTypo.label(size: 13, color: _textMuted)),
    ])),
  ]);


  // ═══ ④ Sleep Card ═══
  Widget _sleepCard() => AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      color: _dk ? const Color(0xFF161D30) : const Color(0xFFF0F4F8),
      border: Border.all(color: _dk
        ? Color.lerp(const Color(0xFF334155), const Color(0xFF38BDF8), _pulseCtrl.value * 0.15)!
        : const Color(0xFFCBD5E1)),
      boxShadow: _dk ? [BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: 0.04 + _pulseCtrl.value * 0.02),
        blurRadius: 20, spreadRadius: -2)] : null),
    child: CustomPaint(
      painter: _CyberGridPainter(dark: _dk, pulse: _pulseCtrl.value),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: const Color(0xFF38BDF8).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.bedtime_rounded, size: 16, color: Color(0xFF38BDF8))),
          const SizedBox(width: 10),
          Text('기상·취침 패턴', style: BotanicalTypo.body(size: 15, weight: FontWeight.w700,
            color: _dk ? const Color(0xFFF1F5F9) : BotanicalColors.textMain)),
          const Spacer(),
          AnimatedBuilder(animation: _pulseCtrl, builder: (_, __) =>
            Container(width: 6, height: 6, decoration: BoxDecoration(
              color: const Color(0xFF38BDF8).withValues(alpha: 0.3 + _pulseCtrl.value * 0.7),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: const Color(0xFF38BDF8).withValues(alpha: _pulseCtrl.value * 0.4), blurRadius: 6)]))),
        ]),
        const SizedBox(height: 16),

        // ── 수면 시간 요약 ──
        Builder(builder: (_) {
          final durations = <int>[];
          for (final p in _sleepPattern) {
            if (p.bedMin != null && p.wakeMin != null) {
              // 취침→기상 수면시간 계산 (자정 넘김 처리)
              final bedAdj = p.bedMin! < 600 ? p.bedMin! + 1440 : p.bedMin!;
              final wakeAdj = p.wakeMin! < 600 ? p.wakeMin! + 1440 : p.wakeMin!;
              final sleepMin = wakeAdj > bedAdj ? wakeAdj - bedAdj : (wakeAdj + 1440) - bedAdj;
              if (sleepMin > 0 && sleepMin < 960) durations.add(sleepMin); // 16시간 미만만 유효
            }
          }
          if (durations.isEmpty) return const SizedBox.shrink();
          final avg = durations.reduce((a, b) => a + b) ~/ durations.length;
          final avgH = avg ~/ 60;
          final avgM = avg % 60;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: _dk ? 0.06 : 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.1))),
              child: Row(children: [
                const Text('💤', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 8),
                Text('평균 수면', style: BotanicalTypo.label(size: 11, weight: FontWeight.w600,
                  color: _dk ? const Color(0xFF94A3B8) : BotanicalColors.textMuted)),
                const Spacer(),
                Text('${avgH}시간 ${avgM > 0 ? '${avgM}분' : ''}',
                  style: BotanicalTypo.body(size: 14, weight: FontWeight.w800,
                    color: const Color(0xFF38BDF8))),
              ]),
            ),
          );
        }),

        // ── 기상 영역 ──
        Row(children: [
          _legendDot(BotanicalColors.gold, '기상'),
          const SizedBox(width: 12),
          _legendDot(const Color(0xFF6B5DAF), '취침'),
        ]),
        const SizedBox(height: 4),
        Text('  기상 시간', style: BotanicalTypo.label(size: 10, weight: FontWeight.w700,
          color: BotanicalColors.gold.withValues(alpha: 0.8))),
        const SizedBox(height: 4),
        SizedBox(height: 75, child: AnimatedBuilder(animation: _chartAnim,
          builder: (_, __) => CustomPaint(size: const Size(double.infinity, 75),
            painter: _SingleLineChartPainter(
              data: _sleepPattern, isWake: true, progress: _chartAnim.value, dark: _dk)))),
        // 요일 라벨
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _sleepPattern.map((p) => Text(p.label,
            style: BotanicalTypo.label(size: 10, weight: FontWeight.w600,
              color: _dk ? const Color(0xFF64748B) : BotanicalColors.textMuted))).toList()),

        const SizedBox(height: 14),
        Container(height: 1, color: (_dk ? Colors.white : Colors.black).withValues(alpha: 0.06)),
        const SizedBox(height: 14),

        // ── 취침 영역 ──
        Text('  취침 시간', style: BotanicalTypo.label(size: 10, weight: FontWeight.w700,
          color: const Color(0xFF6B5DAF).withValues(alpha: 0.8))),
        const SizedBox(height: 4),
        SizedBox(height: 75, child: AnimatedBuilder(animation: _chartAnim,
          builder: (_, __) => CustomPaint(size: const Size(double.infinity, 75),
            painter: _SingleLineChartPainter(
              data: _sleepPattern, isWake: false, progress: _chartAnim.value, dark: _dk)))),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: _sleepPattern.map((p) => Text(p.label,
            style: BotanicalTypo.label(size: 10, weight: FontWeight.w600,
              color: _dk ? const Color(0xFF64748B) : BotanicalColors.textMuted))).toList()),
      ])),
  ));

  Widget _legendDot(Color c, String lb) => Row(children: [
    Container(width: 10, height: 3, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(2))),
    const SizedBox(width: 6),
    Text(lb, style: BotanicalTypo.label(size: 10, color: _dk ? const Color(0xFF94A3B8) : _textMuted)),
  ]);

  // ═══ ⑤½ Routine Card (7일 평균 루틴 통계) ═══
  Widget _routineCard() {
    final items = <_RoutineItem>[
      if (_avgPrepMin != null) _RoutineItem('🧴', '준비시간', _avgPrepMin!, const Color(0xFFFBBF24)),
      if (_avgCommuteToMin != null) _RoutineItem('🚌', '등교 이동', _avgCommuteToMin!, const Color(0xFF38BDF8)),
      if (_avgStudyDurMin != null) _RoutineItem('📚', '공부 체류', _avgStudyDurMin!, BotanicalColors.primary),
      if (_avgCommuteFromMin != null) _RoutineItem('🏠', '하교 이동', _avgCommuteFromMin!, const Color(0xFF818CF8)),
      if (_avgFreeMin != null) _RoutineItem('🎮', '자유시간', _avgFreeMin!, const Color(0xFF34D399)),
      if (_avgSleepMin != null) _RoutineItem('💤', '수면시간', _avgSleepMin!, const Color(0xFF6B5DAF)),
    ];
    if (items.isEmpty) return const SizedBox.shrink();

    // 전체 합계 (비율 바 기준)
    final totalMin = items.fold<int>(0, (s, i) => s + i.minutes);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF1A1F2E), const Color(0xFF1E2636)]
            : [const Color(0xFFFFFBF0), const Color(0xFFF8F4FF)]),
        border: Border.all(color: BotanicalColors.gold.withValues(alpha: _dk ? 0.1 : 0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [BotanicalColors.gold.withValues(alpha: 0.15), BotanicalColors.gold.withValues(alpha: 0.05)]),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.schedule_rounded, size: 18, color: BotanicalColors.gold)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('하루 루틴 분석', style: BotanicalTypo.body(size: 15, weight: FontWeight.w700, color: _textMain)),
            Text('최근 7일 평균', style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ])),
        ]),
        const SizedBox(height: 18),

        // ── 타임라인 스트립 (그라데이션) ──
        AnimatedBuilder(animation: _chartAnim, builder: (_, __) =>
          ClipRRect(borderRadius: BorderRadius.circular(8),
            child: SizedBox(height: 12,
              child: Row(children: items.map((item) {
                final pct = totalMin > 0 ? item.minutes / totalMin : 0.0;
                return Expanded(
                  flex: (pct * 1000 * _chartAnim.value).round().clamp(1, 1000),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 0.5),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [item.color, item.color.withValues(alpha: 0.6)]),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [BoxShadow(
                        color: item.color.withValues(alpha: 0.15), blurRadius: 3)])),
                );
              }).toList())))),
        const SizedBox(height: 20),

        // ── 각 항목 (카드형) ──
        ...items.asMap().entries.map((e) {
          final i = e.key; final item = e.value;
          final pct = totalMin > 0 ? (item.minutes / totalMin * 100).round() : 0;
          return Padding(
            padding: EdgeInsets.only(bottom: i < items.length - 1 ? 12 : 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: _dk ? 0.06 : 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: item.color.withValues(alpha: 0.08))),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: item.color.withValues(alpha: _dk ? 0.12 : 0.08),
                    borderRadius: BorderRadius.circular(10)),
                  child: Center(child: Text(item.emoji, style: const TextStyle(fontSize: 18))),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(item.label, style: BotanicalTypo.body(
                    size: 13, weight: FontWeight.w600, color: _textMain)),
                  Text('$pct%', style: BotanicalTypo.label(
                    size: 10, color: _textMuted)),
                ])),
                Text(_fmtMin(item.minutes),
                  style: BotanicalTypo.body(size: 14, weight: FontWeight.w800, color: item.color)),
              ]),
            ),
          );
        }),
      ]),
    );
  }

  // ═══ 시간 사용 분석 카드 (데일리 로그) ═══
  Widget _timeUsageCard() {
    if (_timeUsage7d.isEmpty) return const SizedBox.shrink();

    final categories = <_TimeCategory>[
      _TimeCategory('준비', '🌅', const Color(0xFFF59E0B), _timeUsage7d['준비'] ?? 0),
      _TimeCategory('등교', '🚌', const Color(0xFF38BDF8), _timeUsage7d['등교'] ?? 0),
      _TimeCategory('공부', '📚', BotanicalColors.primary, _timeUsage7d['공부'] ?? 0),
      _TimeCategory('식사', '🍽️', const Color(0xFFFF8A65), _timeUsage7d['식사'] ?? 0),
      _TimeCategory('하교', '🏠', const Color(0xFF818CF8), _timeUsage7d['하교'] ?? 0),
      _TimeCategory('자유', '🎮', const Color(0xFF34D399), _timeUsage7d['자유'] ?? 0),
    ];
    categories.removeWhere((c) => c.minutes == 0);
    if (categories.isEmpty) return const SizedBox.shrink();
    final totalMin = categories.fold<int>(0, (s, c) => s + c.minutes);

    // 오늘 vs 평균 비교
    final todayItems = <_TodayVsAvg>[];
    if (_todayPrepMin != null && _avgPrepMin != null)
      todayItems.add(_TodayVsAvg('준비', _todayPrepMin!, _avgPrepMin!, const Color(0xFFF59E0B)));
    if (_todayStudyMin != null && _avgStudyDurMin != null)
      todayItems.add(_TodayVsAvg('공부', _todayStudyMin!, _avgStudyDurMin!, BotanicalColors.primary));
    if (_todayCommuteMin != null)
      todayItems.add(_TodayVsAvg('이동', _todayCommuteMin!,
        (_avgCommuteToMin ?? 0) + (_avgCommuteFromMin ?? 0), const Color(0xFF38BDF8)));
    if (_todayFreeMin != null && _avgFreeMin != null)
      todayItems.add(_TodayVsAvg('자유', _todayFreeMin!, _avgFreeMin!, const Color(0xFF34D399)));

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF1A2436), const Color(0xFF1E2234)]
            : [const Color(0xFFF5F3FF), const Color(0xFFF0F9FF)]),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: _dk ? 0.12 : 0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF6366F1).withValues(alpha: 0.2), const Color(0xFF8B5CF6).withValues(alpha: 0.1)]),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.pie_chart_rounded, size: 16, color: Color(0xFF8B5CF6))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('시간 사용 분석', style: BotanicalTypo.body(size: 15, weight: FontWeight.w700, color: _textMain)),
            Text('최근 7일 누적', style: BotanicalTypo.label(size: 11, color: _textMuted)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Text('${totalMin ~/ 60}h ${totalMin % 60}m',
              style: BotanicalTypo.body(size: 12, weight: FontWeight.w800, color: const Color(0xFF8B5CF6))),
          ),
        ]),
        const SizedBox(height: 16),

        // ★ 카테고리별 그라데이션 바
        ...categories.map((c) {
          final pct = totalMin > 0 ? c.minutes / totalMin : 0.0;
          final avgPerDay = c.minutes ~/ 7;
          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(c.emoji, style: const TextStyle(fontSize: 15)),
                const SizedBox(width: 8),
                Expanded(child: Text(c.label, style: BotanicalTypo.body(
                  size: 13, weight: FontWeight.w600, color: _textMain))),
                Text(_fmtMin(c.minutes), style: BotanicalTypo.body(
                  size: 13, weight: FontWeight.w800, color: c.color)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text('${(pct * 100).round()}%', style: BotanicalTypo.label(
                    size: 9, weight: FontWeight.w700, color: c.color)),
                ),
              ]),
              const SizedBox(height: 6),
              AnimatedBuilder(animation: _chartAnim, builder: (_, __) =>
                ClipRRect(borderRadius: BorderRadius.circular(5),
                  child: Stack(children: [
                    Container(height: 8,
                      decoration: BoxDecoration(
                        color: _dk ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(5))),
                    FractionallySizedBox(widthFactor: pct * _chartAnim.value,
                      child: Container(height: 8,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [c.color, c.color.withValues(alpha: 0.5)]),
                          borderRadius: BorderRadius.circular(5),
                          boxShadow: [BoxShadow(
                            color: c.color.withValues(alpha: 0.2), blurRadius: 4)]))),
                  ]))),
              const SizedBox(height: 2),
              Text('일평균 ${_fmtMin(avgPerDay)}', style: BotanicalTypo.label(
                size: 9, color: _textMuted)),
            ]),
          );
        }),

        // 오늘 vs 평균 비교
        if (todayItems.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('오늘 vs 7일 평균', style: BotanicalTypo.label(
                size: 11, weight: FontWeight.w700, color: _textMuted)),
              const SizedBox(height: 10),
              ...todayItems.map((item) {
                final diff = item.today - item.avg;
                final sign = diff >= 0 ? '+' : '';
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(
                      color: item.color, shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    Text(item.label, style: BotanicalTypo.body(
                      size: 12, weight: FontWeight.w500, color: _textMain)),
                    const Spacer(),
                    Text(_fmtMin(item.today), style: BotanicalTypo.body(
                      size: 12, weight: FontWeight.w700, color: _textMain)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (diff >= 0 ? BotanicalColors.primary : const Color(0xFFEF4444)).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text('$sign${_fmtMin(diff.abs())}',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: diff >= 0 ? BotanicalColors.primary : const Color(0xFFEF4444))),
                    ),
                  ]),
                );
              }),
            ]),
          ),
        ],
      ]),
    );
  }

  // ═══ 기상/취침 트렌드 카드 ═══
  Widget _dailyTrendCard() {
    final hasWake = _wakeTrend.isNotEmpty;
    final hasBed = _bedTrend.isNotEmpty;
    if (!hasWake && !hasBed) return const SizedBox.shrink();

    String minToTime(int m) {
      final h = (m % 1440) ~/ 60;
      final min = m % 60;
      return '${h.toString().padLeft(2, '0')}:${min.toString().padLeft(2, '0')}';
    }

    final avgWake = hasWake ? (_wakeTrend.reduce((a, b) => a + b) ~/ _wakeTrend.length) : 0;
    final avgBed = hasBed ? (_bedTrend.reduce((a, b) => a + b) ~/ _bedTrend.length) : 0;

    // 수면 시간 계산
    int? avgSleepDur;
    if (hasWake && hasBed) {
      final bedAdj = avgBed;
      final wakeAdj = avgWake < 600 ? avgWake + 1440 : avgWake;
      final dur = wakeAdj > bedAdj ? wakeAdj - bedAdj : (wakeAdj + 1440) - bedAdj;
      if (dur > 0 && dur < 960) avgSleepDur = dur;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BotanicalDeco.card(_dk),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF6B5DAF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.bedtime_rounded, size: 16, color: Color(0xFF6B5DAF))),
          const SizedBox(width: 10),
          Text('수면 패턴 요약', style: BotanicalTypo.body(
            size: 15, weight: FontWeight.w700, color: _textMain)),
        ]),
        const SizedBox(height: 18),
        Row(children: [
          if (hasWake) _trendBadge('☀️ 평균 기상', minToTime(avgWake),
            color: const Color(0xFFF59E0B)),
          if (hasWake && hasBed) const SizedBox(width: 10),
          if (hasBed) _trendBadge('🌙 평균 취침', minToTime(avgBed % 1440),
            color: const Color(0xFF6B5DAF)),
          if (avgSleepDur != null) ...[
            const SizedBox(width: 10),
            _trendBadge('💤 평균 수면', _fmtMin(avgSleepDur),
              color: const Color(0xFF38BDF8)),
          ],
        ]),
        if (hasWake && _wakeTrend.length >= 3) ...[
          const SizedBox(height: 14),
          // 기상 시각 미니 트렌드 (최근→과거)
          SizedBox(height: 32,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_wakeTrend.length.clamp(0, 7), (i) {
                final m = _wakeTrend[i];
                final normalized = ((m - 300).clamp(0, 600)) / 600; // 5:00~15:00 범위
                return Expanded(child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: AnimatedBuilder(animation: _chartAnim, builder: (_, __) => Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Opacity(opacity: _chartAnim.value,
                      child: Text(minToTime(m), style: TextStyle(
                        fontSize: 7, color: _textMuted, fontWeight: FontWeight.w600))),
                    const SizedBox(height: 2),
                    Container(
                      height: ((24 * (1 - normalized)).clamp(4, 24).toDouble()) * _chartAnim.value,
                      decoration: BoxDecoration(
                        color: (i == 0 ? const Color(0xFFF59E0B) : const Color(0xFFF59E0B).withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(3))),
                  ])),
                ));
              }),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('오늘', style: BotanicalTypo.label(size: 9, color: _textMuted)),
              Text('7일 전', style: BotanicalTypo.label(size: 9, color: _textMuted)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _trendBadge(String label, String value, {required Color color}) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: _dk ? 0.08 : 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.1))),
      child: Column(children: [
        Text(value, style: BotanicalTypo.body(
          size: 14, weight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(label, style: BotanicalTypo.label(
          size: 9, color: _textMuted)),
      ]),
    ));
  }

  // ═══ 세그먼트 컨트롤 (glassmorphism) ═══
  // ═══ 오늘의 일기 카드 ═══
  Widget _dailyDiaryCard() {
    final moods = ['😊', '😐', '😔', '🔥', '😴', '🤯'];
    final hasDiary = _todayDiary != null && _todayDiary!.content.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF1E1A2E), const Color(0xFF1A1628)]
            : [const Color(0xFFF8F4FF), const Color(0xFFFFF8F0)],
        ),
        border: Border.all(
          color: _dk
            ? const Color(0xFF6B5DAF).withValues(alpha: 0.15)
            : const Color(0xFF6B5DAF).withValues(alpha: 0.08)),
        boxShadow: _dk ? null : [
          BoxShadow(
            color: const Color(0xFF6B5DAF).withValues(alpha: 0.06),
            blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF6B5DAF).withValues(alpha: _dk ? 0.15 : 0.1),
                borderRadius: BorderRadius.circular(12)),
              child: const Text('📖', style: TextStyle(fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('오늘의 일기', style: BotanicalTypo.body(
                  size: 15, weight: FontWeight.w700, color: _textMain)),
                Text(DateFormat('yyyy년 M월 d일 (E)', 'ko').format(DateTime.now()),
                  style: BotanicalTypo.label(size: 11, color: _textMuted)),
              ],
            )),
            if (_diaryLoading)
              SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2, color: const Color(0xFF6B5DAF).withValues(alpha: 0.5)))
            else if (hasDiary)
              Icon(Icons.check_circle_rounded, size: 18,
                color: BotanicalColors.primary.withValues(alpha: 0.6)),
          ]),
          const SizedBox(height: 16),
          // 기분 선택
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              Text('기분  ', style: BotanicalTypo.label(
                size: 11, weight: FontWeight.w600, color: _textMuted)),
              ...moods.map((m) {
                final sel = _diaryMood == m;
                return GestureDetector(
                  onTap: () => _safeSetState(() => _diaryMood = sel ? null : m),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: sel
                        ? const Color(0xFF6B5DAF).withValues(alpha: _dk ? 0.2 : 0.12)
                        : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: sel ? Border.all(
                        color: const Color(0xFF6B5DAF).withValues(alpha: 0.3)) : null,
                    ),
                    child: Text(m, style: TextStyle(fontSize: sel ? 20 : 17)),
                  ),
                );
              }),
            ]),
          ),
          const SizedBox(height: 12),
          // 텍스트 입력
          Container(
            decoration: BoxDecoration(
              color: _dk
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _dk
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04)),
            ),
            child: TextField(
              maxLines: 4, minLines: 3,
              controller: _diaryController,
              onChanged: (v) => _diaryText = v,
              style: TextStyle(
                fontSize: 13.5, height: 1.6,
                color: _textMain, fontFamily: 'Pretendard'),
              decoration: InputDecoration(
                hintText: '오늘 하루는 어땠나요? 자유롭게 적어보세요...',
                hintStyle: TextStyle(
                  fontSize: 13, color: _textMuted.withValues(alpha: 0.5)),
                contentPadding: const EdgeInsets.all(16),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // 저장/삭제 버튼
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            if (hasDiary)
              GestureDetector(
                onTap: _deleteDiary,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: _dk ? 0.1 : 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.15)),
                  ),
                  child: Text('삭제', style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600,
                    color: Colors.red.withValues(alpha: 0.7))),
                ),
              ),
            GestureDetector(
              onTap: _saveDiary,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [
                    const Color(0xFF6B5DAF),
                    const Color(0xFF6B5DAF).withValues(alpha: 0.7),
                  ]),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6B5DAF).withValues(alpha: 0.2),
                      blurRadius: 8, offset: const Offset(0, 2)),
                  ],
                ),
                child: const Text('저장', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── 일기 CRUD ──
  Future<void> _loadTodayDiary() async {
    _safeSetState(() => _diaryLoading = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final diary = await _fb.getDailyDiary(today);
      _safeSetState(() {
        _todayDiary = diary;
        _diaryText = diary?.content ?? '';
        _diaryMood = diary?.mood;
        _diaryController.text = _diaryText;
        _diaryLoading = false;
      });
    } catch (e) {
      debugPrint('[Diary] Load error: $e');
      _safeSetState(() => _diaryLoading = false);
    }
  }

  Future<void> _saveDiary() async {
    if (_diaryText.trim().isEmpty) return;
    _safeSetState(() => _diaryLoading = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final diary = DailyDiary(date: today, content: _diaryText.trim(), mood: _diaryMood);
      await _fb.saveDailyDiary(diary);
      if (mounted) {
        _safeSetState(() { _todayDiary = diary; _diaryLoading = false; });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('일기가 저장되었습니다 ✨'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF6B5DAF),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      debugPrint('[Diary] Save error: $e');
      _safeSetState(() => _diaryLoading = false);
    }
  }

  Future<void> _deleteDiary() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('일기 삭제'),
        content: const Text('오늘의 일기를 삭제하시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    _safeSetState(() => _diaryLoading = true);
    try {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await _fb.deleteDailyDiary(today);
      _safeSetState(() {
        _todayDiary = null; _diaryText = ''; _diaryMood = null;
        _diaryController.clear(); _diaryLoading = false;
      });
    } catch (e) {
      debugPrint('[Diary] Delete error: $e');
      _safeSetState(() => _diaryLoading = false);
    }
  }

  // ── 데일리 로그 공용 위젯 ──
  Widget _dailySectionHeader(String emoji, String title) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 16)),
      const SizedBox(width: 8),
      Text(title, style: BotanicalTypo.label(
        size: 13, weight: FontWeight.w800, letterSpacing: 0.5, color: _textMain)),
    ]),
  );

  // ═══ ★ 오늘 하루 요약 글래스 카드 (데일리 로그 최상단) ═══
  Widget _todaySummaryGlassCard() {
    final now = DateTime.now();
    String dayLabel;
    try { dayLabel = DateFormat('M월 d일 EEEE', 'ko').format(now); }
    catch (_) { dayLabel = '${now.month}월 ${now.day}일'; }

    final hour = now.hour;
    final greeting = hour < 6 ? '🌙 밤을 달려온 당신' :
                     hour < 12 ? '☀️ 활기찬 오전' :
                     hour < 18 ? '🌤️ 오후를 달리는 중' : '🌅 하루를 마무리하며';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [const Color(0xFF161D30), const Color(0xFF242150)]
            : [const Color(0xFFF0F9FF), const Color(0xFFF5F3FF)]),
        border: Border.all(
          color: _dk
            ? const Color(0xFF38BDF8).withValues(alpha: 0.12)
            : const Color(0xFF6366F1).withValues(alpha: 0.08)),
        boxShadow: _dk ? null : [
          BoxShadow(color: const Color(0xFF6366F1).withValues(alpha: 0.05),
            blurRadius: 24, offset: const Offset(0, 8))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(dayLabel, style: BotanicalTypo.label(
          size: 11, weight: FontWeight.w600, color: _textMuted)),
        const SizedBox(height: 2),
        Text(greeting, style: BotanicalTypo.body(
          size: 16, weight: FontWeight.w800, color: _textMain)),
        const SizedBox(height: 14),
        Row(children: [
          if (_wakeTrend.isNotEmpty)
            _dailyMiniChip('☀️', '기상 ${_fmtMin0(_wakeTrend.first)}'),
          if (_wakeTrend.isNotEmpty && _bedTrend.isNotEmpty) const SizedBox(width: 8),
          if (_bedTrend.isNotEmpty)
            _dailyMiniChip('🌙', '취침 ${_fmtMin0(_bedTrend.first)}'),
        ]),
      ]),
    );
  }

  Widget _dailyMiniChip(String emoji, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: _dk ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(8)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Text(emoji, style: const TextStyle(fontSize: 11)),
      const SizedBox(width: 4),
      Text(text, style: BotanicalTypo.label(
        size: 10, weight: FontWeight.w700, color: _textMuted)),
    ]),
  );

  String _fmtMin0(int m) {
    final h = (m % 1440) ~/ 60;
    final mn = m % 60;
    return '${h.toString().padLeft(2, '0')}:${mn.toString().padLeft(2, '0')}';
  }

  Widget _dailyToolCard({
    required String icon, required String label, required String subtitle,
    required Color color, required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _dk ? color.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _dk
            ? color.withValues(alpha: 0.12) : color.withValues(alpha: 0.08)),
          boxShadow: _dk ? null : [
            BoxShadow(color: color.withValues(alpha: 0.04),
              blurRadius: 12, offset: const Offset(0, 3))],
        ),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: _dk ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: BotanicalTypo.body(
                size: 14, weight: FontWeight.w600, color: _textMain)),
              Text(subtitle, style: BotanicalTypo.label(
                size: 11, color: _textMuted)),
            ],
          )),
          Icon(Icons.chevron_right_rounded, size: 20, color: _textMuted),
        ]),
      ),
    );
  }

  Widget _emptyCard(String emoji, String text) => Container(
    padding: const EdgeInsets.all(24), decoration: BotanicalDeco.card(_dk),
    child: Column(children: [
      Text(emoji, style: const TextStyle(fontSize: 36)), const SizedBox(height: 8),
      Text(text, style: BotanicalTypo.body(size: 14, color: _textMuted)),
    ]));

  String _fmtMin(int m) => m < 60 ? '${m}분' : '${m ~/ 60}시간 ${m % 60}분';
}

// ═══════════════════════════════════════════════════════════
//  Custom Painters
// ═══════════════════════════════════════════════════════════

class _CyberGridPainter extends CustomPainter {
  final bool dark; final double pulse;
  _CyberGridPainter({required this.dark, this.pulse = 0});
  @override
  void paint(Canvas canvas, Size size) {
    final base = (dark ? Colors.white : Colors.black).withValues(alpha: dark ? 0.03 : 0.025);
    final hl = const Color(0xFF38BDF8).withValues(alpha: 0.02 + pulse * 0.01);
    const g = 20.0;
    for (double x = 0; x < size.width; x += g) canvas.drawLine(Offset(x, 0), Offset(x, size.height), Paint()..color = base..strokeWidth = 0.5);
    for (double y = 0; y < size.height; y += g) {
      final near = (y - size.height / 2).abs() < g * 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()..color = near && dark ? hl : base..strokeWidth = 0.5);
    }
  }
  @override
  bool shouldRepaint(covariant _CyberGridPainter old) => old.pulse != pulse;
}

class _SleepPoint { final String label; final int? wakeMin, bedMin; _SleepPoint({required this.label, this.wakeMin, this.bedMin}); }

class _SingleLineChartPainter extends CustomPainter {
  final List<_SleepPoint> data; final bool isWake; final double progress; final bool dark;
  _SingleLineChartPainter({required this.data, required this.isWake, required this.progress, required this.dark});
  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    final w = size.width; final h = size.height;
    final seg = w / (data.length - 1).clamp(1, 100);
    final color = isWake ? const Color(0xFFD4A745) : const Color(0xFF6B5DAF);

    // 기상: 5:00(300)~10:00(600), 취침: 20:00(1200)~30:00(1800=6:00 다음날)
    final double minY, maxY;
    if (isWake) { minY = 300; maxY = 600; } else { minY = 1200; maxY = 1800; }
    double mapY(int m) {
      final adj = (!isWake && m < 600) ? m + 1440 : m.toDouble();
      return h - ((adj - minY) / (maxY - minY) * h).clamp(0.0, h);
    }

    // 기준선
    final gridHours = isWake ? [5, 6, 7, 8, 9] : [21, 22, 23, 0, 1, 2, 3, 4, 5];
    for (final hr in gridHours) {
      final realM = (isWake ? hr : (hr < 12 ? hr + 24 : hr)) * 60;
      final y = mapY(realM);
      if (y < 0 || y > h) continue;
      canvas.drawLine(Offset(0, y), Offset(w, y),
        Paint()..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.05)..strokeWidth = 0.5);
      final label = '${hr % 24}';
      TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: 8, color: (dark ? Colors.white : Colors.black).withValues(alpha: 0.2))),
        textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(0, y - 10));
    }

    // 데이터 포인트 (인덱스 매핑 포함)
    final pts = <Offset>[];
    final ptDataIdx = <int>[]; // pts → data 인덱스 매핑
    for (int i = 0; i < data.length; i++) {
      final m = isWake ? data[i].wakeMin : data[i].bedMin;
      if (m != null) {
        pts.add(Offset(i * seg, mapY(m) * progress + (h / 2) * (1 - progress)));
        ptDataIdx.add(i);
      }
    }
    if (pts.isEmpty) return;

    // 곡선
    if (pts.length == 1) { canvas.drawCircle(pts[0], 4, Paint()..color = color); return; }
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (int i = 0; i < pts.length - 1; i++) {
      final cx = (pts[i].dx + pts[i + 1].dx) / 2;
      path.cubicTo(cx, pts[i].dy, cx, pts[i + 1].dy, pts[i + 1].dx, pts[i + 1].dy);
    }
    final metrics = path.computeMetrics().toList();
    final total = metrics.fold(0.0, (s, m) => s + m.length);
    final drawn = Path(); var rem = total * progress;
    for (final m in metrics) { if (rem <= 0) break; drawn.addPath(m.extractPath(0, rem.clamp(0, m.length)), Offset.zero); rem -= m.length; }
    canvas.drawPath(drawn, Paint()..style = PaintingStyle.stroke..strokeWidth = 6..color = color.withValues(alpha: 0.12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.drawPath(drawn, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = color..strokeCap = StrokeCap.round);
    for (int pi = 0; pi < pts.length; pi++) {
      final p = pts[pi];
      canvas.drawCircle(p, 5, Paint()..color = color.withValues(alpha: 0.15));
      canvas.drawCircle(p, 3, Paint()..color = color);
      // 시간 라벨 (★ 올바른 data 인덱스 사용)
      final dataIdx = ptDataIdx[pi];
      final m = isWake ? data[dataIdx].wakeMin : data[dataIdx].bedMin;
      if (m != null) {
        final hr = (m ~/ 60) % 24; final mn = m % 60;
        final label = '${hr.toString().padLeft(2,'0')}:${mn.toString().padLeft(2,'0')}';
        TextPainter(text: TextSpan(text: label, style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: color.withValues(alpha: 0.8))),
          textDirection: TextDirection.ltr)..layout()..paint(canvas, Offset(p.dx - 12, p.dy > h / 2 ? p.dy - 12 : p.dy + 4));
      }
    }
  }
  @override
  bool shouldRepaint(covariant _SingleLineChartPainter old) => old.progress != progress;
}

class _RoutineItem {
  final String emoji, label; final int minutes; final Color color;
  _RoutineItem(this.emoji, this.label, this.minutes, this.color);
}

class _TimeCategory {
  final String label, emoji; final Color color; final int minutes;
  _TimeCategory(this.label, this.emoji, this.color, this.minutes);
}

class _TodayVsAvg {
  final String label; final int today, avg; final Color color;
  _TodayVsAvg(this.label, this.today, this.avg, this.color);
}
