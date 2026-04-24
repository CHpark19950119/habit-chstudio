import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../models/order_models.dart';
import 'order_theme.dart';

/// ═══════════════════════════════════════════════════════════
/// 목표 · 습관 — v6.1 Visual Polish
/// 규칙적 · 정렬적 · 실용적 + 비주얼
/// ═══════════════════════════════════════════════════════════

class OrderGoalsTab extends StatefulWidget {
  final OrderData data;
  final void Function(VoidCallback fn) onUpdate;
  const OrderGoalsTab({super.key, required this.data, required this.onUpdate});
  @override
  State<OrderGoalsTab> createState() => _OrderGoalsTabState();
}

class _OrderGoalsTabState extends State<OrderGoalsTab>
    with TickerProviderStateMixin {
  OrderData get _d => widget.data;
  bool _showArchive = false;

  late AnimationController _enterCtrl;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))..forward();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _pulseCtrl.dispose();
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

  List<OrderGoal> get _activeGoals => _d.goals
      .where((g) => !g.isFinished).toList()
    ..sort((a, b) => (a.daysLeft ?? 9999).compareTo(b.daysLeft ?? 9999));

  List<OrderGoal> get _doneGoals => _d.goals
      .where((g) => g.isFinished).toList()
    ..sort((a, b) => (b.completedAt ?? b.failedAt ?? '')
        .compareTo(a.completedAt ?? a.failedAt ?? ''));

  List<OrderHabit> get _activeHabits => _d.habits
      .where((h) => !h.archived && h.settledAt == null).toList();

  List<OrderHabit> get _doneHabits => _d.habits
      .where((h) => h.archived || h.settledAt != null).toList();

  String get _today => todayStr();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
      children: [
        // ── 상단 요약 ──
        _summaryBar(),
        const SizedBox(height: 20),

        // ── 중장기 목표 ──
        _fadeSlide(0.0, 0.3, child: _sectionHeader('중장기 목표', Icons.flag_rounded, _activeGoals.length)),
        const SizedBox(height: 12),
        if (_activeGoals.isEmpty)
          _fadeSlide(0.1, 0.4, child: _emptyState('목표를 추가하고\n체크리스트로 진도를 관리하세요', Icons.track_changes_rounded))
        else
          ...List.generate(_activeGoals.length, (i) =>
            _fadeSlide(0.05 * i + 0.1, 0.05 * i + 0.4,
              child: _goalCard(_activeGoals[i], i))),
        _fadeSlide(0.2, 0.5, child: _addBtn('목표 추가', _showAddGoalSheet)),
        const SizedBox(height: 28),

        // ── 습관 ──
        _fadeSlide(0.3, 0.6, child: _sectionHeader('습관', Icons.local_fire_department_rounded, _activeHabits.length)),
        const SizedBox(height: 12),
        if (_activeHabits.isEmpty)
          _fadeSlide(0.35, 0.65, child: _emptyState('매일의 작은 루틴을 쌓아보세요', Icons.emoji_nature_rounded))
        else
          _fadeSlide(0.35, 0.65, child: _habitsGrid()),
        const SizedBox(height: 12),
        _fadeSlide(0.4, 0.7, child: _addBtn('습관 추가', _showAddHabitSheet)),

        // ── 성과 통계 ──
        if (_doneGoals.isNotEmpty || _activeHabits.isNotEmpty) ...[
          const SizedBox(height: 28),
          _fadeSlide(0.45, 0.75, child: _sectionHeader('성과', Icons.insights_rounded, 0, showCount: false)),
          const SizedBox(height: 12),
          _fadeSlide(0.5, 0.8, child: _performanceStats()),
        ],

        // ── 완료 아카이브 ──
        if (_doneGoals.isNotEmpty || _doneHabits.isNotEmpty) ...[
          const SizedBox(height: 28),
          _fadeSlide(0.6, 0.9, child: _archiveSection()),
        ],
      ],
    );
  }

  // ═══ FADE + SLIDE WRAPPER ═══
  Widget _fadeSlide(double begin, double end, {required Widget child}) {
    final anim = _stagger(begin, end);
    return AnimatedBuilder(animation: anim, builder: (_, __) => Opacity(
      opacity: anim.value,
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - anim.value)),
        child: child),
    ));
  }

  // ═══════════════════════════════════════════════════
  //  SUMMARY BAR — 상단 통계
  // ═══════════════════════════════════════════════════
  Widget _summaryBar() {
    final goals = _activeGoals.length;
    final habits = _activeHabits;
    final avgStreak = habits.isEmpty ? 0
        : (habits.map((h) => h.currentStreak).fold(0, (a, b) => a + b) / habits.length).round();
    final todayDone = habits.where((h) => h.isDoneOn(_today)).length;
    final completed = _doneGoals.where((g) => g.isCompleted).length;

    return _fadeSlide(0.0, 0.25, child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
      child: Row(children: [
        _miniStat('$goals', '진행 목표', OC.accent),
        _miniDivider(),
        _miniStat('$todayDone/${habits.length}', '오늘 습관', OC.success),
        _miniDivider(),
        _miniStat('$avgStreak일', '평균 연속', OC.amber),
        _miniDivider(),
        _miniStat('$completed', '달성', OC.text3),
      ]),
    ));
  }

  Widget _miniStat(String value, String label, Color c) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(
        fontSize: 17, fontWeight: FontWeight.w900, color: c,
        fontFeatures: const [FontFeature.tabularFigures()])),
      const SizedBox(height: 2),
      Text(label, style: const TextStyle(
        fontSize: 9, fontWeight: FontWeight.w600, color: OC.text3)),
    ]),
  );

  Widget _miniDivider() => Container(
    width: 1, height: 24,
    color: OC.border.withValues(alpha: 0.3));

  // ═══════════════════════════════════════════════════
  //  SECTION HEADER
  // ═══════════════════════════════════════════════════
  Widget _sectionHeader(String title, IconData icon, int count, {bool showCount = true}) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: OC.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, size: 14, color: OC.accent)),
      const SizedBox(width: 8),
      Text(title, style: const TextStyle(
        fontSize: 15, fontWeight: FontWeight.w900, color: OC.text1,
        letterSpacing: -0.3)),
      if (showCount) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(
            color: OC.accentBg, borderRadius: BorderRadius.circular(6)),
          child: Text('$count', style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800, color: OC.accent)),
        ),
      ],
      const Spacer(),
      Expanded(child: Container(height: 0.5, color: OC.border.withValues(alpha: 0.3))),
    ]);
  }

  // ═══════════════════════════════════════════════════
  //  GOAL CARD — 좌측 액센트바 + 그라데이션 + D-Day
  // ═══════════════════════════════════════════════════
  Widget _goalCard(OrderGoal g, int index) {
    final done = g.milestones.where((m) => m.done).length;
    final total = g.milestones.length;
    final progress = total > 0 ? done / total : 0.0;
    final dDay = g.dDayLabel;
    final accentC = _goalAccent(g.daysLeft, index);
    final pctText = total > 0 ? '${(progress * 100).round()}%' : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () => _showGoalDetail(g),
        child: Container(
          decoration: BoxDecoration(
            color: OC.card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: OC.border.withValues(alpha: 0.3))),
          child: IntrinsicHeight(child: Row(children: [
            // Left accent bar
            Container(width: 3,
              decoration: BoxDecoration(
                color: accentC,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14)))),
            // Content — 컴팩트 1줄
            Expanded(child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // 1행: 제목 + D-Day + %
                Row(children: [
                  Expanded(child: Text(g.title, style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: OC.text1),
                    maxLines: 1, overflow: TextOverflow.ellipsis)),
                  if (pctText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(pctText, style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: accentC)),
                  ],
                  if (dDay.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: accentC.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6)),
                      child: Text(dDay, style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800, color: accentC)),
                    ),
                  ],
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded,
                    size: 16, color: OC.text4.withValues(alpha: 0.4)),
                ]),
                // 2행: 프로그레스 바
                if (total > 0) ...[
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress, minHeight: 3,
                      backgroundColor: OC.border.withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation(accentC))),
                ],
              ]),
            )),
          ])),
        ),
      ),
    );
  }

  Color _goalAccent(int? daysLeft, int index) {
    if (daysLeft != null && daysLeft <= 0) return OC.error;
    if (daysLeft != null && daysLeft <= 7) return OC.amber;
    final colors = [OC.accent, const Color(0xFF8B5CF6), const Color(0xFF0EA5E9), const Color(0xFF10B981)];
    return colors[index % colors.length];
  }

  // ═══════════════════════════════════════════════════
  //  HABITS GRID — 2열 카드 그리드
  // ═══════════════════════════════════════════════════
  Widget _habitsGrid() {
    final items = _activeHabits;
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i += 2) {
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Expanded(child: _habitCard(items[i])),
          const SizedBox(width: 10),
          if (i + 1 < items.length)
            Expanded(child: _habitCard(items[i + 1]))
          else
            const Expanded(child: SizedBox()),
        ]),
      ));
    }
    return Column(children: rows);
  }

  Widget _habitCard(OrderHabit h) {
    final done = h.isDoneOn(_today);
    final streak = h.currentStreak;
    final maxDays = max(h.targetDays, streak + 1);
    final streakPct = streak / maxDays;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        h.toggleDate(_today);
        widget.onUpdate(() {});
        _safeSetState(() {});
      },
      onLongPress: () => _showHabitDetail(h),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: done ? OC.accent.withValues(alpha: 0.06) : OC.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: done ? OC.accent.withValues(alpha: 0.25) : OC.border.withValues(alpha: 0.4)),
          boxShadow: done ? [BoxShadow(color: OC.accent.withValues(alpha: 0.06),
            blurRadius: 12, offset: const Offset(0, 4))] : null),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Top row: emoji + check
          Row(children: [
            Text(h.emoji, style: const TextStyle(fontSize: 24)),
            const Spacer(),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 24, height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? OC.accent : Colors.transparent,
                border: Border.all(
                  color: done ? OC.accent : OC.text4.withValues(alpha: 0.4), width: 2)),
              child: done
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : null,
            ),
          ]),
          const SizedBox(height: 8),
          Text(h.title, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: done ? OC.text3 : OC.text1),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          // Streak progress
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: streakPct.clamp(0, 1),
              minHeight: 3,
              backgroundColor: OC.border.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(
                streak >= h.targetDays ? OC.success : OC.amber.withValues(alpha: 0.7)))),
          const SizedBox(height: 6),
          Row(children: [
            Text(h.growthEmoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 3),
            Text(h.growthLabel, style: const TextStyle(
              fontSize: 9, fontWeight: FontWeight.w600, color: OC.text3)),
            const Spacer(),
            if (streak > 0) Text('$streak일', style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w900, color: OC.amber)),
          ]),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  ADD BUTTON (점선 → 은은한 그라데이션)
  // ═══════════════════════════════════════════════════
  Widget _addBtn(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: () { HapticFeedback.selectionClick(); onTap(); },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            OC.accentBg.withValues(alpha: 0.5), OC.accentBg.withValues(alpha: 0.2)]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OC.accent.withValues(alpha: 0.12))),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_rounded, size: 16, color: OC.accent.withValues(alpha: 0.6)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700,
            color: OC.accent.withValues(alpha: 0.6))),
        ]),
      ),
    );
  }

  Widget _emptyState(String text, IconData icon) => Container(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Column(children: [
      Icon(icon, size: 32, color: OC.text4.withValues(alpha: 0.4)),
      const SizedBox(height: 10),
      Text(text, textAlign: TextAlign.center, style: const TextStyle(
        fontSize: 12, color: OC.text4, height: 1.5)),
    ]),
  );

  // ═══════════════════════════════════════════════════
  //  PERFORMANCE STATS — 성과 통계
  // ═══════════════════════════════════════════════════
  Widget _performanceStats() {
    final completed = _d.goals.where((g) => g.isCompleted).toList();
    final failed = _d.goals.where((g) => g.isFailed).toList();
    final totalFinished = completed.length + failed.length;
    final successRate = totalFinished > 0
        ? (completed.length / totalFinished * 100).round() : 0;

    final allHabits = _d.habits.where((h) => !h.archived).toList();
    final totalChecks = allHabits.fold<int>(0, (s, h) => s + h.completedDates.length);
    final bestHabit = allHabits.isNotEmpty
        ? (allHabits.toList()..sort((a, b) => b.currentStreak.compareTo(a.currentStreak))).first
        : null;
    final settled = _d.habits.where((h) => h.isSettled).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OC.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OC.border.withValues(alpha: 0.3)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
          blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── 목표 성과 ──
        Row(children: [
          const Text('🎯', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          const Text('목표 성과', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800, color: OC.text1)),
        ]),
        const SizedBox(height: 12),
        // Success/Fail ratio bar
        if (totalFinished > 0) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(height: 24, child: Row(children: [
              if (completed.isNotEmpty) Expanded(
                flex: completed.length,
                child: Container(
                  color: OC.success.withValues(alpha: 0.8),
                  alignment: Alignment.center,
                  child: Text('${completed.length} 달성', style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)))),
              if (failed.isNotEmpty) Expanded(
                flex: failed.length,
                child: Container(
                  color: OC.error.withValues(alpha: 0.7),
                  alignment: Alignment.center,
                  child: Text('${failed.length} 실패', style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white)))),
            ])),
          ),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('성공률 $successRate%', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800,
              color: successRate >= 70 ? OC.success : successRate >= 40 ? OC.amber : OC.error)),
            Text('총 $totalFinished건 완결', style: const TextStyle(
              fontSize: 11, color: OC.text3)),
          ]),
        ] else
          Text('아직 완결된 목표가 없습니다', style: const TextStyle(
            fontSize: 12, color: OC.text4)),

        // Divider
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Container(height: 0.5, color: OC.border.withValues(alpha: 0.3))),

        // ── 습관 성과 ──
        Row(children: [
          const Text('🔥', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 6),
          const Text('습관 성과', style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w800, color: OC.text1)),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          _perfBadge('누적 체크', '$totalChecks회', OC.accent),
          const SizedBox(width: 8),
          _perfBadge('정착 완료', '$settled개', OC.success),
          const SizedBox(width: 8),
          _perfBadge('최장 연속',
            bestHabit != null ? '${bestHabit.bestStreak}일' : '-',
            OC.amber),
        ]),

        // ── 최근 기록 (타임라인) ──
        if (totalFinished > 0) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Container(height: 0.5, color: OC.border.withValues(alpha: 0.3))),
          const Text('최근 기록', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: OC.text3)),
          const SizedBox(height: 8),
          ..._recentTimeline(),
        ],
      ]),
    );
  }

  Widget _perfBadge(String label, String value, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.1))),
      child: Column(children: [
        Text(value, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w900, color: c)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
          fontSize: 9, fontWeight: FontWeight.w600, color: OC.text3)),
      ]),
    ),
  );

  List<Widget> _recentTimeline() {
    final events = <_TimelineEvent>[];
    for (final g in _d.goals.where((g) => g.isFinished)) {
      final dateStr = g.completedAt ?? g.failedAt ?? '';
      events.add(_TimelineEvent(
        title: g.title,
        date: dateStr.length >= 10 ? dateStr.substring(0, 10) : '',
        isSuccess: g.isCompleted,
        icon: g.isCompleted ? Icons.check_circle_rounded : Icons.cancel_rounded,
      ));
    }
    events.sort((a, b) => b.date.compareTo(a.date));

    return events.take(5).map((e) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        // Timeline dot + line
        Column(children: [
          Container(
            width: 8, height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: e.isSuccess ? OC.success : OC.error)),
        ]),
        const SizedBox(width: 10),
        Expanded(child: Text(e.title, style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600,
          color: e.isSuccess ? OC.text2 : OC.text3),
          maxLines: 1, overflow: TextOverflow.ellipsis)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: e.isSuccess ? OC.successBg : OC.errorBg,
            borderRadius: BorderRadius.circular(6)),
          child: Text(e.isSuccess ? '달성' : '실패', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w800,
            color: e.isSuccess ? OC.success : OC.error)),
        ),
        const SizedBox(width: 8),
        Text(e.date, style: const TextStyle(fontSize: 9, color: OC.text4)),
      ]),
    )).toList();
  }

  // ═══════════════════════════════════════════════════
  //  ARCHIVE SECTION — 성공/실패 분리
  // ═══════════════════════════════════════════════════
  Widget _archiveSection() {
    final successGoals = _doneGoals.where((g) => g.isCompleted).toList();
    final failedGoals = _doneGoals.where((g) => g.isFailed).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OC.bgSub.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => _safeSetState(() => _showArchive = !_showArchive),
          child: Row(children: [
            const Icon(Icons.inventory_2_outlined, size: 15, color: OC.text3),
            const SizedBox(width: 8),
            const Text('아카이브', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: OC.text3)),
            const SizedBox(width: 6),
            if (successGoals.isNotEmpty) _archiveChip('${successGoals.length} 달성', OC.success),
            if (failedGoals.isNotEmpty) ...[
              const SizedBox(width: 4),
              _archiveChip('${failedGoals.length} 실패', OC.error),
            ],
            const Spacer(),
            AnimatedRotation(
              turns: _showArchive ? 0.5 : 0,
              duration: const Duration(milliseconds: 200),
              child: const Icon(Icons.expand_more_rounded, size: 20, color: OC.text4)),
          ]),
        ),
        if (_showArchive) ...[
          if (successGoals.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [
              Container(width: 3, height: 12,
                decoration: BoxDecoration(
                  color: OC.success, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              const Text('달성한 목표', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: OC.success)),
            ]),
            const SizedBox(height: 8),
            ...successGoals.map((g) => _archiveGoalRow(g)),
          ],
          if (failedGoals.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [
              Container(width: 3, height: 12,
                decoration: BoxDecoration(
                  color: OC.error, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              const Text('실패한 목표', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: OC.error)),
            ]),
            const SizedBox(height: 8),
            ...failedGoals.map((g) => _archiveGoalRow(g)),
          ],
          if (_doneHabits.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(children: [
              Container(width: 3, height: 12,
                decoration: BoxDecoration(
                  color: OC.text4, borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 8),
              const Text('습관', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: OC.text3)),
            ]),
            const SizedBox(height: 8),
            ..._doneHabits.map(_archiveHabitRow),
          ],
        ],
      ]),
    );
  }

  Widget _archiveChip(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: c.withValues(alpha: 0.15))),
    child: Text(text, style: TextStyle(
      fontSize: 9, fontWeight: FontWeight.w800, color: c)),
  );

  Widget _archiveGoalRow(OrderGoal g) {
    final c = g.isCompleted ? OC.success : OC.error;
    final dateStr = g.completedAt ?? g.failedAt ?? '';
    final date = dateStr.length >= 10 ? dateStr.substring(0, 10) : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle, color: c.withValues(alpha: 0.1)),
          child: Icon(
            g.isCompleted ? Icons.check_rounded : Icons.close_rounded,
            size: 12, color: c)),
        const SizedBox(width: 10),
        Expanded(child: Text(g.title, style: TextStyle(
          fontSize: 12, color: OC.text3,
          decoration: TextDecoration.lineThrough,
          decorationColor: c.withValues(alpha: 0.3)))),
        if (g.failedNote != null && g.failedNote!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Tooltip(message: g.failedNote!,
              child: Icon(Icons.info_outline_rounded, size: 14,
                color: OC.text4.withValues(alpha: 0.5)))),
        Text(date, style: const TextStyle(fontSize: 9, color: OC.text4)),
      ]),
    );
  }

  Widget _archiveHabitRow(OrderHabit h) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Text(h.emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 10),
        Expanded(child: Text(h.title, style: const TextStyle(
          fontSize: 12, color: OC.text3, decoration: TextDecoration.lineThrough))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: h.isSettled ? OC.successBg : OC.bgSub,
            borderRadius: BorderRadius.circular(6)),
          child: Text(h.isSettled ? '정착' : '보관', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700,
            color: h.isSettled ? OC.success : OC.text4)),
        ),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════
  //  GOAL DETAIL SHEET
  // ═══════════════════════════════════════════════════
  void _showGoalDetail(OrderGoal g) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setBS) {
          final done = g.milestones.where((m) => m.done).length;
          final total = g.milestones.length;
          final addCtrl = TextEditingController();

          return Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            padding: EdgeInsets.only(bottom: sheetBottomPad(ctx)),
            decoration: const BoxDecoration(
              color: OC.bg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              sheetHandle(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(g.title, style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800, color: OC.text1))),
                    if (g.dDayLabel.isNotEmpty) Text(g.dDayLabel, style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w800,
                      color: _goalAccent(g.daysLeft, 0))),
                  ]),
                  if (g.deadline != null) ...[
                    const SizedBox(height: 4),
                    Text('마감 ${g.deadline}', style: const TextStyle(
                      fontSize: 12, color: OC.text3)),
                  ],
                  if (total > 0) ...[
                    const SizedBox(height: 14),
                    Row(children: List.generate(total, (i) {
                      final isDone = g.milestones[i].done;
                      return Expanded(child: Container(
                        height: 4,
                        margin: EdgeInsets.only(right: i < total - 1 ? 3 : 0),
                        decoration: BoxDecoration(
                          color: isDone ? OC.accent : OC.border.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2)),
                      ));
                    })),
                    const SizedBox(height: 6),
                    Text('$done / $total 완료', style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: OC.text3)),
                  ],
                  const SizedBox(height: 16),
                ]),
              ),
              Flexible(child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                shrinkWrap: true,
                children: [
                  ...g.milestones.map((ms) => _milestoneRow(ms, g, setBS)),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: TextField(
                      controller: addCtrl,
                      style: const TextStyle(fontSize: 13, color: OC.text1),
                      decoration: InputDecoration(
                        hintText: '항목 추가...',
                        hintStyle: const TextStyle(color: OC.text4),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                        filled: true, fillColor: OC.cardHi,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: OC.border)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: OC.border)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: OC.accent)),
                      ),
                      onSubmitted: (v) {
                        if (v.trim().isEmpty) return;
                        g.milestones.add(OrderMilestone(
                          id: 'ms_${DateTime.now().millisecondsSinceEpoch}',
                          text: v.trim()));
                        g.recalcFromMilestones();
                        widget.onUpdate(() {});
                        addCtrl.clear();
                        setBS(() {});
                        _safeSetState(() {});
                      },
                    )),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        if (addCtrl.text.trim().isEmpty) return;
                        g.milestones.add(OrderMilestone(
                          id: 'ms_${DateTime.now().millisecondsSinceEpoch}',
                          text: addCtrl.text.trim()));
                        g.recalcFromMilestones();
                        widget.onUpdate(() {});
                        addCtrl.clear();
                        setBS(() {});
                        _safeSetState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: OC.accent, borderRadius: BorderRadius.circular(12)),
                        child: const Icon(Icons.add_rounded,
                          size: 18, color: Colors.white),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(child: sheetBtn('완료 처리', OC.success, Colors.white, () {
                      g.completedAt = DateTime.now().toIso8601String();
                      g.progress = 100;
                      widget.onUpdate(() {});
                      Navigator.pop(ctx);
                      _safeSetState(() {});
                    })),
                    const SizedBox(width: 10),
                    Expanded(child: sheetBtn('편집', OC.bgSub, OC.text2, () {
                      Navigator.pop(ctx);
                      _showEditGoalSheet(g);
                    })),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () {
                        _d.goals.remove(g);
                        widget.onUpdate(() {});
                        Navigator.pop(ctx);
                        _safeSetState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: OC.errorBg,
                          borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.delete_outline_rounded,
                          size: 20, color: OC.error),
                      ),
                    ),
                  ]),
                ],
              )),
            ]),
          );
        });
      },
    );
  }

  Widget _milestoneRow(OrderMilestone ms, OrderGoal g,
      void Function(void Function()) setBS) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          ms.done = !ms.done;
          g.recalcFromMilestones();
          widget.onUpdate(() {});
          setBS(() {});
          _safeSetState(() {});
        },
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22, height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: ms.done ? OC.accent : Colors.transparent,
              border: Border.all(
                color: ms.done ? OC.accent : OC.text4, width: 1.5)),
            child: ms.done
                ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(ms.text, style: TextStyle(
            fontSize: 14, color: ms.done ? OC.text3 : OC.text1,
            decoration: ms.done ? TextDecoration.lineThrough : null))),
          GestureDetector(
            onTap: () {
              g.milestones.remove(ms);
              g.recalcFromMilestones();
              widget.onUpdate(() {});
              setBS(() {});
              _safeSetState(() {});
            },
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close_rounded, size: 16, color: OC.text4)),
          ),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  ADD / EDIT GOAL SHEETS
  // ═══════════════════════════════════════════════════
  String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _showAddGoalSheet() {
    final titleCtrl = TextEditingController();
    DateTime? deadline;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setBS) => Container(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: sheetBottomPad(ctx)),
        decoration: const BoxDecoration(color: OC.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          sheetHandle(), const SizedBox(height: 12),
          const Text('목표 추가', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: OC.text1)),
          const SizedBox(height: 16),
          sheetField('제목', titleCtrl, '예: 1차 PSAT 커트라인 달성'),
          const SizedBox(height: 8),
          _datePicker(deadline, (d) => setBS(() => deadline = d), ctx),
          const SizedBox(height: 20),
          sheetBtn('추가', OC.accent, Colors.white, () {
            if (titleCtrl.text.trim().isEmpty) return;
            _d.goals.add(OrderGoal(
              id: 'g_${DateTime.now().millisecondsSinceEpoch}',
              title: titleCtrl.text.trim(),
              deadline: deadline != null ? _fmtDate(deadline!) : null));
            widget.onUpdate(() {});
            Navigator.pop(ctx);
            _safeSetState(() {});
          }),
        ]),
      )),
    );
  }

  void _showEditGoalSheet(OrderGoal g) {
    final titleCtrl = TextEditingController(text: g.title);
    DateTime? deadline = g.deadline != null ? DateTime.tryParse(g.deadline!) : null;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setBS) => Container(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: sheetBottomPad(ctx)),
        decoration: const BoxDecoration(color: OC.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          sheetHandle(), const SizedBox(height: 12),
          const Text('목표 편집', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: OC.text1)),
          const SizedBox(height: 16),
          sheetField('제목', titleCtrl, '목표 제목'),
          const SizedBox(height: 8),
          _datePicker(deadline, (d) => setBS(() => deadline = d), ctx,
            clearable: true, onClear: () => setBS(() => deadline = null)),
          const SizedBox(height: 20),
          sheetBtn('저장', OC.accent, Colors.white, () {
            if (titleCtrl.text.trim().isEmpty) return;
            g.title = titleCtrl.text.trim();
            g.deadline = deadline != null ? _fmtDate(deadline!) : null;
            widget.onUpdate(() {});
            Navigator.pop(ctx);
            _safeSetState(() {});
          }),
        ]),
      )),
    );
  }

  Widget _datePicker(DateTime? current, Function(DateTime) onPick,
      BuildContext ctx, {bool clearable = false, VoidCallback? onClear}) {
    return GestureDetector(
      onTap: () async {
        final picked = await showDatePicker(
          context: ctx,
          initialDate: current ?? DateTime.now().add(const Duration(days: 30)),
          firstDate: DateTime(2020), lastDate: DateTime(2030),
          builder: (c, child) => Theme(
            data: Theme.of(c).copyWith(
              colorScheme: const ColorScheme.light(primary: OC.accent)),
            child: child!),
        );
        if (picked != null) onPick(picked);
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: OC.cardHi, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OC.border)),
        child: Row(children: [
          const Icon(Icons.calendar_today_rounded, size: 16, color: OC.text3),
          const SizedBox(width: 10),
          Text(current != null ? _fmtDate(current) : '마감일 선택 (선택사항)',
            style: TextStyle(fontSize: 14,
              color: current != null ? OC.text1 : OC.text4)),
          if (clearable && current != null) ...[
            const Spacer(),
            GestureDetector(onTap: onClear,
              child: const Icon(Icons.close_rounded, size: 16, color: OC.text3)),
          ],
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  ADD HABIT SHEET
  // ═══════════════════════════════════════════════════
  void _showAddHabitSheet() {
    final titleCtrl = TextEditingController();
    final emojiCtrl = TextEditingController(text: '✅');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: sheetBottomPad(ctx)),
        decoration: const BoxDecoration(color: OC.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          sheetHandle(), const SizedBox(height: 12),
          const Text('습관 추가', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: OC.text1)),
          const SizedBox(height: 16),
          Row(children: [
            SizedBox(width: 60, child: sheetInput(emojiCtrl, '😊')),
            const SizedBox(width: 10),
            Expanded(child: sheetInput(titleCtrl, '예: 영단어 30분')),
          ]),
          const SizedBox(height: 20),
          sheetBtn('추가', OC.accent, Colors.white, () {
            if (titleCtrl.text.trim().isEmpty) return;
            _d.habits.add(OrderHabit(
              id: 'h_${DateTime.now().millisecondsSinceEpoch}',
              title: titleCtrl.text.trim(),
              emoji: emojiCtrl.text.trim().isNotEmpty ? emojiCtrl.text.trim() : '✅',
              rank: 1));
            widget.onUpdate(() {});
            Navigator.pop(ctx);
            _safeSetState(() {});
          }),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  HABIT DETAIL (long-press)
  // ═══════════════════════════════════════════════════
  void _showHabitDetail(OrderHabit h) {
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.only(left: 20, right: 20, top: 8, bottom: sheetBottomPad(ctx)),
        decoration: const BoxDecoration(color: OC.bg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          sheetHandle(), const SizedBox(height: 16),
          Text(h.emoji, style: const TextStyle(fontSize: 36)),
          const SizedBox(height: 8),
          Text(h.title, style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w800, color: OC.text1)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _detailStat('현재 연속', '${h.currentStreak}일', OC.accent),
            _detailStat('최고 기록', '${h.bestStreak}일', OC.amber),
            _detailStat('성장 단계', '${h.growthEmoji} ${h.growthLabel}', OC.success),
          ]),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: sheetBtn('보관', OC.bgSub, OC.text2, () {
              h.archived = true;
              widget.onUpdate(() {});
              Navigator.pop(ctx);
              _safeSetState(() {});
            })),
            const SizedBox(width: 10),
            Expanded(child: sheetBtn('삭제', OC.errorBg, OC.error, () {
              _d.habits.remove(h);
              widget.onUpdate(() {});
              Navigator.pop(ctx);
              _safeSetState(() {});
            })),
          ]),
        ]),
      ),
    );
  }

  Widget _detailStat(String label, String value, Color c) => Column(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.12))),
      child: Text(value, style: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w800, color: c)),
    ),
    const SizedBox(height: 4),
    Text(label, style: const TextStyle(
      fontSize: 9, fontWeight: FontWeight.w600, color: OC.text3)),
  ]);
}

// ═══ Helper ═══
class _TimelineEvent {
  final String title;
  final String date;
  final bool isSuccess;
  final IconData icon;
  const _TimelineEvent({
    required this.title, required this.date,
    required this.isSuccess, required this.icon});
}
