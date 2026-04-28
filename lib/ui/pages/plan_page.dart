import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '../widgets/phase_goal_card.dart';
import '../widgets/sleep_card.dart';
import '../widgets/phase_sleep_card.dart';
import '../widgets/sleep_plan_overview.dart';
import '../widgets/media_detox_card.dart';
import '../widgets/craving_card.dart';
import '../widgets/meals_card.dart';
import '../widgets/toggle_status_card.dart';
import '../widgets/life_logs_summary.dart';

/// 계획 탭 — 1차/2차 D-day · 수면 위상 · Detox · 토글 · 누적 통계
/// 사용자 지시 2026-04-28 16:58 "홈 간결화 + 구체 카드 → 계획 탭 이관"
class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyPalette.paper,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            const _Header(),
            const SizedBox(height: DailySpace.lg),
            // 시험 D-day (1차·2차·3차)
            const _ExamDDayCard(),
            const SizedBox(height: DailySpace.md),
            // Phase + 목표 (홈에서 이관)
            const PhaseGoalCard(),
            const SizedBox(height: DailySpace.md),
            // 수면 위상 14일 + Phase 1·2 plan
            const _PhaseCard(),
            const SizedBox(height: DailySpace.md),
            const SleepCard(),
            const SizedBox(height: DailySpace.md),
            const PhaseSleepCard(),
            const SizedBox(height: DailySpace.md),
            const SleepPlanOverview(),
            const SizedBox(height: DailySpace.md),
            // Detox · 갈망
            const MediaDetoxCard(),
            const SizedBox(height: DailySpace.md),
            const CravingCard(),
            const SizedBox(height: DailySpace.md),
            // 식사 · 생활 토글
            const MealsCard(),
            const SizedBox(height: DailySpace.md),
            const ToggleStatusCard(),
            const SizedBox(height: DailySpace.md),
            const LifeLogsSummary(),
            const SizedBox(height: DailySpace.md),
            // 누적 통계
            const _Routine14(),
            const SizedBox(height: DailySpace.md),
            const _SleepPhase14(),
            const SizedBox(height: DailySpace.md),
            const _DomainNote(),
          ],
        ),
      ),
    );
  }
}

class _ExamDDayCard extends StatelessWidget {
  const _ExamDDayCard();
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final exam1 = DateTime(2026, 7, 18); // PSAT
    final exam2 = DateTime(2026, 9, 19); // 전공 (헌법·국제법·국제정치학)
    final exam3 = DateTime(2026, 11, 23); // 면접 시작
    final d1 = exam1.difference(DateTime(today.year, today.month, today.day)).inDays;
    final d2 = exam2.difference(DateTime(today.year, today.month, today.day)).inDays;
    final d3 = exam3.difference(DateTime(today.year, today.month, today.day)).inDays;
    return Container(
      padding: const EdgeInsets.all(DailySpace.lg),
      decoration: BoxDecoration(
        color: DailyPalette.card,
        borderRadius: BorderRadius.circular(DailySpace.radiusL),
        border: Border.all(color: DailyPalette.gold, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('7급 외무영사직 시험', style: TextStyle(fontSize: 13, color: DailyPalette.slate, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _row('1차 PSAT', '2026-07-18 (토)', '언어논리·자료해석·상황판단', d1, DailyPalette.error),
          const SizedBox(height: 8),
          _row('2차 전공', '2026-09-19 (토)', '헌법·국제법·국제정치학', d2, DailyPalette.gold),
          const SizedBox(height: 8),
          _row('3차 면접', '2026-11-23~26', '자기기술서·토론·PT', d3, DailyPalette.primary),
        ],
      ),
    );
  }

  Widget _row(String label, String date, String subjects, int dDay, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
          child: Text('D-$dDay', style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$label · $date', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
              Text(subjects, style: const TextStyle(fontSize: 10, color: DailyPalette.ash)),
            ],
          ),
        ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('계획', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
        SizedBox(height: 4),
        Text('시험 D-day · 수면 위상 · Detox · 누적 통계', style: TextStyle(fontSize: 12, color: DailyPalette.ash)),
      ],
    );
  }
}

