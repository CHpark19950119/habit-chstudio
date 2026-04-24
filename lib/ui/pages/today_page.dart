import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/theme.dart';
import '../widgets/routine_checklist.dart';
import '../widgets/sleep_card.dart';
import '../widgets/phase_sleep_card.dart';
import '../widgets/sleep_plan_overview.dart';
import '../widgets/media_detox_card.dart';
import '../widgets/craving_card.dart';

/// DAILY 오늘 탭 — TODO 체크리스트 중심
/// 상단: 날짜 + 오늘의 순서 (checkable)
/// 하단: 수면·Phase·Detox·Craving 요약 (소형)
class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyPalette.paper,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => await Future.delayed(const Duration(milliseconds: 300)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: const [
              _Header(),
              SizedBox(height: DailySpace.lg),
              // ★ 핵심 — 오늘의 순서 체크리스트
              RoutineChecklist(),
              SizedBox(height: DailySpace.lg),
              // 상황 요약 (작게)
              SleepCard(),
              SizedBox(height: DailySpace.md),
              PhaseSleepCard(),
              SizedBox(height: DailySpace.md),
              SleepPlanOverview(),
              SizedBox(height: DailySpace.md),
              MediaDetoxCard(),
              SizedBox(height: DailySpace.md),
              CravingCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final date = DateFormat('M월 d일 EEEE', 'ko').format(now);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(date, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 4),
        const Text('오늘', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
      ],
    );
  }
}
