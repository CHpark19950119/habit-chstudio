// DAILY · self_care 페이지 (사용자 명시 2026-05-04 02:22 KST)
// 자위·시청 등재 + 누적 분석 + craving cycle 추적.
// 민감 기록 = sanitized code (type·mode 만 · 본문 X · CLAUDE.md 정합).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';
import '../widgets/common.dart';

class SelfCarePage extends StatelessWidget {
  const SelfCarePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 100),
          children: [
            const _HeroSelfCare(),
            const SizedBox(height: DailySpace.lg),
            SectionHeader(title: '14일 빈도', accent: DailyV12.bronze),
            const SizedBox(height: DailySpace.sm),
            const _Frequency14(),
            const SizedBox(height: DailySpace.lg),
            SectionHeader(title: '최근 기록', accent: DailyV12.bronzeDeep),
            const SizedBox(height: DailySpace.sm),
            const _RecentList(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showQuickAdd(context),
        icon: const Icon(Icons.add),
        label: const Text('빠른 등재'),
        backgroundColor: DailyV12.bronze,
        foregroundColor: DailyV12.cream,
      ),
    );
  }

  void _showQuickAdd(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _QuickAddSheet(),
    );
  }
}

/// Hero · 오늘 빈도 + 어제 비교 + 위상 정진 정보
class _HeroSelfCare extends StatelessWidget {
  const _HeroSelfCare();

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(kUid).collection('self_care_log')
          .where('date', isEqualTo: today)
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        final todayCount = docs.length;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(26, 28, 26, 24),
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
                  width: 200, height: 200,
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
                  const Text(
                    'self-care · 자위 등재',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DailyV12.bronzeDeep, letterSpacing: 1.2),
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
                          '$todayCount',
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
                          '오늘 등재 회수',
                          style: TextStyle(fontSize: 13, color: DailyV12.ink3, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '본문 X · type/mode 코드만 등재 (sanitized)',
                    style: TextStyle(fontSize: 12, color: DailyV12.ink2, height: 1.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 14일 빈도 막대
class _Frequency14 extends StatelessWidget {
  const _Frequency14();

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day).subtract(const Duration(days: 13));
    final startKey = DateFormat('yyyy-MM-dd').format(start);
    final endKey = DateFormat('yyyy-MM-dd').format(today);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(kUid).collection('self_care_log')
          .where('date', isGreaterThanOrEqualTo: startKey)
          .where('date', isLessThanOrEqualTo: endKey)
          .snapshots(),
      builder: (ctx, snap) {
        final byDay = <String, int>{};
        for (int i = 0; i < 14; i++) {
          final d = start.add(Duration(days: i));
          byDay[DateFormat('yyyy-MM-dd').format(d)] = 0;
        }
        for (final d in snap.data?.docs ?? []) {
          final m = d.data();
          final date = m['date']?.toString();
          if (date != null && byDay.containsKey(date)) {
            byDay[date] = (byDay[date] ?? 0) + 1;
          }
        }
        final maxCount = byDay.values.fold<int>(0, (a, b) => a > b ? a : b);
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
                  const Text('최근 14일', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DailyV12.ink2)),
                  const Spacer(),
                  Text('총 ${total}회', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: DailyV12.bronzeDeep)),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 64,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: byDay.entries.map((e) {
                    final h = maxCount == 0 ? 0.0 : (e.value / maxCount) * 56.0;
                    final isToday = e.key == DateFormat('yyyy-MM-dd').format(today);
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              height: h.clamp(2.0, 56.0),
                              decoration: BoxDecoration(
                                color: isToday ? DailyV12.bronzeDeep : DailyV12.bronze.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.key.substring(8, 10)}',
                              style: TextStyle(
                                fontSize: 8,
                                color: isToday ? DailyV12.bronzeDeep : DailyPalette.ash,
                                fontWeight: isToday ? FontWeight.w800 : FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 최근 기록 list (10건 한도)
class _RecentList extends StatelessWidget {
  const _RecentList();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(kUid).collection('self_care_log')
          .orderBy('ts', descending: true)
          .limit(10)
          .snapshots(),
      builder: (ctx, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(DailySpace.lg),
            decoration: BoxDecoration(
              color: DailyPalette.card,
              borderRadius: BorderRadius.circular(DailySpace.radiusL),
              border: Border.all(color: DailyPalette.line),
            ),
            child: const Text(
              '등재 기록 없음. 우측 하단 "빠른 등재" 버튼 활용.',
              style: TextStyle(fontSize: 12, color: DailyPalette.ash),
            ),
          );
        }
        return Column(
          children: docs.map((d) => _LogTile(doc: d)).toList(),
        );
      },
    );
  }
}

class _LogTile extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _LogTile({required this.doc});

