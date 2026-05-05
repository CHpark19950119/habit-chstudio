// DAILY 오늘 탭 v13.4 — 사용자 5/6 00:23 명시: timeRecords 3필드 표기 + 누락 시 보정 UI.
// 헤더 + timeRecords 카드 (기상/외출/귀가) + 매일 계획 체크박스 + self_care FAB.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import 'self_care_page.dart';

class TodayPage extends StatelessWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: DailyPalette.gold,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.favorite),
        label: const Text('self_care'),
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SelfCarePage()));
        },
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: const [
            _Header(),
            SizedBox(height: 16),
            _TimeRecordsCard(),
            SizedBox(height: 20),
            _RoutineChecklist(),
          ],
        ),
      ),
    );
  }
}

/// timeRecords 카드 — 기상·외출·귀가 3필드 표기 + 누락 시 보정.
/// 사용자 5/6 00:23 명시: 매일 누락 없이 기록.
class _TimeRecordsCard extends StatelessWidget {
  const _TimeRecordsCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final docRef = FirebaseFirestore.instance.collection('users/$kUid/data').doc('today');

    return StreamBuilder<DocumentSnapshot>(
      stream: docRef.snapshots(),
      builder: (ctx, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final tr = (data['timeRecords'] as Map<String, dynamic>? ?? {}).cast<String, dynamic>();
        final wake = tr['wake']?.toString();
        final outing = tr['outing']?.toString();
        final returnHome = tr['returnHome']?.toString();

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: DailyPalette.line),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text('오늘 동선',
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ),
                Row(
                  children: [
                    Expanded(child: _TimeChip(label: '기상', icon: '🌅', value: wake, field: 'wake', docRef: docRef)),
                    const SizedBox(width: 8),
                    Expanded(child: _TimeChip(label: '외출', icon: '🚪', value: outing, field: 'outing', docRef: docRef)),
                    const SizedBox(width: 8),
                    Expanded(child: _TimeChip(label: '귀가', icon: '🏠', value: returnHome, field: 'returnHome', docRef: docRef)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TimeChip extends StatelessWidget {
  final String label, icon, field;
  final String? value;
  final DocumentReference docRef;
  const _TimeChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.field,
    required this.docRef,
  });

  Future<void> _pick(BuildContext context) async {
    final now = TimeOfDay.now();
    final initial = value != null && value!.contains(':')
        ? TimeOfDay(
            hour: int.tryParse(value!.split(':')[0]) ?? now.hour,
            minute: int.tryParse(value!.split(':')[1]) ?? now.minute,
          )
        : now;
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    final timeStr = '$hh:$mm';
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await docRef.set({
      'timeRecords': {field: timeStr},
      'timeRecords.$today': {field: timeStr},
    }, SetOptions(merge: true));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filled = value != null && value!.isNotEmpty;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _pick(context),
      onLongPress: filled
          ? () async {
              final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
              await docRef.set({
                'timeRecords': {field: FieldValue.delete()},
                'timeRecords.$today': {field: FieldValue.delete()},
              }, SetOptions(merge: true));
            }
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: filled ? DailyPalette.goldSurface : DailyPalette.paper,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: filled ? DailyPalette.gold.withValues(alpha: 0.3) : DailyPalette.line,
          ),
        ),
        child: Column(
          children: [
            Text('$icon $label',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF8A857C),
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 6),
            Text(filled ? value! : '—',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: filled ? DailyPalette.gold : const Color(0xFFB8B2A6),
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                )),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(now);
    final dDay = DateTime(2026, 7, 19).difference(now).inDays;
    final w1 = DateTime(2026, 5, 5);
    final week = (now.difference(w1).inDays / 7).floor() + 1;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DailyPalette.goldSurface, DailyPalette.cream],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: DailyPalette.gold.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateStr, style: theme.textTheme.bodyMedium?.copyWith(color: DailyPalette.ash, fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('D-$dDay',
                  style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: DailyPalette.gold)),
              const SizedBox(width: 12),
              Text('· W$week 적응기',
                  style: theme.textTheme.titleMedium?.copyWith(color: DailyPalette.ink, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

/// 매일 계획 체크박스 — plan v6.2 routine 1:1
class _RoutineChecklist extends StatelessWidget {
  const _RoutineChecklist();

  // sortKey = 정렬용 / id = Firestore 키 / time / label / icon
  static const _items = <Map<String, String>>[
    {'id': 'wake', 'time': '06:30', 'label': '기상 + 광노출 5분', 'icon': '🌅'},
    {'id': 'breakfast', 'time': '06:50', 'label': '아침 30분', 'icon': '🍚'},
    {'id': 't1', 'time': '07:30', 'label': 'T1 deliberate 4h', 'icon': '📚'},
    {'id': 'lunch', 'time': '12:30', 'label': '점심 + 산책', 'icon': '🍱'},
    {'id': 't2', 'time': '13:00', 'label': 'T2 review 4h', 'icon': '📖'},
    {'id': 'exercise', 'time': '17:00', 'label': '운동 30분 (홈 스트레칭)', 'icon': '🤸'},
    {'id': 'shower', 'time': '17:30', 'label': '샤워·세면', 'icon': '🚿'},
    {'id': 'dinner', 'time': '18:00', 'label': '저녁 30분', 'icon': '🍽'},
    {'id': 't3', 'time': '19:00', 'label': 'T3 light 2~4h', 'icon': '✏️'},
    {'id': 'tidy', 'time': '22:30', 'label': '생활 정리 30분', 'icon': '🧼'},
    {'id': 'sleep', 'time': '23:30', 'label': '취침 (W4 = 23:00)', 'icon': '🌙'},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final docRef = FirebaseFirestore.instance.collection('users/$kUid/daily_log').doc(today);

    return StreamBuilder<DocumentSnapshot>(
      stream: docRef.snapshots(),
      builder: (ctx, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final checks = (data['checks'] as Map<String, dynamic>? ?? {}).cast<String, dynamic>();
        final doneCount = _items.where((it) => checks[it['id']] == true).length;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: DailyPalette.line),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: Row(
                    children: [
                      Text('오늘의 계획',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text('$doneCount / ${_items.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: DailyPalette.gold, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                for (final it in _items)
                  _CheckRow(
                    docRef: docRef,
                    id: it['id']!,
                    time: it['time']!,
                    label: it['label']!,
                    icon: it['icon']!,
                    checked: checks[it['id']] == true,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CheckRow extends StatelessWidget {
  final DocumentReference docRef;
  final String id, time, label, icon;
  final bool checked;
  const _CheckRow({
    required this.docRef,
    required this.id,
    required this.time,
    required this.label,
    required this.icon,
    required this.checked,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => docRef.set({'checks': {id: !checked}}, SetOptions(merge: true)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              color: checked ? DailyPalette.gold : DailyPalette.ash,
              size: 26,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 50,
              child: Text(time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DailyPalette.gold,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  )),
            ),
            Text('$icon  ', style: const TextStyle(fontSize: 18)),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  decoration: checked ? TextDecoration.lineThrough : null,
                  color: checked ? DailyPalette.ash : DailyPalette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
