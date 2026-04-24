import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../models/order_models.dart';
import '../services/firebase_service.dart';
import 'order/order_theme.dart';
import 'order/order_today_tab.dart';
import 'order/order_life_tab.dart';
import 'order/order_stats_tab.dart';
import 'order/order_goals_tab.dart';
import 'journey_screen.dart';
import 'insight_screen.dart';

/// ═══════════════════════════════════════════════════════════
/// ARCHIVE — 비활성 모듈 보관함
/// Order 축소 후 격리된 읽기/정리 전용 진입점
/// ═══════════════════════════════════════════════════════════

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});
  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
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
      _savePending = true;
      return;
    }
    _saving = true;
    try {
      await _fb.updateField('orderData', _data.toMap());
    } catch (e) {
      debugPrint('[Archive] save error: $e');
    }
    _saving = false;
    if (_savePending) {
      _savePending = false;
      _save();
    }
  }

  void _update(VoidCallback fn) {
    fn();
    _safeSetState(() {});
    _save();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: OC.bg,
        appBar: AppBar(
          backgroundColor: OC.bg,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: OC.text1),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('아카이브', style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: OC.text1)),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: OC.accent))
            : SafeArea(child: RefreshIndicator(
                color: OC.accent,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    const SizedBox(height: 4),
                    const Text('비활성 모듈 보관함', style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: OC.text3)),
                    const SizedBox(height: 14),
                    _grid(),
                  ],
                ),
              )),
      ),
    );
  }

  Widget _grid() {
    final cards = <_ArchiveCard>[
      _ArchiveCard(
        label: '목표 · 습관',
        desc: '과거 기록 정리',
        icon: Icons.flag_rounded,
        color: OC.accent,
        onTap: () => _push(OrderGoalsTab(data: _data, onUpdate: _update)),
      ),
      _ArchiveCard(
        label: '오늘',
        desc: '일일 성취 요약',
        icon: Icons.today_rounded,
        color: OC.amber,
        onTap: () => _push(OrderTodayTab(
          data: _data, onUpdate: _update, onLoad: _load)),
      ),
      _ArchiveCard(
        label: '인생',
        desc: '로드맵 · 타임라인',
        icon: Icons.timeline_rounded,
        color: OC.marathon,
        onTap: () => _push(const OrderLifeTab()),
      ),
      _ArchiveCard(
        label: '통계',
        desc: '목표 · 습관 지표',
        icon: Icons.bar_chart_rounded,
        color: OC.success,
        onTap: () => _push(OrderStatsTab(data: _data)),
      ),
      _ArchiveCard(
        label: '인생경로',
        desc: 'Journey',
        icon: Icons.route_rounded,
        color: const Color(0xFFf472b6),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => const JourneyScreen()));
        },
      ),
      _ArchiveCard(
        label: '데일리 인사이트',
        desc: 'Insight',
        icon: Icons.lightbulb_outline_rounded,
        color: const Color(0xFFfbbf24),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => const InsightScreen()));
        },
      ),
    ];

    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 1.15,
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      children: cards.map(_buildCard).toList(),
    );
  }

  Widget _buildCard(_ArchiveCard c) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        c.onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: OC.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: OC.border.withValues(alpha: 0.5)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: c.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
              child: Icon(c.icon, size: 20, color: c.color),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.label, style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w800, color: OC.text1)),
                const SizedBox(height: 2),
                Text(c.desc, style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: OC.text3)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _push(Widget tab) {
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

class _ArchiveCard {
  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ArchiveCard({
    required this.label,
    required this.desc,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