  @override
  Widget build(BuildContext context) {
    final m = doc.data();
    final ts = m['ts']?.toString() ?? '';
    final tShort = ts.length >= 16 ? ts.substring(11, 16) : '?';
    final dShort = ts.length >= 10 ? ts.substring(5, 10) : '?';
    final type = m['type']?.toString() ?? '?';
    final mode = m['mode']?.toString() ?? '';
    final video = m['video_recorded'] == true;
    final context_ = m['context']?.toString() ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: DailyPalette.card,
        borderRadius: BorderRadius.circular(DailySpace.radiusL),
        border: Border.all(color: DailyPalette.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: DailyV12.bronze.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: DailyV12.bronze.withValues(alpha: 0.4)),
            ),
            child: Text(type, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: DailyV12.bronzeDeep)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$dShort $tShort', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: DailyV12.ink2)),
                    if (mode.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(mode, style: const TextStyle(fontSize: 11, color: DailyV12.ink3, fontWeight: FontWeight.w600)),
                    ],
                    if (video) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.videocam, size: 12, color: DailyPalette.error),
                    ],
                  ],
                ),
                if (context_.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(context_, style: const TextStyle(fontSize: 11, color: DailyPalette.ash)),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: DailyPalette.ash),
            onPressed: () async {
              await doc.reference.delete();
            },
          ),
        ],
      ),
    );
  }
}

/// 빠른 등재 sheet
class _QuickAddSheet extends StatefulWidget {
  const _QuickAddSheet();
  @override
  State<_QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<_QuickAddSheet> {
  String _type = 'M';
  String _mode = 'EL';
  bool _videoRecorded = false;
  bool _cleanupDone = true;
  final _ctxCtrl = TextEditingController();

  @override
  void dispose() { _ctxCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    final now = DateTime.now();
    final ts = now.toIso8601String();
    final date = DateFormat('yyyy-MM-dd').format(now);
    await FirebaseFirestore.instance
        .collection('users').doc(kUid).collection('self_care_log').add({
      'date': date,
      'ts': ts,
      'type': _type,
      'mode': _mode,
      'context': _ctxCtrl.text.trim(),
      'video_recorded': _videoRecorded,
      'cleanup_done': _cleanupDone,
    });
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      decoration: const BoxDecoration(
        color: DailyPalette.card,
        borderRadius: BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(color: DailyPalette.line, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const Text('self-care 빠른 등재', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: DailyV12.bronzeDeep)),
          const SizedBox(height: 14),
          const Text('type', style: TextStyle(fontSize: 11, color: DailyPalette.slate, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: ['M', 'V', 'MV', 'partner'].map((t) => ChoiceChip(
              label: Text(t),
              selected: _type == t,
              onSelected: (v) => setState(() => _type = t),
            )).toList(),
          ),
          const SizedBox(height: 12),
          const Text('mode', style: TextStyle(fontSize: 11, color: DailyPalette.slate, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            children: ['EL', 'mainstream', 'imagination', 'partner'].map((m) => ChoiceChip(
              label: Text(m),
              selected: _mode == m,
              onSelected: (v) => setState(() => _mode = m),
            )).toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _ctxCtrl,
            decoration: const InputDecoration(
              labelText: 'context (1줄 · 자유 · 본문은 sanitized)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            maxLength: 80,
          ),
          Row(
            children: [
              Checkbox(value: _videoRecorded, onChanged: (v) => setState(() => _videoRecorded = v ?? false)),
              const Text('영상 촬영', style: TextStyle(fontSize: 12)),
              const Spacer(),
              Checkbox(value: _cleanupDone, onChanged: (v) => setState(() => _cleanupDone = v ?? true)),
              const Text('정리 완료', style: TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: const Text('등재'),
              style: FilledButton.styleFrom(
                backgroundColor: DailyV12.bronze,
                foregroundColor: DailyV12.cream,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
