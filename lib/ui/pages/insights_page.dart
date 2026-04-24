import 'package:flutter/material.dart';
import '../../theme/theme.dart';

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyPalette.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            const Text('인사이트', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
            const SizedBox(height: 4),
            const Text('주간·월간 패턴 (v3 구현 예정)',
                style: TextStyle(fontSize: 12, color: DailyPalette.ash)),
            const SizedBox(height: DailySpace.xxl),
            Container(
              padding: const EdgeInsets.all(DailySpace.xl),
              decoration: BoxDecoration(
                color: DailyPalette.card,
                borderRadius: BorderRadius.circular(DailySpace.radiusL),
                border: Border.all(color: DailyPalette.line),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('예정 항목', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
                  SizedBox(height: 10),
                  Text('• 주간 수면 평균·편차', style: TextStyle(fontSize: 13, color: DailyPalette.slate)),
                  Text('• 식사 빈도·시간대', style: TextStyle(fontSize: 13, color: DailyPalette.slate)),
                  Text('• Craving LoL 일별 그래프', style: TextStyle(fontSize: 13, color: DailyPalette.slate)),
                  Text('• Media Detox 달성률', style: TextStyle(fontSize: 13, color: DailyPalette.slate)),
                  Text('• Phase 타깃 vs 실제', style: TextStyle(fontSize: 13, color: DailyPalette.slate)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
