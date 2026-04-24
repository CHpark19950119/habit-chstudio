import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '_card.dart';

/// 오늘 life_logs 전체 카테고리 요약 (chip)
class LifeLogsSummary extends StatelessWidget {
  const LifeLogsSummary({super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ref = FirebaseFirestore.instance.doc('users/$kUid/life_logs/$today');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data() ?? {};
        final chips = <(String, int)>[];
        for (final entry in data.entries) {
          if (entry.value is List && (entry.value as List).isNotEmpty) {
            chips.add((entry.key, (entry.value as List).length));
          }
        }
        return DailyCard(
          title: 'HB 오늘 기록',
          icon: Icons.edit_note_outlined,
          child: chips.isEmpty
              ? const Text('HB 텔레로 기록 시작하세요', style: TextStyle(fontSize: 12, color: DailyPalette.ash))
              : Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: chips.map((c) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: DailyPalette.goldSurface,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('${_label(c.$1)} ${c.$2}',
                            style: const TextStyle(fontSize: 11, color: DailyPalette.ink, fontWeight: FontWeight.w600)),
                      )).toList(),
                ),
        );
      },
    );
  }

  String _label(String key) {
    switch (key) {
      case 'meals': return '식사';
      case 'bowel': return '배변';
      case 'study': return '공부';
      case 'outing': return '외출';
      case 'hydration': return '수분';
      case 'care': return '관리';
      case 'game': return '게임';
      default: return key;
    }
  }
}
