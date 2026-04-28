// 수면 위상 전진 — Phase 1·2·완성형 단계 명확 표시. Media Detox = 사용자 17:24 삭제 지시.
// 사용자 지시 (2026-04-28 17:24): "Phase 설명 잘 + 진행 단계 잘 알게".
import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '_card.dart';

class SleepPlanOverview extends StatelessWidget {
  const SleepPlanOverview({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final p1Start = DateTime(2026, 4, 25);
    final p2Start = DateTime(2026, 5, 2);
    final p3Start = DateTime(2026, 5, 9);

    int currentPhase;
    int totalDays;
    int currentDay;
    if (now.isBefore(p2Start)) {
      currentPhase = 1;
      totalDays = 7;
      currentDay = now.difference(p1Start).inDays + 1;
    } else if (now.isBefore(p3Start)) {
      currentPhase = 2;
      totalDays = 7;
      currentDay = now.difference(p2Start).inDays + 1;
    } else {
      currentPhase = 3;
      totalDays = 1;
      currentDay = 1;
    }

    return DailyCard(
      title: '수면 위상 전진 14일',
      icon: Icons.timeline,
      tint: DailyPalette.goldSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 현재 Phase 강조 헤더
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: DailyPalette.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DailyPalette.primary, width: 1.2),
            ),
            child: Row(
              children: [
                Icon(Icons.flag_circle, size: 22, color: DailyPalette.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentPhase == 3
                            ? '완성형 단계 진행 중'
                            : 'Phase $currentPhase · Day $currentDay/$totalDays 진행 중',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: DailyPalette.primary),
                      ),
                      Text(
                        currentPhase == 1
                            ? '기상 정렬 + 광노출 + 수면 압력 복원'
                            : currentPhase == 2
                                ? '공부 밀도 증가 + 위상 정착'
                                : '7시 취침 · 10시 기상 · 공부 8시간 정착',
                        style: const TextStyle(fontSize: 11, color: DailyPalette.slate),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 진행 bar
          if (currentPhase < 3)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (currentDay / totalDays).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: DailyPalette.line,
                valueColor: const AlwaysStoppedAnimation<Color>(DailyPalette.primary),
              ),
            ),
          const SizedBox(height: 12),

          // 3 Phase 단계 list
          _PhaseRow(
            num: 1, active: currentPhase == 1,
            range: 'D1~D7 · 04-25 → 05-01',
            goal: '기상 정렬 + 광노출 + 수면 압력 복원',
            why: '늦은 취침 패턴을 깨고 일관된 기상으로 부터 출발',
            wake: '08:30', bed: '01:30', study: '4h+',
          ),
          _PhaseRow(
            num: 2, active: currentPhase == 2,
            range: 'D8~D14 · 05-02 → 05-08',
            goal: '공부 밀도 증가 + 위상 정착',
            why: '몸이 새 리듬에 적응한 후 본격 공부 시간 증가',
            wake: '07:30', bed: '00:00', study: '6h',
          ),
          _PhaseRow(
            num: 3, active: currentPhase == 3, isFinal: true,
            range: 'D15+ · 05-09 ~ 시험 직전',
            goal: '완성형 — 7시 취침 · 10시 기상 · 공부 8시간',
            why: '시험 본번 컨디션 그대로 유지',
            wake: '07:00', bed: '23:00', study: '8h',
          ),
        ],
      ),
    );
  }
}

class _PhaseRow extends StatelessWidget {
  final int num;
  final bool active, isFinal;
  final String range, goal, why, wake, bed, study;
  const _PhaseRow({
    required this.num, required this.active, this.isFinal = false,
    required this.range, required this.goal, required this.why,
    required this.wake, required this.bed, required this.study,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? DailyPalette.primary : DailyPalette.slate;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? DailyPalette.cream : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? DailyPalette.gold : DailyPalette.line, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isFinal ? '완성형' : 'Phase $num',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
              ),
              const SizedBox(width: 6),
              Text(range, style: const TextStyle(fontSize: 11, color: DailyPalette.ash)),
              if (active) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: DailyPalette.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('진행 중',
                      style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(goal, style: const TextStyle(fontSize: 12, color: DailyPalette.ink, fontWeight: FontWeight.w600)),
          Text(why, style: const TextStyle(fontSize: 11, color: DailyPalette.ash, height: 1.4)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              _chip('🌅', '기상 $wake'),
              _chip('🛏️', '취침 $bed'),
              _chip('📖', '공부 $study'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(String emoji, String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: DailyPalette.paper,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: DailyPalette.line),
        ),
        child: Text('$emoji  $text',
            style: const TextStyle(fontSize: 11, color: DailyPalette.ink, fontWeight: FontWeight.w600)),
      );
}