class _DomainNote extends StatelessWidget {
  const _DomainNote();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(DailySpace.md),
      decoration: BoxDecoration(
        color: DailyPalette.goldSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: DailyPalette.gold, width: 0.8),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: DailyPalette.gold),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '공부 진도는 STUDY 앱에서 확인. 데일리 앱은 일상(수면·루틴·식사) 만 다룬다.',
              style: TextStyle(fontSize: 11, color: DailyPalette.slate, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _DDayCard extends StatelessWidget {
  const _DDayCard();
  @override
  Widget build(BuildContext context) {
    final exam = DateTime(2026, 7, 18);
    final today = DateTime.now();
    final dday = exam.difference(DateTime(today.year, today.month, today.day)).inDays;
    return Container(
      padding: const EdgeInsets.all(DailySpace.lg),
      decoration: BoxDecoration(
        color: DailyPalette.card,
        borderRadius: BorderRadius.circular(DailySpace.radiusL),
        border: Border.all(color: DailyPalette.gold, width: 1.2),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: DailyPalette.goldSurface,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.flag, color: DailyPalette.gold, size: 28),
          ),
          const SizedBox(width: DailySpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('7급 외무영사직 1차 PSAT', style: TextStyle(fontSize: 13, color: DailyPalette.slate, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('D-$dday  ·  2026-07-18 (토)',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: DailyPalette.ink)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard();
  @override
  Widget build(BuildContext context) {
    final start = DateTime(2026, 4, 25);
    final today = DateTime.now();
    final day = today.difference(DateTime(start.year, start.month, start.day)).inDays + 1;
    final phaseName = day <= 7 ? 'Phase 1 (위상 전진)' : day <= 14 ? 'Phase 2 (밀도 증가)' : '완성형 (8h/일)';
    final progress = day <= 14 ? day / 14.0 : 1.0;
    return Container(
      padding: const EdgeInsets.all(DailySpace.lg),
      decoration: BoxDecoration(
        color: DailyPalette.card,
        borderRadius: BorderRadius.circular(DailySpace.radiusL),
        border: Border.all(color: DailyPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.trending_up, size: 18, color: DailyPalette.primary),
              const SizedBox(width: 6),
              const Text('수면 위상 전진 14일', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
              const Spacer(),
              Text('Day $day / 14',
                  style: const TextStyle(fontSize: 11, color: DailyPalette.ash, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          Text(phaseName, style: const TextStyle(fontSize: 13, color: DailyPalette.slate, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: DailyPalette.line,
              valueColor: const AlwaysStoppedAnimation<Color>(DailyPalette.primary),
            ),
          ),
        ],
      ),
    );
  }
}

class _Week7Study extends StatelessWidget {
  const _Week7Study();
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 6));
    final startKey = DateFormat('yyyy-MM-dd').format(start);
    final endKey = DateFormat('yyyy-MM-dd').format(today);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(kUid).collection('life_logs')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
          .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
          .snapshots(),
      builder: (ctx, snap) {
        final byDay = <String, int>{};
        for (int i = 0; i < 7; i++) {
          final d = start.add(Duration(days: i));
          byDay[DateFormat('yyyy-MM-dd').format(d)] = 0;
        }
        for (final d in snap.data?.docs ?? []) {
          final m = d.data();
          final list = m['study'];
          if (list is List) {
            int sum = 0;
            for (final s in list.whereType<Map>()) {
              if (s['category'] == 'infra_setup') continue;
              final v = s['duration_min'];
              if (v is num) sum += v.toInt();
            }
            byDay[d.id] = sum;
          }
        }
        final maxMin = byDay.values.fold<int>(0, (a, b) => a > b ? a : b);
        final total = byDay.values.fold<int>(0, (a, b) => a + b);
        return Container(
          padding: const EdgeInsets.all(DailySpace.lg),
          decoration: BoxDecoration(
            color: DailyPalette.card,
            borderRadius: BorderRadius.circular(DailySpace.radiusL),
            border: Border.all(color: DailyPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.bar_chart, size: 18, color: DailyPalette.primary),
                  const SizedBox(width: 6),
                  const Text('최근 7일 공부 시간', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
                  const Spacer(),
                  Text('총 ${(total / 60).toStringAsFixed(1)}h',
                      style: const TextStyle(fontSize: 11, color: DailyPalette.ash, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: DailySpace.md),
              SizedBox(
                height: 90,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(7, (i) {
                    final d = start.add(Duration(days: i));
                    final key = DateFormat('yyyy-MM-dd').format(d);
                    final m = byDay[key] ?? 0;
                    final h = maxMin == 0 ? 0.0 : (m / maxMin * 70).clamp(0.0, 70.0);
                    final isToday = i == 6;
                    return Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(m > 0 ? '${(m / 60).toStringAsFixed(1)}h' : '',
                              style: const TextStyle(fontSize: 9, color: DailyPalette.ash)),
                          const SizedBox(height: 2),
                          Container(
                            height: h,
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            decoration: BoxDecoration(
                              color: isToday ? DailyPalette.primary : DailyPalette.gold,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(DateFormat('E', 'ko').format(d).substring(0, 1),
                              style: TextStyle(
                                fontSize: 10,
                                color: isToday ? DailyPalette.primary : DailyPalette.ash,
                                fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                              )),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Routine14 extends StatelessWidget {
  const _Routine14();
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 13));
    final startKey = DateFormat('yyyy-MM-dd').format(start);
    final endKey = DateFormat('yyyy-MM-dd').format(today);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(kUid).collection('routine')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
          .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
          .snapshots(),
      builder: (ctx, snap) {
        final byDay = <String, double>{};
        for (int i = 0; i < 14; i++) {
          final d = start.add(Duration(days: i));
          byDay[DateFormat('yyyy-MM-dd').format(d)] = 0.0;
        }
        for (final d in snap.data?.docs ?? []) {
          final m = d.data();
          final steps = m['steps'];
          if (steps is List && steps.isNotEmpty) {
            final done = steps.whereType<Map>().where((s) => s['done'] == true).length;
            byDay[d.id] = done / steps.length;
          }
        }
        final avg = byDay.values.fold<double>(0, (a, b) => a + b) / byDay.length;
        return Container(
          padding: const EdgeInsets.all(DailySpace.lg),
          decoration: BoxDecoration(
            color: DailyPalette.card,
            borderRadius: BorderRadius.circular(DailySpace.radiusL),
            border: Border.all(color: DailyPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.checklist, size: 18, color: DailyPalette.primary),
                  const SizedBox(width: 6),
                  const Text('루틴 달성률 14일', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
                  const Spacer(),
                  Text('평균 ${(avg * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 11, color: DailyPalette.ash, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: DailySpace.md),
              SizedBox(
                height: 24,
                child: Row(
                  children: List.generate(14, (i) {
                    final d = start.add(Duration(days: i));
                    final key = DateFormat('yyyy-MM-dd').format(d);
                    final r = byDay[key] ?? 0.0;
                    Color c;
                    if (r >= 1.0) {
                      c = DailyPalette.success;
                    } else if (r >= 0.6) {
                      c = DailyPalette.gold;
                    } else if (r > 0.0) {
                      c = DailyPalette.gold.withValues(alpha: 0.4);
                    } else {
                      c = DailyPalette.line;
                    }
                    return Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          color: c,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(DateFormat('M/d').format(start), style: const TextStyle(fontSize: 9, color: DailyPalette.ash)),
                  Text(DateFormat('M/d').format(today), style: const TextStyle(fontSize: 9, color: DailyPalette.ash)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SleepPhase14 extends StatelessWidget {
  const _SleepPhase14();
  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 13));
    final startKey = DateFormat('yyyy-MM-dd').format(start);
    final endKey = DateFormat('yyyy-MM-dd').format(today);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(kUid).collection('life_logs')
          .where(FieldPath.documentId, isGreaterThanOrEqualTo: startKey)
          .where(FieldPath.documentId, isLessThanOrEqualTo: endKey)
          .snapshots(),
      builder: (ctx, snap) {
        final wake = <String, String>{}, sleep = <String, String>{};
        for (final d in snap.data?.docs ?? []) {
          final m = d.data();
          if (m['wake'] is Map && m['wake']['time'] is String) wake[d.id] = m['wake']['time'];
          if (m['sleep'] is Map && m['sleep']['time'] is String) sleep[d.id] = m['sleep']['time'];
        }
        return Container(
          padding: const EdgeInsets.all(DailySpace.lg),
          decoration: BoxDecoration(
            color: DailyPalette.card,
            borderRadius: BorderRadius.circular(DailySpace.radiusL),
            border: Border.all(color: DailyPalette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.bedtime, size: 18, color: DailyPalette.primary),
                  SizedBox(width: 6),
                  Text('수면 위상 14일', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
                ],
              ),
              const SizedBox(height: DailySpace.md),
              ...List.generate(14, (i) {
                final d = start.add(Duration(days: i));
                final key = DateFormat('yyyy-MM-dd').format(d);
                final w = wake[key] ?? '—';
                final s = sleep[key] ?? '—';
                final isToday = i == 13;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 50,
                        child: Text(DateFormat('M/d EEE', 'ko').format(d),
                            style: TextStyle(
                              fontSize: 10,
                              color: isToday ? DailyPalette.primary : DailyPalette.ash,
                              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                            )),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.wb_sunny, size: 12, color: DailyPalette.gold),
                            const SizedBox(width: 3),
                            Text(w, style: const TextStyle(fontSize: 11, color: DailyPalette.ink)),
                            const Spacer(),
                            const Icon(Icons.nightlight_round, size: 12, color: DailyPalette.slate),
                            const SizedBox(width: 3),
                            Text(s, style: const TextStyle(fontSize: 11, color: DailyPalette.ink)),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}
