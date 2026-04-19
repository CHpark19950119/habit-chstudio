import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../models/order_models.dart';
import '../../services/firebase_service.dart';
import '../archive_screen.dart';
import 'order_theme.dart';
import 'order_expense_tab.dart';

/// ═══════════════════════════════════════════════════════════
/// COMPASS v6.0 — Expense-Only Cockpit
/// Header · Expense · Quick Access (회계장부 / 아카이브)
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
    return Row(children: [
      Container(width: 10, height: 10,
        decoration: const BoxDecoration(
          color: OC.accent, shape: BoxShape.circle)),
      const SizedBox(width: 10),
      const Text('COMPASS', style: TextStyle(
        fontSize: 20, fontWeight: FontWeight.w900,
        color: OC.text1, letterSpacing: 2)),
    ]);
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
      _safeSetState(() {});
      _save();
    }
  }

  // ═══════════════════════════════════════════════════
  //  QUICK ACCESS — 회계장부 / 아카이브
  // ═══════════════════════════════════════════════════
  Widget _quickAccess() {
    return Row(children: [
      _accessBtn('회계장부', Icons.receipt_long_rounded, OC.success, () =>
        _pushDetail(OrderExpenseTab(data: _data, onUpdate: _update))),
      const SizedBox(width: 8),
      _accessBtn('아카이브', Icons.inventory_2_rounded, OC.accent, () {
        Navigator.push(context, MaterialPageRoute(
          builder: (_) => const ArchiveScreen()));
      }),
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
}
