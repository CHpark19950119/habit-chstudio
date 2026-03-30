part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — COMPASS 포탈 + 습관 큐 집중 카드 + 수험표 OCR
/// ⚠️ 네비바 충돌 금지
/// ═══════════════════════════════════════════════════
extension _HomeOrderSection on _HomeScreenState {

   // ── ORDER PORTAL — 라이트 컴팩트 COMPASS 카드 ──
  Widget _orderPortalChip() {
    final p1 = _orderData?.primaryGoal;
    final p2 = _orderData?.secondaryGoal;
    final focusHabits = _orderData?.focusHabits ?? [];
    final goals = <MapEntry<int, OrderGoal>>[
      if (p1 != null) MapEntry(1, p1),
      if (p2 != null) MapEntry(2, p2),
    ];
    final goalsDone = goals.where((e) => e.value.progress >= 100).length;

    // 테마 색상
    final cardBg = _dk ? const Color(0xFF1A1A2E) : Colors.white;
    final borderC = _dk ? const Color(0xFF2D2D44) : const Color(0xFFE8E4DF);
    final subtleBg = _dk ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8F7F5);
    final subtleBorder = _dk ? Colors.white.withValues(alpha: 0.08) : const Color(0xFFEEE9E2);
    final labelC = _dk ? Colors.white.withValues(alpha: 0.4) : const Color(0xFF94A3B8);
    final mainC = _dk ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B);

    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const OrderScreen(),
            transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 200),
          )).then((_) => _load());
      },
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: borderC),
        ),
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ═══ 헤더: COMPASS + D-day 뱃지 + > 화살표 ═══
          Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('COMPASS', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w800,
              color: mainC, letterSpacing: 1.2)),
            const Spacer(),
            Icon(Icons.chevron_right_rounded,
              size: 18, color: labelC),
          ]),

          // ═══ 습관: 최대 4개, 2열 동적 그리드 ═══
          if (focusHabits.isNotEmpty) ...[
            const SizedBox(height: 14),
            LayoutBuilder(builder: (ctx, constraints) {
              final habits = focusHabits.take(4).toList();
              final cardW = (constraints.maxWidth - 8) / 2;
              // 2열 Row 쌍으로 구성
              final rows = <Widget>[];
              for (int i = 0; i < habits.length; i += 2) {
                final row = Row(children: [
                  SizedBox(
                    width: cardW,
                    child: GestureDetector(
                      onTap: () => _toggleHabit(habits[i]),
                      child: _focusHabitCard(habits[i], subtleBg, subtleBorder, labelC, mainC, cardW))),
                  if (i + 1 < habits.length) ...[
                    const SizedBox(width: 8),
                    SizedBox(
                      width: cardW,
                      child: GestureDetector(
                        onTap: () => _toggleHabit(habits[i + 1]),
                        child: _focusHabitCard(habits[i + 1], subtleBg, subtleBorder, labelC, mainC, cardW))),
                  ],
                ]);
                if (rows.isNotEmpty) rows.add(const SizedBox(height: 8));
                rows.add(row);
              }
              return Column(children: rows);
            }),
          ],

          // ═══ 목표 ═══
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 14),
            _compassDivider(borderC),
            const SizedBox(height: 10),
            Row(children: [
              Text('GOALS', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w800,
                color: labelC, letterSpacing: 1)),
              const Spacer(),
              Text('$goalsDone/${goals.length}', style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w700, color: labelC)),
            ]),
            const SizedBox(height: 8),
            ...goals.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _compassGoalRow(e.key, e.value, mainC, labelC, subtleBg),
            )),
            if (goals.isNotEmpty && goals.first.value.dDayLabel.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Text(goals.first.value.dDayLabel, style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: labelC)),
              ),
          ],

          // ═══ 투두 요약 ═══
          if (_todayTodos != null && _todayTodos!.items.isNotEmpty) ...[
            const SizedBox(height: 10),
            _compassDivider(borderC),
            const SizedBox(height: 10),
            _compassTodoRow(_todayTodos!, mainC, labelC),
          ],


          // ═══ 데이터 없을 때 ═══
          if (focusHabits.isEmpty && goals.isEmpty) ...[
            const SizedBox(height: 8),
            Text('목표 · 습관 · 질서 관리', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: labelC)),
          ],
        ]),
      ),
    );
  }

  Widget _compassDivider(Color c) => Container(
    height: 1, color: c.withValues(alpha: 0.5));

  // ═══ 습관 카드 (2열 그리드 아이템) ═══
  Widget _focusHabitCard(OrderHabit h, Color bg, Color border, Color label, Color main, [double? width]) {
    final todayStr = StudyDateUtils.todayKey();
    final done = h.isDoneOn(todayStr);
    final streak = h.currentStreak;

    return Container(
      width: width,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: done
            ? const Color(0xFF22C55E).withValues(alpha: 0.3) : border)),
      child: Row(children: [
        Text(h.emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.title, style: TextStyle(
              fontSize: 11, color: label),
              maxLines: 1, overflow: TextOverflow.ellipsis),
            Row(children: [
              const Text('🔥', style: TextStyle(fontSize: 12)),
              Text(' ${streak}일', style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: main)),
            ]),
          ],
        )),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: done
                ? const Color(0xFFDCFCE7)
                : (_dk ? const Color(0xFF312E81) : const Color(0xFFEEF2FF)),
            borderRadius: BorderRadius.circular(6)),
          child: Text(done ? '완료' : '집중', style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w600,
            color: done
                ? const Color(0xFF16A34A)
                : const Color(0xFF6366F1))),
        ),
      ]),
    );
  }

  /// 습관 완료 처리 (홈에서 직접 체크 — 원터치 완료만)
  void _toggleHabit(OrderHabit h) {
    final todayStr = StudyDateUtils.todayKey();

    // ★ 이미 완료 시 무시 (실수 방지 — ORDER 탭에서 수정 가능)
    if (h.isDoneOn(todayStr)) return;

    HapticFeedback.mediumImpact();
    h.completedDates.add(todayStr);
    _saveOrderData();
    _safeSetState(() {});
  }

  /// ORDER 데이터 Firebase 저장 (★ Phase B: order 문서에 write)
  Future<void> _saveOrderData() async {
    if (_orderData == null) return;
    try {
      await FirebaseService().updateField('orderData', _orderData!.toMap());
    } catch (e) {
      debugPrint('[HomeOrder] orderData 저장 실패: $e');
    }
  }

  // ═══ COMPASS 내부 컴포넌트 ═══

  /// 목표 행 — 번호 뱃지 + 타이틀 + 미니 프로그레스
  Widget _compassGoalRow(int rank, OrderGoal g, Color main, Color label, Color bg) {
    final rankColors = {
      1: const Color(0xFFD97706),
      2: const Color(0xFF6366F1),
    };
    final rankBg = {
      1: _dk ? const Color(0xFF78350F) : const Color(0xFFFEF3C7),
      2: _dk ? const Color(0xFF312E81) : const Color(0xFFEEF2FF),
    };
    final c = rankColors[rank] ?? const Color(0xFF64748B);

    return Row(children: [
      Container(
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: rankBg[rank] ?? bg,
          borderRadius: BorderRadius.circular(8)),
        child: Center(child: Text('$rank', style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: c))),
      ),
      const SizedBox(width: 8),
      Expanded(child: Text(g.title, style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w500, color: main),
        maxLines: 1, overflow: TextOverflow.ellipsis)),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${g.progress}%', style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        const SizedBox(height: 3),
        Container(
          width: 50, height: 3,
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withValues(alpha: 0.06) : const Color(0xFFE8E4DF),
            borderRadius: BorderRadius.circular(2)),
          child: FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: (g.progress / 100).clamp(0.0, 1.0),
            child: Container(decoration: BoxDecoration(
              color: c, borderRadius: BorderRadius.circular(2))),
          ),
        ),
      ]),
    ]);
  }

  /// 투두 요약 1줄
  Widget _compassTodoRow(TodoDaily todos, Color main, Color label) {
    final rate = todos.completionRate;
    final rateColor = rate >= 0.8
        ? const Color(0xFF22C55E)
        : rate >= 0.5
            ? const Color(0xFFFBBF24)
            : const Color(0xFFEF4444);

    return GestureDetector(
      onTap: () => _switchTab(1),
      child: Row(children: [
        const Text('✅', style: TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Text('오늘의 할일', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w600, color: main)),
        const Spacer(),
        Text('${todos.completedCount}/${todos.totalCount}', style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w800, color: rateColor)),
      ]),
    );
  }


  // ══════════════════════════════════════════
  //  홈 → ORDER 플로팅 스위칭 버튼
  // ══════════════════════════════════════════
  Widget _orderFab() {
    return FloatingActionButton.small(
      heroTag: 'orderFab',
      backgroundColor: const Color(0xFF6366F1),
      elevation: 4,
      onPressed: () {
        HapticFeedback.mediumImpact();
        Navigator.push(context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const OrderScreen(),
            transitionsBuilder: (_, anim, __, child) =>
              SlideTransition(
                position: Tween(
                  begin: const Offset(1, 0), end: Offset.zero,
                ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
                child: child),
            transitionDuration: const Duration(milliseconds: 250),
          )).then((_) => _load());
      },
      child: const Icon(Icons.explore_rounded, size: 20, color: Colors.white),
    );
  }

}

/// 하루 타임라인 세그먼트 모델
class _DaySegment {
  final String start;
  final String end;
  final String label;
  final String emoji;
  final Color color;
  final String? startEvent;
  const _DaySegment({
    required this.start, required this.end,
    required this.label, required this.emoji, required this.color,
    this.startEvent});
}

