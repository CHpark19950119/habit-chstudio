import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/theme.dart';
import '../widgets/routine_checklist.dart';
import '../widgets/phase_goal_card.dart';
import '../widgets/today_timeline.dart';

/// DAILY 오늘 탭 — 사용자 지시 (2026-04-28 16:58) 간결화.
/// 그날 일정 (timeline) + 그날 순서 (Phase routine) 만 표시.
/// 구체 카드 (Sleep/Detox/Craving/Meals/Toggle/LifeLogsSummary 등) = 계획 탭으로 이관.
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
              // Phase + 시험 D-day 한 줄 badge
              PhaseGoalCard(),
              SizedBox(height: DailySpace.md),
              // 오늘의 순서 (Phase 기반 routine checklist)
              RoutineChecklist(),
              SizedBox(height: DailySpace.md),
              // 오늘 일정 (시간순 timeline)
              TodayTimeline(),
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
