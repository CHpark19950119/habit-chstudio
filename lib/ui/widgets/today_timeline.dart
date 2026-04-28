// 오늘 일정 timeline — wake / outing / meals / events / payments / sleep target 시간순.
// 사용자 지시 (2026-04-28 16:58): 홈 = 그날 일정 + 그날 순서 만 간결.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '_card.dart';

class TodayTimeline extends StatelessWidget {
  const TodayTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final ref = FirebaseFirestore.instance.doc('users/$kUid/life_logs/$today');
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: ref.snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data() ?? {};
        final entries = _collect(data);
        return DailyCard(
          title: '오늘 일정',
          icon: Icons.timeline_outlined,
          child: entries.isEmpty
              ? const Text('기록 없음', style: TextStyle(fontSize: 12, color: DailyPalette.ash))
              : Column(
                  children: entries.map((e) => _row(e)).toList(),
                ),
        );
      },
    );
  }

  List<_Entry> _collect(Map<String, dynamic> data) {
    final list = <_Entry>[];

    if (data['wake'] is Map) {
      final w = data['wake'] as Map;
      final t = w['time']?.toString();
      if (t != null) list.add(_Entry(t, '🌅', '기상', w['note']?.toString()));
    }

    if (data['meals'] is List) {
      for (final m in (data['meals'] as List).whereType<Map>()) {
        final s = (m['start'] ?? m['time'])?.toString();
        final e = m['end']?.toString();
        if (s != null) {
          list.add(_Entry(s, '🍽️', '식사 시작', e != null ? '~$e' : '진행 중'));
        }
      }
    }

    if (data['outing'] is List) {
      for (final o in (data['outing'] as List).whereType<Map>()) {
        final t = o['time']?.toString();
        final r = o['returnHome']?.toString();
        if (t != null) {
          final dest = o['destination']?.toString() ?? '';
          list.add(_Entry(t, '🚶', '외출', '$dest${r != null ? ' (귀가 $r)' : ' (진행 중)'}'));
        }
      }
    }

    if (data['events'] is List) {
      for (final e in (data['events'] as List).whereType<Map>()) {
        final t = e['time']?.toString();
        if (t != null) {
          final tag = e['tag']?.toString() ?? '';
          final emoji = _emojiForTag(tag);
          list.add(_Entry(t, emoji, tag, e['note']?.toString()));
        }
      }
    }

    if (data['payments'] is List) {
      for (final p in (data['payments'] as List).whereType<Map>()) {
        final t = p['time']?.toString();
        if (t != null) {
          list.add(_Entry(t, '💳',
              '결제 ${p['place'] ?? ''} ${p['amount'] ?? ''}원', p['service']?.toString()));
        }
      }
    }

    if (data['sleep'] is Map) {
      final s = data['sleep'] as Map;
      final t = s['time']?.toString();
      if (t != null) list.add(_Entry(t, '🛏️', '취침', s['note']?.toString()));
    }

    list.sort((a, b) => _normalize(a.time).compareTo(_normalize(b.time)));
    return list;
  }

  String _normalize(String t) {
    // "01:30+1" 같은 다음날 표기 처리
    if (t.contains('+')) return '24:${t.split(':').last.split('+').first}';
    return t;
  }

  String _emojiForTag(String tag) {
    if (tag.contains('study') || tag == 'focus') return '📖';
    if (tag.contains('break')) return '☕';
    if (tag.contains('meal')) return '🍽️';
    if (tag.contains('hygiene') || tag.contains('샤워')) return '🚿';
    if (tag.contains('plan')) return '📋';
    if (tag.contains('date')) return '💞';
    return '📌';
  }

  Widget _row(_Entry e) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 50, child: Text(e.time, style: const TextStyle(fontSize: 12, color: DailyPalette.slate, fontWeight: FontWeight.w700))),
            Text(e.emoji, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
            Expanded(
              child: RichText(
                text: TextSpan(
                  children: [
                    TextSpan(text: e.label, style: const TextStyle(fontSize: 12, color: DailyPalette.ink, fontWeight: FontWeight.w600)),
                    if (e.note != null && e.note!.isNotEmpty)
                      TextSpan(text: '  ${e.note}', style: const TextStyle(fontSize: 11, color: DailyPalette.ash, fontWeight: FontWeight.w400)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
}

class _Entry {
  final String time;
  final String emoji;
  final String label;
  final String? note;
  _Entry(this.time, this.emoji, this.label, this.note);
}
