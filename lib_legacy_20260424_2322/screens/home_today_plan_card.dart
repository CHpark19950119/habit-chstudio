import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 오늘의 계획 카드
/// 데이터: assets/plans/today_plan_20260424.json
/// 권위본: HB 세션 대화 (plan v4 + Media Detox + D-85 외영 + 과목 배분)
/// ═══════════════════════════════════════════════════
class HomeTodayPlanCard extends StatefulWidget {
  const HomeTodayPlanCard({super.key});

  @override
  State<HomeTodayPlanCard> createState() => _HomeTodayPlanCardState();
}

class _HomeTodayPlanCardState extends State<HomeTodayPlanCard> {
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await rootBundle.loadString('assets/plans/today_plan_20260424.json');
      setState(() => _data = json.decode(raw) as Map<String, dynamic>);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_data == null) return const SizedBox.shrink();
    final exam = _data!['exam'] as Map<String, dynamic>? ?? {};
    final plan = _data!['phaseShiftPlan'] as Map<String, dynamic>? ?? {};
    final media = _data!['mediaDetox'] as Map<String, dynamic>? ?? {};
    final alloc = (_data!['subjectAllocation'] as Map<String, dynamic>?)?['weights']
            as Map<String, dynamic>? ??
        {};
    final blocks = (_data!['todayBlocks'] as List?) ?? const [];
    final diet = _data!['diet'] as Map<String, dynamic>? ?? {};
    final craving = _data!['cravingManagement'] as Map<String, dynamic>? ?? {};

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerRow(exam),
          const SizedBox(height: 12),
          _phaseRow(plan),
          const SizedBox(height: 12),
          _mediaRow(media),
          const Divider(height: 22, color: Color(0xFF475569)),
          _sectionLabel('과목 배분 (실력축)'),
          const SizedBox(height: 6),
          ...alloc.entries.map((e) => _subjectRow(e.key, e.value as Map<String, dynamic>)),
          const SizedBox(height: 12),
          _sectionLabel('오늘 블록'),
          const SizedBox(height: 6),
          ...blocks.whereType<Map>().map((b) => _blockRow(Map<String, dynamic>.from(b))),
          const SizedBox(height: 12),
          _sectionLabel('식단·음료'),
          const SizedBox(height: 6),
          _infoRow(
              '아침',
              diet['breakfast']?.toString() ?? '',
              diet['note']?.toString()),
          _infoRow('음료', diet['drink']?.toString() ?? '', null),
          const SizedBox(height: 12),
          _sectionLabel('Craving 관리'),
          const SizedBox(height: 6),
          _infoRow('LoL',
              (craving['lol'] as Map?)?['status']?.toString() ?? '',
              (craving['lol'] as Map?)?['note']?.toString()),
          _infoRow('Porn',
              (craving['porn'] as Map?)?['stage']?.toString() ?? '',
              (craving['porn'] as Map?)?['note']?.toString()),
        ],
      ),
    );
  }

  Widget _headerRow(Map<String, dynamic> exam) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            exam['dDay']?.toString() ?? 'D-?',
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${exam['name'] ?? ''} · ${exam['date'] ?? ''}',
            style: const TextStyle(
                color: Color(0xFFF1F5F9), fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _phaseRow(Map<String, dynamic> plan) {
    final p1 = plan['phase1'] as Map<String, dynamic>? ?? {};
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule, size: 14, color: Color(0xFF60A5FA)),
              const SizedBox(width: 6),
              Text(
                '${plan['name'] ?? ''} · ${plan['currentDay'] ?? ''} (내일 D1 시작)',
                style: const TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Phase 1 (${p1['range'] ?? ''}): ${p1['goal'] ?? ''}',
            style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _tag('기상 ${p1['wake_target'] ?? '—'}', const Color(0xFFFBBF24)),
              const SizedBox(width: 6),
              _tag('취침 ${p1['bed_target'] ?? '—'}', const Color(0xFF8B5CF6)),
              const SizedBox(width: 6),
              _tag('공부 ${p1['study_target_hours'] ?? 0}h', const Color(0xFF34D399)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mediaRow(Map<String, dynamic> media) {
    final stages = (media['stages'] as List?) ?? const [];
    Map<String, dynamic>? stage1;
    if (stages.isNotEmpty) stage1 = Map<String, dynamic>.from(stages[0] as Map);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.play_disabled, size: 14, color: Color(0xFFF87171)),
              const SizedBox(width: 6),
              Text(
                'Media Detox · Stage 1 D-1 (내일 개시)',
                style: const TextStyle(
                    color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          if (stage1 != null) ...[
            const SizedBox(height: 4),
            Text(
              '${stage1['start']} ~ ${stage1['end']} · ${stage1['goal']}',
              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(String t) => Text(t,
      style: const TextStyle(
          color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5));

  Widget _subjectRow(String name, Map<String, dynamic> w) {
    final priority = w['priority']?.toString() ?? '';
    final hours = w['hours_per_day']?.toString() ?? '';
    final style = w['style']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Text('#$priority',
                style: const TextStyle(color: Color(0xFF60A5FA), fontSize: 10, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 40,
            child: Text(name,
                style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 12, fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            width: 44,
            child: Text('${hours}h',
                style: const TextStyle(color: Color(0xFF34D399), fontSize: 11, fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text(style,
                style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _blockRow(Map<String, dynamic> b) {
    final status = b['status']?.toString() ?? '';
    Color statusColor;
    String statusIcon;
    switch (status) {
      case 'done':
        statusColor = const Color(0xFF34D399);
        statusIcon = '✓';
        break;
      case 'in_progress':
        statusColor = const Color(0xFFFBBF24);
        statusIcon = '▶';
        break;
      default:
        statusColor = const Color(0xFF94A3B8);
        statusIcon = '◦';
    }
    final note = b['note']?.toString();
    final subject = b['subject']?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 18,
              child: Text(statusIcon,
                  style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold))),
          SizedBox(
            width: 88,
            child: Text(b['time']?.toString() ?? '',
                style: const TextStyle(
                    color: Color(0xFFE2E8F0), fontSize: 11, fontFamily: 'monospace')),
          ),
          Expanded(
            child: Text(
              subject != null ? '$subject${note != null ? " · $note" : ""}' : (note ?? ''),
              style: const TextStyle(color: Color(0xFFF1F5F9), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, String? note) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
              width: 48,
              child: Text(label,
                  style: const TextStyle(
                      color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w600))),
          Expanded(
            child: Text(
              '$value${note != null && note.isNotEmpty ? " · $note" : ""}',
              style: const TextStyle(color: Color(0xFFE2E8F0), fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
