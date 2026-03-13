import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../data/plan_data.dart';

/// Home widget — renders a real Flutter widget as image.
class WidgetRenderService {
  static final WidgetRenderService _instance = WidgetRenderService._();
  factory WidgetRenderService() => _instance;
  WidgetRenderService._();

  Future<void> updateWidget() async {
    try {
      final exams = StudyPlanData.ddays
          .where((d) => d.enabled && d.daysLeft >= 0)
          .toList()
        ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));

      final primary = exams.isNotEmpty
          ? exams.firstWhere((d) => d.primary, orElse: () => exams.first)
          : null;
      final others = exams.where((d) => d.id != primary?.id).take(2).toList();

      await HomeWidget.renderFlutterWidget(
        _DDayView(primary: primary, others: others),
        key: 'widget_image',
        logicalSize: const Size(360, 180),
        pixelRatio: 3.0,
      );
      await HomeWidget.updateWidget(
        name: 'StudyWidgetProvider',
        androidName: 'StudyWidgetProvider',
      );
      debugPrint('[Widget] rendered OK');
    } catch (e) {
      debugPrint('[Widget] error: $e');
    }
  }
}

// ═══════════════════════════════════════════
//  The actual Flutter widget rendered to image
// ═══════════════════════════════════════════

class _DDayView extends StatelessWidget {
  final PlanDDay? primary;
  final List<PlanDDay> others;
  const _DDayView({required this.primary, required this.others});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        width: 360,
        height: 180,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF8F6F1), Color(0xFFF0ECE3)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: primary == null
            ? const Center(child: Text('예정된 시험 없음',
                style: TextStyle(fontSize: 15, color: Color(0xFFADA79C))))
            : Row(
                children: [
                  // ── Left: Primary D-Day ──
                  Expanded(
                    flex: 5,
                    child: _primarySection(),
                  ),
                  // ── Divider ──
                  Container(
                    width: 1,
                    margin: const EdgeInsets.symmetric(vertical: 20),
                    color: const Color(0xFFE0DCD4),
                  ),
                  // ── Right: Other exams ──
                  Expanded(
                    flex: 4,
                    child: _othersSection(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _primarySection() {
    final p = primary!;
    final weeks = (p.daysLeft / 7).ceil();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // D-Day number
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              p.dDayLabel,
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w800,
                color: p.color,
                height: 1.0,
                letterSpacing: -1.5,
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Exam name
          Text(
            p.name,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2A2A2A),
              height: 1.2,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Date + weeks
          Text(
            '${_fmtDate(p.date)}  ·  ${weeks}\uC8FC',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xFF9A9590),
              height: 1.2,
            ),
          ),
          const Spacer(),
          // Progress bar
          _progressBar(p),
        ],
      ),
    );
  }

  Widget _progressBar(PlanDDay p) {
    final totalDays = 180;
    final elapsed = totalDays - p.daysLeft;
    final ratio = (elapsed / totalDays).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: SizedBox(
            height: 6,
            child: LinearProgressIndicator(
              value: ratio,
              backgroundColor: const Color(0xFFE5E1D8),
              valueColor: AlwaysStoppedAnimation(p.color.withValues(alpha: 0.6)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _othersSection() {
    if (others.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(
          child: Text('다른 시험 없음',
            style: TextStyle(fontSize: 12, color: Color(0xFFADA79C))),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '\uB2E4\uC74C \uC2DC\uD5D8',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0xFFADA79C),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          ...others.map((exam) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _examItem(exam),
          )),
        ],
      ),
    );
  }

  Widget _examItem(PlanDDay exam) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Color dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: exam.color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam.name,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A3A3A),
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _fmtDate(exam.date),
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFFADA79C),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          // D-Day badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: exam.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              exam.dDayLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: exam.color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDate(String dateStr) {
    final d = DateTime.parse(dateStr);
    return '${d.year}.${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';
  }
}
