import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '_card.dart';

/// 수면 위상 전진 14일 전체 조망 + Media Detox 4 Stage
/// 사용자 지시 "계획 조망 가능해야" (2026-04-25 00:20)
class SleepPlanOverview extends StatelessWidget {
  const SleepPlanOverview({super.key});

  @override
  Widget build(BuildContext context) {
    return DailyCard(
      title: '수면 위상 전진 · 14일',
      icon: Icons.timeline,
      tint: DailyPalette.goldSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PhaseRow(
            num: 1,
            range: 'D1~D7 · 04-25~05-01',
            goal: '기상 정렬 + 광노출 + 수면 압력 복원',
            wake: '08:30', bed: '01:30', study: '4h',
          ),
          _PhaseRow(
            num: 2,
            range: 'D8~D14 · 05-02~05-07',
            goal: '공부 밀도 증가 + 위상 정착',
            wake: '07:30', bed: '00:00', study: '6h',
          ),
          _PhaseRow(
            num: 0,  // 완성형
            range: 'D15+ · 05-08 이후',
            goal: '7시 취침 · 10시 기상 · 공부 8시간',
            wake: '07:00', bed: '23:00', study: '8h',
            isFinal: true,
          ),
          const SizedBox(height: 6),
          const Divider(color: DailyPalette.line, height: 1),
          const SizedBox(height: 10),
          const Text('Media Detox · 4 Stage',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: DailyPalette.ink)),
          const SizedBox(height: 6),
          _DetoxRow(num: 1, range: '04-25~05-07', goal: '숏폼·추천 OFF · 30분/일'),
          _DetoxRow(num: 2, range: '05-08~06-06', goal: '평일 완전 OFF · 주말 1h'),
          _DetoxRow(num: 3, range: '06-07~08-05', goal: 'YouTube 상시 OFF'),
          _DetoxRow(num: 4, range: '08-06+', goal: '수동 영상 시청 원천 제거'),
        ],
      ),
    );
  }
}

class _PhaseRow extends StatelessWidget {
  final int num;
  final String range, goal, wake, bed, study;
  final bool isFinal;
  const _PhaseRow({
    required this.num, required this.range, required this.goal,
    required this.wake, required this.bed, required this.study,
    this.isFinal = false,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final p1 = DateTime(2026, 4, 25);
    final p2 = DateTime(2026, 5, 2);
    final p3 = DateTime(2026, 5, 9);
    final active = isFinal
        ? !now.isBefore(p3)
        : num == 1
            ? !now.isBefore(p1) && now.isBefore(p2)
            : num == 2
                ? !now.isBefore(p2) && now.isBefore(p3)
                : false;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? DailyPalette.cream : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: active ? Border.all(color: DailyPalette.gold, width: 1) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                isFinal ? '완성형' : 'Phase $num',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: active ? DailyPalette.primary : DailyPalette.slate,
                ),
              ),
              const SizedBox(width: 6),
              Text(range, style: const TextStyle(fontSize: 10, color: DailyPalette.ash)),
              if (active) ...[
                const SizedBox(width: 4),
                const Icon(Icons.circle, size: 6, color: DailyPalette.primary),
              ],
            ],
          ),
          const SizedBox(height: 2),
          Text(goal, style: const TextStyle(fontSize: 11, color: DailyPalette.slate)),
          const SizedBox(height: 2),
          Text('기상 $wake · 취침 $bed · 공부 $study',
              style: const TextStyle(fontSize: 10, color: DailyPalette.ash)),
        ],
      ),
    );
  }
}

class _DetoxRow extends StatelessWidget {
  final int num;
  final String range, goal;
  const _DetoxRow({required this.num, required this.range, required this.goal});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final bounds = [
      (DateTime(2026, 4, 25), DateTime(2026, 5, 8)),
      (DateTime(2026, 5, 8), DateTime(2026, 6, 7)),
      (DateTime(2026, 6, 7), DateTime(2026, 8, 6)),
      (DateTime(2026, 8, 6), DateTime(2099, 1, 1)),
    ];
    final b = bounds[num - 1];
    final active = !now.isBefore(b.$1) && now.isBefore(b.$2);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 60,
            child: Row(
              children: [
                Text('Stage $num',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: active ? DailyPalette.primary : DailyPalette.slate,
                    )),
                if (active) ...[
                  const SizedBox(width: 3),
                  const Icon(Icons.circle, size: 6, color: DailyPalette.primary),
                ],
              ],
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(range, style: const TextStyle(fontSize: 10, color: DailyPalette.ash)),
          ),
          Expanded(
            child: Text(goal, style: const TextStyle(fontSize: 11, color: DailyPalette.slate)),
          ),
        ],
      ),
    );
  }
}
