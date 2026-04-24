import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '_card.dart';

/// Phase Card — DAILY 버전 (수면 타깃 중심 · 공부 타깃은 STUDY)
/// 2026-04-25 ~ 2026-05-07 위상전진 v4 · 기상/취침/수면질 추적
class PhaseSleepCard extends StatelessWidget {
  const PhaseSleepCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final phase1Start = DateTime(2026, 4, 25);
    final phase2Start = DateTime(2026, 5, 2);
    final phase3Start = DateTime(2026, 5, 9);

    final String label, goal, wake, bed;
    if (now.isBefore(phase1Start)) {
      label = '준비일 · 내일 Phase 1 개시';
      goal = '오늘은 정비 · 수면 회복';
      wake = '—';
      bed = '—';
    } else if (now.isBefore(phase2Start)) {
      final d = now.difference(phase1Start).inDays + 1;
      label = 'Phase 1 · D$d/7';
      goal = '기상 정렬 + 광노출 + 수면 압력 복원';
      wake = '08:30';
      bed = '01:30';
    } else if (now.isBefore(phase3Start)) {
      final d = now.difference(phase2Start).inDays + 1;
      label = 'Phase 2 · D$d/7';
      goal = '수면 위상 정착';
      wake = '07:30';
      bed = '00:00';
    } else {
      label = '완성형';
      goal = '7시취침 10시기상 (사용자 완성형 목표)';
      wake = '07:00';
      bed = '23:00';
    }

    return DailyCard(
      title: label,
      icon: Icons.route_outlined,
      tint: DailyPalette.goldSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(goal, style: const TextStyle(fontSize: 12, color: DailyPalette.slate)),
          const SizedBox(height: 8),
          Row(
            children: [
              _pill('기상 $wake'),
              const SizedBox(width: 6),
              _pill('취침 $bed'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pill(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: DailyPalette.cream,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: DailyPalette.line),
        ),
        child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: DailyPalette.ink)),
      );
}
