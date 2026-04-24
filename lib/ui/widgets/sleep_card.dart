import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '_card.dart';

/// 수면 카드 · 어제 취침 · 오늘 기상 · 수면 시간 계산
class SleepCard extends StatelessWidget {
  const SleepCard({super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yesterday = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

    final todayRef = FirebaseFirestore.instance.doc('users/$kUid/life_logs/$today');
    final yRef = FirebaseFirestore.instance.doc('users/$kUid/life_logs/$yesterday');

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: todayRef.snapshots(),
      builder: (_, tSnap) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: yRef.snapshots(),
          builder: (_, ySnap) {
            final tData = tSnap.data?.data() ?? {};
            final yData = ySnap.data?.data() ?? {};
            final wake = (tData['wake'] is Map) ? tData['wake']['time'] : null;
            final sleep = (yData['sleep'] is Map) ? yData['sleep']['time'] : null;
            final duration = _calcDuration(sleep, wake);

            return DailyCard(
              title: '수면',
              icon: Icons.bedtime_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _row('어제 취침', sleep ?? '—'),
                      const Spacer(),
                      _row('오늘 기상', wake ?? '—'),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (duration != null)
                    Text('수면 시간 $duration',
                        style: const TextStyle(fontSize: 13, color: DailyPalette.sleep, fontWeight: FontWeight.w700))
                  else
                    const Text('취침·기상 기록 후 수면 시간 자동 계산',
                        style: TextStyle(fontSize: 11, color: DailyPalette.ash)),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _row(String l, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l, style: const TextStyle(fontSize: 10, color: DailyPalette.ash)),
          Text(v, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DailyPalette.ink)),
        ],
      );

  String? _calcDuration(String? sleep, String? wake) {
    if (sleep == null || wake == null) return null;
    try {
      final s = _toMin(sleep);
      final w = _toMin(wake);
      int diff = w - s;
      if (diff < 0) diff += 1440;
      final h = diff ~/ 60;
      final m = diff % 60;
      return '${h}h ${m}m';
    } catch (_) {
      return null;
    }
  }

  int _toMin(String hhmm) {
    final p = hhmm.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
}
