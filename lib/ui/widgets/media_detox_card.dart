import 'package:flutter/material.dart';
import '../../theme/theme.dart';
import '_card.dart';

class MediaDetoxCard extends StatelessWidget {
  const MediaDetoxCard({super.key});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final stage1Start = DateTime(2026, 4, 25);
    final stage2Start = DateTime(2026, 5, 8);
    final stage3Start = DateTime(2026, 6, 7);
    final stage4Start = DateTime(2026, 8, 6);

    String stage, goal;
    if (now.isBefore(stage1Start)) {
      stage = 'Stage 1 · D-1 개시 예정';
      goal = '숏폼·추천 피드 OFF · 30분/일';
    } else if (now.isBefore(stage2Start)) {
      stage = 'Stage 1 진행 중';
      goal = '숏폼 OFF · 30분/일';
    } else if (now.isBefore(stage3Start)) {
      stage = 'Stage 2';
      goal = 'YouTube 평일 OFF · 주말 1h';
    } else if (now.isBefore(stage4Start)) {
      stage = 'Stage 3';
      goal = 'YouTube 상시 OFF';
    } else {
      stage = 'Stage 4';
      goal = '수동 영상 시청 원천 제거';
    }

    return DailyCard(
      title: 'Media Detox · $stage',
      icon: Icons.smart_display_outlined,
      tint: DailyPalette.primarySurface,
      child: Text(goal, style: const TextStyle(fontSize: 12, color: DailyPalette.slate)),
    );
  }
}
