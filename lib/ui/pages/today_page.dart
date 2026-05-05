// DAILY 오늘 탭 v14.0 — 쿨웜 파스텔 믹스 (사용자 5/6 00:38 명시).
// header (peach→sky→lilac gradient) + timeRecords (apricot/mint/lilac) + routine (mint check) + self_care FAB (coral).
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
      backgroundColor: DailyV14.bg,
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DailyV14.coral, DailyV14.peach],
          ),
          boxShadow: [
            BoxShadow(
              color: DailyV14.coral.withValues(alpha: 0.35),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          icon: const Icon(Icons.favorite),
          label: const Text('self_care', style: TextStyle(fontWeight: FontWeight.w700)),
          onPressed: () {
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SelfCarePage()));
          },
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
          children: const [
            _Header(),
            SizedBox(height: 14),
            _TimeRecordsCard(),
            SizedBox(height: 14),
            _RoutineChecklist(),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [DailyV14.peachSoft, DailyV14.skySoft, DailyV14.lilacSoft],
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: DailyV14.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dateStr,
              style: theme.textTheme.bodyMedium?.copyWith(color: DailyV14.ink2, fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('D-$dDay',
                  style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800, color: DailyV14.goldDeep)),
              const SizedBox(width: 12),
              Text('· W$week 적응기',
                  style: theme.textTheme.titleMedium?.copyWith(
                      color: DailyV14.ink, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

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

        return Container(
          decoration: BoxDecoration(
            color: DailyV14.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: DailyV14.line),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 0, 2, 10),
                child: Text('오늘 동선',
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Row(
                children: [
                  Expanded(child: _TimeChip(
                    label: '기상', icon: '🌅', value: wake, field: 'wake', docRef: docRef,
                    fillBg: DailyV14.apricotSoft, fillBorder: DailyV14.apricot, fillInk: DailyV14.coral,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _TimeChip(
                    label: '외출', icon: '🚪', value: outing, field: 'outing', docRef: docRef,
                    fillBg: DailyV14.mintSoft, fillBorder: DailyV14.mint, fillInk: DailyV14.mintInk,
                  )),
                  const SizedBox(width: 8),
                  Expanded(child: _TimeChip(
                    label: '귀가', icon: '🏠', value: returnHome, field: 'returnHome', docRef: docRef,
                    fillBg: DailyV14.lilacSoft, fillBorder: DailyV14.lilac, fillInk: DailyV14.lilacInk,
                  )),
                ],
              ),
            ],
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
  final Color fillBg, fillBorder, fillInk;
  const _TimeChip({
    required this.label,
    required this.icon,
    required this.value,
    required this.field,
    required this.docRef,
    required this.fillBg,
    required this.fillBorder,
    required this.fillInk,
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
      borderRadius: BorderRadius.circular(14),
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
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: filled ? fillBg : DailyV14.cardSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: filled ? fillBorder : DailyV14.line),
        ),
        child: Column(
          children: [
            Text('$icon $label',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: DailyV14.ink2,
                  fontWeight: FontWeight.w600,
                )),
            const SizedBox(height: 6),
            Text(filled ? value! : '—',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: filled ? fillInk : DailyV14.ink3,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'monospace',
                )),
          ],
        ),
      ),
    );
  }
}

class _RoutineChecklist extends StatelessWidget {
  const _RoutineChecklist();

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

        return Container(
          decoration: BoxDecoration(
            color: DailyV14.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: DailyV14.line),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                child: Row(
                  children: [
                    Text('오늘의 계획',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: DailyV14.peachSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('$doneCount / ${_items.length}',
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: DailyV14.coral, fontWeight: FontWeight.w800)),
                    ),
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
      borderRadius: BorderRadius.circular(10),
      onTap: () => docRef.set({'checks': {id: !checked}}, SetOptions(merge: true)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 26, height: 26,
              decoration: BoxDecoration(
                color: checked ? DailyV14.mint : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: checked ? DailyV14.mint : DailyV14.ink4,
                  width: 2,
                ),
              ),
              child: checked
                  ? const Icon(Icons.check, size: 18, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 50,
              child: Text(time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: DailyV14.goldDeep,
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
                  color: checked ? DailyV14.ink3 : DailyV14.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
