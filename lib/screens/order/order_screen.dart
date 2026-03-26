import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../models/order_models.dart';
import '../../data/plan_data.dart';
import '../../services/firebase_service.dart';
import '../../utils/study_date_utils.dart';
import 'order_theme.dart';
import 'order_goals_tab.dart';
import 'order_expense_tab.dart';
import '../journey_screen.dart';

/// ═══════════════════════════════════════════════════════════
/// COMPASS v5.0 — Command Center (Single Page)
/// Mission · Targets · Discipline · Quick Access
/// ═══════════════════════════════════════════════════════════

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});
  @override State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final _fb = FirebaseService();
  OrderData _data = OrderData();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    try {
      FirebaseService().invalidateStudyCache();
      final raw = await _fb.getStudyData();
      if (raw != null) {
        final od = raw['orderData'];
        if (od is Map && od.isNotEmpty) {
          _data = OrderData.fromMap(Map<String, dynamic>.from(od));
        }
      }
    } catch (_) {}
    _safeSetState(() => _loading = false);
  }

  bool _saving = false;
  bool _savePending = false;

  Future<void> _save() async {
    if (_saving) {
      _savePending = true; // 큐잉: 현재 저장 끝나면 다시 저장
      return;
    }
    _saving = true;
    try {
      await _fb.updateField('orderData', _data.toMap());
    } catch (e) {
      debugPrint('[Order] save error: $e');
    }
    _saving = false;
    if (_savePending) {
      _savePending = false;
      _save(); // 대기 중이던 저장 실행
    }
  }

  void _update(VoidCallback fn) {
    fn();               // 데이터 변경은 즉시 적용
    _safeSetState(() {});  // UI 갱신만 지연 가능
    _save();
  }

  String get _today => StudyDateUtils.todayKey();

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: OC.bg,
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: OC.accent))
            : SafeArea(child: Stack(children: [
                Positioned(top: -60, right: -40,
                  child: _meshSpot(OC.accent, 200, .06)),
                Positioned(bottom: 100, left: -60,
                  child: _meshSpot(OC.amber, 180, .05)),
                RefreshIndicator(
                  color: OC.accent,
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                    children: [
                      _header(),
                      const SizedBox(height: 20),
                      _missionCard(),
                      const SizedBox(height: 16),
                      _targetsSection(),
                      const SizedBox(height: 16),
                      _disciplineSection(),
                      const SizedBox(height: 16),
                      _overviewRow(),
                      const SizedBox(height: 10),
                      _expenseRow(),
                      const SizedBox(height: 20),
                      _quickAccess(),
                    ],
                  ),
                ),
              ])),
        floatingActionButton: FloatingActionButton.small(
          heroTag: 'homeFab',
          backgroundColor: OC.card,
          elevation: 4,
          onPressed: () {
            HapticFeedback.mediumImpact();
            Navigator.pop(context);
          },
          child: Icon(Icons.home_rounded, size: 20, color: OC.text2),
        ),
      ),
    );
  }

  Widget _meshSpot(Color c, double size, double op) => Container(
    width: size, height: size,
    decoration: BoxDecoration(shape: BoxShape.circle,
      gradient: RadialGradient(
        colors: [c.withValues(alpha: op), c.withValues(alpha: 0)])),
  );

  // ═══════════════════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════════════════
  Widget _header() {
    final primary = StudyPlanData.primaryDDay();
    return Row(children: [
      Container(width: 10, height: 10,
        decoration: const BoxDecoration(
          color: OC.accent, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      const Text('COMPASS', style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w900,
        color: OC.text1, letterSpacing: 2)),
      const Spacer(),
      if (primary != null) Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: primary.color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: primary.color.withValues(alpha: 0.3))),
        child: Text(primary.dDayLabel, style: TextStyle(
          fontSize: 13, fontWeight: FontWeight.w800, color: primary.color)),
      ),
    ]);
  }

  // ═══════════════════════════════════════════════════
  //  MISSION — 현재 기간 + 서브기간
  // ═══════════════════════════════════════════════════
  Widget _missionCard() {
    final period = StudyPlanData.periodForDate(_today);
    final sub = StudyPlanData.subPeriodForDate(_today);
    final daily = StudyPlanData.dailyPlanForDate(_today);

    if (period == null) {
      return _card(children: [
        const Text('현재 기간 없음', style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w600, color: OC.text3)),
      ]);
    }

    final progress = period.progressForDate(_today);

    return _card(children: [
      // Period header
      Row(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: OC.accent, borderRadius: BorderRadius.circular(8)),
          child: Text(period.id, style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(period.name, style: const TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: OC.text1))),
      ]),
      const SizedBox(height: 8),
      Text(period.goal, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w500, color: OC.text2)),
      const SizedBox(height: 10),
      // Progress
      Row(children: [
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress, minHeight: 6,
            backgroundColor: OC.bgSub,
            valueColor: AlwaysStoppedAnimation(OC.accent.withValues(alpha: 0.7))))),
        const SizedBox(width: 10),
        Text('${(progress * 100).toInt()}%', style: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w800, color: OC.accent)),
      ]),
      // Sub-period
      if (sub != null) ...[
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: OC.bgSub, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('📌', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              Text(sub.name, style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: OC.text1)),
              const Spacer(),
              Text('${sub.days}일', style: const TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: OC.text3)),
            ]),
            const SizedBox(height: 4),
            Text(sub.primaryGoal, style: const TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: OC.text2)),
            if (sub.goals.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...sub.goals.take(3).map((g) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('· ', style: TextStyle(fontSize: 11, color: OC.text3)),
                  Expanded(child: Text(g, style: const TextStyle(
                    fontSize: 11, color: OC.text3))),
                ]),
              )),
            ],
          ]),
        ),
      ],
      // Daily plan
      if (daily != null) ...[
        const SizedBox(height: 10),
        Row(children: [
          const Text('📋', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text(daily.title ?? '오늘의 플랜', style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w700, color: OC.text1)),
          if (daily.tag != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: StudyPlanData.tagColor(daily.tag!).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6)),
              child: Text(StudyPlanData.tagLabel(daily.tag!), style: TextStyle(
                fontSize: 9, fontWeight: FontWeight.w700,
                color: StudyPlanData.tagColor(daily.tag!))),
            ),
          ],
        ]),
        if (daily.tasks.isNotEmpty) ...[
          const SizedBox(height: 4),
          ...daily.tasks.map((t) => Padding(
            padding: const EdgeInsets.only(left: 20, top: 2),
            child: Text('· $t', style: const TextStyle(
              fontSize: 11, color: OC.text2)),
          )),
        ],
      ],
    ]);
  }

  // ═══════════════════════════════════════════════════
  //  TARGETS — 중장기 목표 (마감순 정렬)
  // ═══════════════════════════════════════════════════
  Widget _targetsSection() {
    final active = _data.goals
        .where((g) => !g.isFinished)
        .toList()
      ..sort((a, b) => (a.daysLeft ?? 9999).compareTo(b.daysLeft ?? 9999));

    return _card(children: [
      _sectionLabel('TARGETS', Icons.flag_rounded),
      const SizedBox(height: 10),
      if (active.isEmpty)
        const Text('목표를 설정하세요', style: TextStyle(
          fontSize: 13, color: OC.text3))
      else
        ...active.take(3).map((g) => _goalRow(g)),
    ]);
  }

  Widget _goalRow(OrderGoal g) {
    final done = g.milestones.where((m) => m.done).length;
    final total = g.milestones.length;
    final progress = total > 0 ? done / total : 0.0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(g.title, style: const TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: OC.text1),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          if (total > 0) ...[
            const SizedBox(height: 4),
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: progress, minHeight: 4,
                  backgroundColor: OC.bgSub,
                  valueColor: AlwaysStoppedAnimation(OC.accent.withValues(alpha: 0.7))))),
              const SizedBox(width: 8),
              Text('$done/$total', style: const TextStyle(
                fontSize: 10, fontWeight: FontWeight.w700, color: OC.text3)),
            ]),
          ],
        ])),
        if (g.dDayLabel.isNotEmpty) ...[
          const SizedBox(width: 10),
          Text(g.dDayLabel, style: TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700,
            color: (g.daysLeft ?? 999) <= 7 ? OC.amber : OC.text3)),
        ],
      ]),
    );
  }

  // ═══════════════════════════════════════════════════
  //  DISCIPLINE — 습관 체크 (간소화)
  // ═══════════════════════════════════════════════════
  Widget _disciplineSection() {
    final active = _data.habits
        .where((h) => !h.archived && h.settledAt == null)
        .toList();

    return _card(children: [
      _sectionLabel('DISCIPLINE', Icons.local_fire_department_rounded),
      const SizedBox(height: 10),
      if (active.isEmpty)
        const Text('습관을 추가하세요', style: TextStyle(
          fontSize: 13, color: OC.text3))
      else
        ...active.map((h) => _habitRow(h)),
    ]);
  }

  Widget _habitRow(OrderHabit h) {
    final done = h.isDoneOn(_today);
    final streak = h.currentStreak;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          h.toggleDate(_today);
          _update(() {});
        },
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 26, height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: done ? OC.accent : Colors.transparent,
              border: Border.all(
                color: done ? OC.accent : OC.text4, width: 2)),
            child: done
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Text(h.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Expanded(child: Text(h.title, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700,
            color: done ? OC.text3 : OC.text1,
            decoration: done ? TextDecoration.lineThrough : null))),
          if (streak > 0)
            Text('🔥 $streak', style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: OC.amber)),
        ]),
      ),
    );
  }

  // ═══════════════════════════════════════════════════
  //  OVERVIEW — 통계 요약 칩
  // ═══════════════════════════════════════════════════
  Widget _overviewRow() {
    final active = _data.habits.where((h) => !h.archived && !h.isSettled).toList();
    final avgStreak = active.isEmpty ? 0
        : (active.map((h) => h.currentStreak).fold(0, (a, b) => a + b) / active.length).round();
    final goalsDone = _data.goals.where((g) => g.isCompleted).length;

    return Row(children: [
      _statChip('$avgStreak일', '평균 스트릭', OC.amber, OC.amberBg),
      const SizedBox(width: 8),
      _statChip('$goalsDone/${_data.goals.length}', '목표 달성', OC.accent, OC.accentBg),
    ]);
  }

  Widget _statChip(String value, String label, Color c, Color bg) {
    return Expanded(child: Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.15))),
      child: Column(children: [
        Text(value, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w900, color: c)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(
          fontSize: 9, fontWeight: FontWeight.w600, color: OC.text3)),
      ]),
    ));
  }

  String _formatWon(int v) {
    if (v >= 10000) return '${(v / 10000).toStringAsFixed(1)}만';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}천';
    return '${v}원';
  }

  String _numberFormat(int v) {
    final s = v.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  // ═══════════════════════════════════════════════════
  //  EXPENSE ROW — 수험 / AI 분리 통계
  // ═══════════════════════════════════════════════════
  Widget _expenseRow() {
    final examTotal = _data.expenses
        .where((e) => e.category != 'AI')
        .fold(0, (sum, e) => sum + e.amount);
    final aiExpenses = _data.expenses.where((e) => e.category == 'AI').toList();
    final aiTotal = aiExpenses.fold(0, (sum, e) => sum + e.amount);
    final lastAi = aiExpenses.isNotEmpty
        ? (aiExpenses.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).first
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: OC.card, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OC.border.withValues(alpha: 0.5))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 수험 비용
        Row(children: [
          const Text('📚', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          const Text('수험', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: OC.text3)),
          const Spacer(),
          Text('₩${_numberFormat(examTotal)}', style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: OC.text2)),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: OC.border.withValues(alpha: 0.4))),
        // AI 비용
        Row(children: [
          const Text('🤖', style: TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          const Text('AI', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: OC.text3)),
          if (lastAi != null) ...[
            const SizedBox(width: 6),
            Text('(+₩${_numberFormat(lastAi.amount)})', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600,
              color: OC.accent.withValues(alpha: 0.5))),
          ],
          const Spacer(),
          Text('₩${_numberFormat(aiTotal)}', style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: OC.accent)),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _showAiCostSheet,
            child: Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                color: OC.accent, borderRadius: BorderRadius.circular(7)),
              child: const Icon(Icons.add_rounded, size: 16, color: Colors.white),
            ),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Divider(height: 1, color: OC.border.withValues(alpha: 0.4))),
        // 합계
        Row(children: [
          const Text('합계', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w800, color: OC.text3)),
          const Spacer(),
          Text('₩${_numberFormat(examTotal + aiTotal)}', style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w900, color: OC.text1)),
        ]),
      ]),
    );
  }

  void _showAiCostSheet() async {
    final amtCtrl = TextEditingController();
    HapticFeedback.selectionClick();
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(20, 20, 20,
          MediaQuery.of(ctx).viewInsets.bottom +
          MediaQuery.of(ctx).padding.bottom + 16),
        decoration: const BoxDecoration(
          color: OC.card,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          sheetHandle(),
          const SizedBox(height: 12),
          const Text('🤖 AI 비용 추가', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: OC.text1)),
          const SizedBox(height: 16),
          TextField(
            controller: amtCtrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '금액 (원)',
              prefixText: '₩ ',
              filled: true,
              fillColor: OC.bgSub,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: OC.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              final amt = int.tryParse(amtCtrl.text.replaceAll(',', '')) ?? 0;
              if (amt > 0) Navigator.pop(ctx, amt);
            },
            child: const Text('추가', style: TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
          )),
        ]),
      ),
    );
    // 시트 닫힌 뒤 처리 — setState 확실히 반영
    if (result != null && result > 0) {
      _data.expenses.add(StudyExpense(
        id: 'exp_${DateTime.now().millisecondsSinceEpoch}',
        title: 'AI 사용료',
        amount: result,
        category: 'AI',
      ));
      setState(() {});
      _save();
    }
  }

  // ═══════════════════════════════════════════════════
  //  QUICK ACCESS — 상세 관리 진입점
  // ═══════════════════════════════════════════════════
  Widget _quickAccess() {
    return Column(children: [
      Row(children: [
        _accessBtn('목표 · 습관', Icons.flag_rounded, OC.accent, () =>
          _pushDetail(OrderGoalsTab(data: _data, onUpdate: _update))),
        const SizedBox(width: 8),
        _accessBtn('회계장부', Icons.receipt_long_rounded, OC.success, () =>
          _pushDetail(OrderExpenseTab(data: _data, onUpdate: _update))),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _accessBtn('인생경로', Icons.route_rounded, const Color(0xFFf472b6), () =>
          Navigator.push(context, MaterialPageRoute(builder: (_) => const JourneyScreen()))),
        const SizedBox(width: 8),
        const Expanded(child: SizedBox()),
      ]),
    ]);
  }

  Widget _accessBtn(String label, IconData icon, Color c, VoidCallback onTap) {
    return Expanded(child: GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: OC.card, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: OC.border.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8, offset: const Offset(0, 2))]),
        child: Column(children: [
          Icon(icon, size: 22, color: c),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: OC.text2)),
        ]),
      ),
    ));
  }

  void _pushDetail(Widget tab) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: OC.bg,
        appBar: AppBar(
          backgroundColor: OC.bg, elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: OC.text1),
            onPressed: () => Navigator.pop(context)),
        ),
        body: SafeArea(child: tab),
      ),
    )).then((_) { if (mounted) setState(() {}); });
  }

  // ═══ Shared ═══
  Widget _card({required List<Widget> children}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: OC.card, borderRadius: BorderRadius.circular(16),
      border: Border.all(color: OC.border.withValues(alpha: 0.5)),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
        blurRadius: 8, offset: const Offset(0, 2))]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _sectionLabel(String text, IconData icon) => Row(children: [
    Icon(icon, size: 14, color: OC.accent),
    const SizedBox(width: 6),
    Text(text, style: const TextStyle(
      fontSize: 11, fontWeight: FontWeight.w800,
      color: OC.text3, letterSpacing: 1.5)),
  ]);
}
