import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '_card.dart';

class MealsCard extends StatelessWidget {
  const MealsCard({super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ref = FirebaseFirestore.instance.doc('users/$kUid/life_logs/$today');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data() ?? {};
        final meals = (data['meals'] is List) ? (data['meals'] as List) : [];
        return DailyCard(
          title: '식사',
          icon: Icons.restaurant_outlined,
          child: meals.isEmpty
              ? const Text('기록 없음', style: TextStyle(fontSize: 12, color: DailyPalette.ash))
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: meals.whereType<Map>().map((m) {
                    final t = m['time']?.toString() ?? '—';
                    final menu = m['menu']?.toString() ?? '';
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          SizedBox(width: 52, child: Text(t, style: const TextStyle(fontSize: 12, color: DailyPalette.slate))),
                          Expanded(child: Text(menu, style: const TextStyle(fontSize: 13, color: DailyPalette.ink))),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        );
      },
    );
  }
}
