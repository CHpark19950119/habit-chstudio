// DAILY 오늘 탭 — 일상 dashboard (사용자 명시 2026-05-01 14:32 = 공부 관련 전부 제거).
// Hero (날짜 + 수면 위상 + 오늘 취침 권고) + Quick stats + 오늘의 순서 + 오늘 일정.
// STUDY 도메인 (D-day·Phase·plan v6.x) = ST 앱에서 별도 표시.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/routine_checklist.dart';
import '../widgets/today_timeline.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => await Future.delayed(const Duration(milliseconds: 300)),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
            children: [
              const _HeroToday(),
              const SizedBox(height: DailySpace.lg),
              const _QuickStats(),
              const SizedBox(height: DailySpace.lg),
              SectionHeader(title: '오늘의 순서', accent: theme.colorScheme.primary),
              const SizedBox(height: DailySpace.sm),
              const RoutineChecklist(),
              const SizedBox(height: DailySpace.lg),
              SectionHeader(title: '오늘 일정', accent: DailyPalette.gold),
              const SizedBox(height: DailySpace.sm),
              const TodayTimeline(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hero · v12 luminous bento + 수면 위상 중심 (사용자 명시 2026-05-01 14:32 · 공부 도메인 제거).
class _HeroToday extends StatelessWidget {
  const _HeroToday();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // 수면 위상 사다리 = plan v6.2 정합 (-30분/일 · D9 02:30 → D16 23:00)
    final phase1Start = DateTime(2026, 4, 23); // D1
    final dn = now.difference(DateTime(phase1Start.year, phase1Start.month, phase1Start.day)).inDays + 1;
    String sleepTarget;
    if (dn <= 9) {sleepTarget = '02:30';}
    else if (dn == 10) {sleepTarget = '02:00';}
    else if (dn == 11) {sleepTarget = '01:30';}
    else if (dn == 12) {sleepTarget = '01:00';}
    else if (dn == 13) {sleepTarget = '00:30';}
    else if (dn == 14) {sleepTarget = '00:00';}
    else if (dn == 15) {sleepTarget = '23:30';}
    else {sleepTarget = '23:00';}
    final wakeTarget = '+8h 후';
    final dayLabel = DateFormat('M.d EEEE', 'ko').format(now);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(26, 32, 26, 28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF6E0), Color(0xFFFFEAC4), Color(0xFFF4D9A8)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: DailyV12Radius.card,
        boxShadow: DailyV12Shadow.card(),
        border: Border.all(color: DailyV12.bronze.withValues(alpha: 0.18), width: 1),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -50, top: -50,
            child: Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [DailyV12.bronzeGlow, DailyV12.bronzeGlow.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    DateFormat('yyyy.MM.dd EEEE', 'ko').format(now),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DailyV12.bronzeDeep, letterSpacing: 1.2),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: DailyV12.bronze.withValues(alpha: 0.16),
                      borderRadius: DailyV12Radius.capsule,
                      border: Border.all(color: DailyV12.bronze.withValues(alpha: 0.55)),
                    ),
                    child: Text(
                      '오늘 $dayLabel',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: DailyV12.bronzeDeep, letterSpacing: 0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                '수면 위상 정진',
                style: TextStyle(fontSize: 14, color: DailyV12.bronzeDeep, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ShaderMask(
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.topCenter, end: Alignment.bottomCenter,
                      colors: [Color(0xFFB87020), Color(0xFF824A14), Color(0xFF5A3008)],
                      stops: [0, 0.55, 1.0],
                    ).createShader(rect),
                    blendMode: BlendMode.srcIn,
                    child: Text(
                      sleepTarget,
                      style: const TextStyle(
                        fontSize: 64, fontWeight: FontWeight.w900,
                        height: 0.95, letterSpacing: -2.4,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 10, bottom: 12),
                    child: Text(
                      '취침 목표',
                      style: TextStyle(fontSize: 14, color: DailyV12.ink3, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '기상 = 취침 $wakeTarget · 광노출 산책 30m',
                style: const TextStyle(fontSize: 13, color: DailyV12.ink2, height: 1.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 8, runSpacing: 8,
                children: [
                  _badge('일상', DailyV12.bronzeDeep),
                  _badge('수면·식사·routine', DailyV12.bronze),
                  _badge('학업 = ST 앱', DailyV12.ink3),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.6), width: 1),
        ),
        child: Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color)),
      );
}

/// Quick stats — 4-grid (수면·식사·외출·Detox).
class _QuickStats extends StatelessWidget {
  const _QuickStats();

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ref = FirebaseFirestore.instance.doc('users/$kUid/life_logs/$today');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (ctx, snap) {
        final data = snap.data?.data() ?? {};
        final wake = (data['wake'] as Map?)?['time']?.toString() ?? '—';
        final sleep = (data['sleep'] as Map?)?['time']?.toString() ?? '—';
        final mealsCount = (data['meals'] as List?)?.length ?? 0;
        final outingCount = (data['outing'] as List?)?.length ?? 0;
        final mediaList = data['media'] as List?;
        final mediaTotal = mediaList?.fold<int>(0, (a, b) => a + ((b is Map ? b['duration_min'] : 0) as num? ?? 0).toInt()) ?? 0;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.6,
          children: [
            StatCard(label: '기상 / 취침', value: wake, sub: '취침 $sleep', icon: Icons.wb_sunny_outlined, accent: DailyPalette.gold),
            StatCard(label: '식사', value: '$mealsCount회', sub: '오늘 등재', icon: Icons.restaurant_outlined, accent: DailyPalette.success),
            StatCard(label: '외출', value: '$outingCount회', sub: 'outing 토글', icon: Icons.directions_walk_outlined, accent: DailyPalette.info),
            StatCard(label: '미디어', value: '${mediaTotal}분', sub: '쇼츠 누적', icon: Icons.smart_display_outlined, accent: DailyPalette.craving),
          ],
        );
      },
    );
  }
}
