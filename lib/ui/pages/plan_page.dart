import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/sleep_card.dart';
import '../widgets/sleep_plan_overview.dart';
import '../widgets/craving_card.dart';
import '../widgets/life_logs_summary.dart';

class PlanPage extends StatelessWidget {
  const PlanPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
          children: [
            const HeroCard(
              title: '계획',
              subtitle: '수면 위상 · 갈망 · 생활 누적',
              icon: Icons.flag_outlined,
            ),
            const SizedBox(height: DailySpace.lg),
            SectionHeader(title: '수면 위상', accent: DailyPalette.sleep),
            const SizedBox(height: DailySpace.sm),
            const SleepCard(),
            const SizedBox(height: DailySpace.md),
            const SleepPlanOverview(),
            const SizedBox(height: DailySpace.lg),
            SectionHeader(title: '갈망·생활 누적', accent: DailyPalette.craving),
            const SizedBox(height: DailySpace.sm),
            const CravingCard(),
            const SizedBox(height: DailySpace.md),
            const LifeLogsSummary(),
            const SizedBox(height: DailySpace.lg),
            SectionHeader(title: '누적 통계', accent: DailyPalette.gold),
            const SizedBox(height: DailySpace.sm),
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

/// 수면 위상 14일 — sleep bar 시각화 (트렌디·깔끔, 사용자 17:24 지시).
/// 24h timeline X축 + 취침~기상 sleep window 가로 bar.
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
        final wakeMap = <String, double>{}, sleepMap = <String, double>{};
        for (final d in snap.data?.docs ?? []) {
          final m = d.data();
          if (m['wake'] is Map && m['wake']['time'] is String) {
            wakeMap[d.id] = _toHourFrac(m['wake']['time']);
          }
          if (m['sleep'] is Map && m['sleep']['time'] is String) {
            sleepMap[d.id] = _toHourFrac(m['sleep']['time']);
          }
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
                  Icon(Icons.bedtime_rounded, size: 18, color: DailyPalette.primary),
                  SizedBox(width: 6),
                  Text('수면 위상 14일', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
                  Spacer(),
                  Text('취침→기상 사이 어두운 bar', style: TextStyle(fontSize: 9, color: DailyPalette.ash)),
                ],
              ),
              const SizedBox(height: DailySpace.md),
              // 24h hour markers
              _hourAxis(),
              const SizedBox(height: 4),
              ...List.generate(14, (i) {
                final d = start.add(Duration(days: i));
                final key = DateFormat('yyyy-MM-dd').format(d);
                final isToday = i == 13;
                // 취침 = 어제 sleep[d-1] (그 날 wake → 다음 날 wake 사이 sleep 의 *시작*)
                // 단순화: sleep[d-1] = 그 날 밤 취침, wake[d] = 그 날 아침 기상.
                final prevKey = DateFormat('yyyy-MM-dd').format(d.subtract(const Duration(days: 1)));
                final bedHour = sleepMap[prevKey];
                final wakeHour = wakeMap[key];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 46,
                        child: Text(DateFormat('M/d E', 'ko').format(d),
                            style: TextStyle(
                              fontSize: 10,
                              color: isToday ? DailyPalette.primary : DailyPalette.ash,
                              fontWeight: isToday ? FontWeight.w700 : FontWeight.w400,
                            )),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: _bar(bedHour, wakeHour, isToday)),
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

  static double _toHourFrac(String t) {
    // "01:30+1" = 다음날 1.5시
    final parts = t.split('+');
    final next = parts.length > 1;
    final hm = parts[0].split(':');
    final h = double.tryParse(hm[0]) ?? 0;
    final m = hm.length > 1 ? (double.tryParse(hm[1]) ?? 0) : 0;
    return h + m / 60 + (next ? 24 : 0);
  }

  Widget _hourAxis() {
    return SizedBox(
      height: 12,
      child: Row(
        children: [
          const SizedBox(width: 52),
          Expanded(
            child: Stack(
              children: List.generate(7, (i) {
                final hour = i * 4;
                return Positioned(
                  left: (hour / 24) * 1000.0 / 1000 * 0,  // 정확한 left 계산은 LayoutBuilder 필요
                  child: const SizedBox.shrink(),
                );
              })..addAll([
                LayoutBuilder(builder: (ctx, c) {
                  return SizedBox(
                    width: c.maxWidth, height: 12,
                    child: Stack(children: List.generate(7, (i) {
                      final hour = i * 4;
                      return Positioned(
                        left: (hour / 24) * c.maxWidth - 6,
                        child: Text('$hour시',
                            style: const TextStyle(fontSize: 8, color: DailyPalette.ash)),
                      );
                    })),
                  );
                }),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bar(double? bedHour, double? wakeHour, bool isToday) {
    return LayoutBuilder(builder: (ctx, c) {
      final w = c.maxWidth;
      // 24시간 = w 픽셀.
      // bedHour = 전날 취침. 기준: 전날 18시 ~ 그날 18시 윈도우 (또는 단순 그날 0~24).
      // 여기선 그날 0~24h 을 X축으로 하되, bedHour 가 0~6 또는 21~30 이면 그래프에 표현.
      final segments = <Widget>[];
      // sleep bar: bedHour 가 어제 저녁 (예: 23~28h normalized). bedHour 의 시각 = wake 까지.
      if (bedHour != null && wakeHour != null) {
        // bedHour 를 그날 시각으로 normalize: 24 이상이면 그대로, 미만이면 그대로
        // 단순화: bed = bedHour mod 24; 그날 새벽 wake 까지 = 0~wake. 그 전 = bed~24.
        double bedNorm = bedHour;
        if (bedNorm >= 24) bedNorm -= 24;
        // 새벽 sleep (bedNorm < wake) = single bar bedNorm~wake
        // 또는 전날 늦게 자서 bedNorm > wake = 두 bar (bedNorm~24, 0~wake)
        if (bedNorm < wakeHour) {
          segments.add(_seg(bedNorm / 24, (wakeHour - bedNorm) / 24, w));
        } else {
          segments.add(_seg(0, wakeHour / 24, w));
          segments.add(_seg(bedNorm / 24, (24 - bedNorm) / 24, w));
        }
      } else if (wakeHour != null) {
        // wake 만 있음 = wake 점만
        segments.add(_seg(wakeHour / 24 - 0.005, 0.01, w, color: DailyPalette.gold));
      }

      return Container(
        height: 14,
        decoration: BoxDecoration(
          color: DailyPalette.paper,
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: isToday ? DailyPalette.primary : DailyPalette.line, width: isToday ? 1.2 : 0.8),
        ),
        child: Stack(children: segments),
      );
    });
  }

  Widget _seg(double leftFrac, double widthFrac, double totalW, {Color? color}) {
    return Positioned(
      left: leftFrac * totalW,
      child: Container(
        height: 12,
        width: (widthFrac * totalW).clamp(2.0, totalW),
        decoration: BoxDecoration(
          color: color ?? DailyPalette.primary.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
