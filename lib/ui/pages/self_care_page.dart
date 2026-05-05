// DAILY · self_care 페이지 v13.1.1 — 회색 빈 영역 수정 (5/5 14:54 사용자 피드백)
// 3 필드만: 횟수 (오늘 누적) + 날짜 (자동) + 방법 (M / MV / V / partner)
// Expanded 제거 → ListView 단일 스크롤 + 빈 상태 명확히 표시.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../app/app.dart';
import '../../theme/theme.dart';

class SelfCarePage extends StatefulWidget {
  const SelfCarePage({super.key});

  @override
  State<SelfCarePage> createState() => _SelfCarePageState();
}

class _SelfCarePageState extends State<SelfCarePage> {
  String _method = 'M';
  bool _saving = false;

  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<void> _add() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('users/$kUid/self_care_log').add({
        'date': _today,
        'ts': FieldValue.serverTimestamp(),
        'method': _method,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('기록 추가 ($_method)'), duration: const Duration(seconds: 1)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('실패: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: DailyPalette.paper,
      appBar: AppBar(
        backgroundColor: DailyPalette.paper,
        elevation: 0,
        title: const Text('self_care'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _TodayCountCard(),
            const SizedBox(height: 20),
            Text('방법', style: theme.textTheme.titleSmall?.copyWith(color: DailyPalette.ash, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _methodChip('M', 'M (자위)'),
                _methodChip('MV', 'MV (영상)'),
                _methodChip('V', 'V (영상만)'),
                _methodChip('partner', 'partner'),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _add,
              icon: const Icon(Icons.add),
              label: Text(_saving ? '저장 중...' : '+ 기록 추가'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                backgroundColor: DailyPalette.gold,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 24),
            Text('최근 기록', style: theme.textTheme.titleSmall?.copyWith(color: DailyPalette.ash, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const _RecentSimpleList(),
          ],
        ),
      ),
    );
  }

  Widget _methodChip(String value, String label) {
    final selected = _method == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _method = value),
      selectedColor: DailyPalette.goldSurface,
      side: BorderSide(color: selected ? DailyPalette.gold : DailyPalette.line, width: selected ? 2 : 1),
      labelStyle: TextStyle(fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
    );
  }
}

class _TodayCountCard extends StatelessWidget {
  String get _today => DateFormat('yyyy-MM-dd').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users/$kUid/self_care_log')
          .where('date', isEqualTo: _today)
          .snapshots(),
      builder: (ctx, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: DailyPalette.goldSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DailyPalette.gold.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Text(_today.substring(5), style: theme.textTheme.titleMedium?.copyWith(color: DailyPalette.ash)),
              const Spacer(),
              Text('$count회', style: theme.textTheme.headlineMedium?.copyWith(
                color: DailyPalette.gold, fontWeight: FontWeight.w800,
              )),
            ],
          ),
        );
      },
    );
  }
}

class _RecentSimpleList extends StatelessWidget {
  const _RecentSimpleList();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users/$kUid/self_care_log')
          .orderBy('ts', descending: true)
          .limit(20)
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text('오류: ${snap.error}',
                style: theme.textTheme.bodySmall?.copyWith(color: DailyPalette.error)),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
            decoration: BoxDecoration(
              color: DailyPalette.paper,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DailyPalette.line, style: BorderStyle.solid),
            ),
            child: Column(
              children: [
                Icon(Icons.inbox_outlined, size: 36, color: DailyPalette.line),
                const SizedBox(height: 8),
                Text('아직 기록 없음',
                    style: theme.textTheme.bodyMedium?.copyWith(color: DailyPalette.ash)),
                const SizedBox(height: 4),
                Text('위 + 기록 추가 버튼으로 등재',
                    style: theme.textTheme.bodySmall?.copyWith(color: DailyPalette.ash)),
              ],
            ),
          );
        }
        return Column(
          children: [
            for (var i = 0; i < docs.length; i++) ...[
              _recordRow(theme, docs[i]),
              if (i < docs.length - 1) Divider(height: 1, color: DailyPalette.line),
            ],
          ],
        );
      },
    );
  }

  Widget _recordRow(ThemeData theme, QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final ts = d['ts'] as Timestamp?;
    final timeStr = ts != null ? DateFormat('MM/dd HH:mm').format(ts.toDate()) : '?';
    final method = d['method']?.toString() ?? d['type']?.toString() ?? '?';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: DailyPalette.goldSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Text(method,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: DailyPalette.gold, fontWeight: FontWeight.w800,
            fontSize: method.length > 2 ? 11 : 14,
          ),
        ),
      ),
      title: Text(timeStr, style: theme.textTheme.bodyMedium),
      trailing: IconButton(
        icon: Icon(Icons.delete_outline, color: DailyPalette.ash, size: 20),
        onPressed: () => doc.reference.delete(),
      ),
    );
  }
}
