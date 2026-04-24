import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '_card.dart';

class CravingCard extends StatelessWidget {
  const CravingCard({super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ref = FirebaseFirestore.instance.doc('users/$kUid/life_logs/$today');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data() ?? {};
        final psych = (data['psych'] is Map) ? Map<String, dynamic>.from(data['psych']) : <String, dynamic>{};
        final lol = psych['cravingLol'];
        final mood = psych['mood']?.toString();

        return DailyCard(
          title: '갈망 · 기분',
          icon: Icons.favorite_border,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (lol == null && (mood == null || mood.isEmpty))
                const Text('기록 없음', style: TextStyle(fontSize: 12, color: DailyPalette.ash))
              else ...[
                if (lol != null) ...[
                  Row(
                    children: [
                      const SizedBox(width: 2, child: Text('LoL', style: TextStyle(fontSize: 10))),
                      const SizedBox(width: 30),
                      Expanded(
                        child: LinearProgressIndicator(
                          value: (lol as num).toDouble() / 10,
                          minHeight: 6,
                          backgroundColor: DailyPalette.line,
                          valueColor: AlwaysStoppedAnimation<Color>(_lolColor(lol)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('$lol/10', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
                if (mood != null && mood.isNotEmpty)
                  Row(
                    children: [
                      const Text('기분 ', style: TextStyle(fontSize: 11, color: DailyPalette.ash)),
                      Text(mood, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: DailyPalette.ink)),
                    ],
                  ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _lolColor(num v) => v >= 7 ? DailyPalette.craving : v >= 4 ? DailyPalette.warn : DailyPalette.success;
}
