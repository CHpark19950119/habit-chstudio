import 'package:flutter/material.dart';
import '../models/life_logs_models.dart';
import '../services/life_logs_service.dart';

/// ═══════════════════════════════════════════════════
/// HOME — LIFE LOGS 패널 (HB 기입 결과 조회)
/// 권위본: memory/project_app_integration.md
/// ═══════════════════════════════════════════════════
class HomeLifeLogsPanel extends StatelessWidget {
  final String yyyymmdd;

  const HomeLifeLogsPanel({super.key, required this.yyyymmdd});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<LifeLog>(
      stream: LifeLogsService.streamByDate(yyyymmdd),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final log = snap.data!;
        if (log.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'HB 기록 없음 · $yyyymmdd',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          );
        }
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_note, size: 18, color: Color(0xFF475569)),
                  const SizedBox(width: 6),
                  Text(
                    'HB 기록 — $yyyymmdd',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (log.wake != null) _row('기상', log.wake!.time, log.wake!.note),
              if (log.sleep != null) _row('취침', log.sleep!.time, log.sleep!.note),
              if (log.meals.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...log.meals.map((m) => _row('식사', m.time, '${m.menu}${m.note != null ? ' · ${m.note}' : ''}')),
              ],
              if (log.bowel.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...log.bowel.map((b) => _row('배변', b.time, b.status)),
              ],
              if (log.study.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...log.study.map((s) => _row(
                      '공부',
                      s.time,
                      '${s.subject}${s.problems != null ? ' · ${s.problems}문제' : ''}${s.note != null ? ' · ${s.note}' : ''}',
                    )),
                Padding(
                  padding: const EdgeInsets.only(top: 4, left: 48),
                  child: Text(
                    '총 ${log.totalStudyProblems}문제',
                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              if (log.outing.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...log.outing.map((e) => _row('외출', e.time, e.note)),
              ],
              if (log.hydration.isNotEmpty) ...[
                const SizedBox(height: 6),
                ...log.hydration.map((e) => _row('수분', e.time, e.note)),
              ],
              if (_hasPsych(log.psych)) ...[
                const Divider(height: 18, color: Color(0xFFE2E8F0)),
                _psychBlock(log.psych),
              ],
            ],
          ),
        );
      },
    );
  }

  bool _hasPsych(LifeLogPsych p) =>
      p.masturbation.isNotEmpty ||
      p.porn.isNotEmpty ||
      p.cravingLol != null ||
      (p.mood != null && p.mood!.isNotEmpty);

  Widget _row(String label, String time, String? note) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 48,
            child: Text(
              time,
              style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Text(
              note ?? '',
              style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _psychBlock(LifeLogPsych p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '심리 · 민감 기록 (코드만)',
          style: TextStyle(fontSize: 11, color: Colors.grey[600], fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        if (p.cravingLol != null) _row('크레이빙', 'LoL', '${p.cravingLol}/10'),
        if (p.mood != null && p.mood!.isNotEmpty) _row('기분', '', p.mood),
        ...p.masturbation.map((r) => _row('M', r.time, r.code)),
        ...p.porn.map((r) => _row('P', r.time, r.code)),
      ],
    );
  }
}
