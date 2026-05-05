// DAILY · self_care v14.0 — 쿨웜 파스텔 믹스 (사용자 5/6 00:38 명시).
// header lilac→peach gradient · today count card · method chips (lilac selected) · coral add button.
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
          SnackBar(content: Text('+ $_method'), duration: const Duration(seconds: 1)),
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
    return Scaffold(
      backgroundColor: DailyV14.bg,
      appBar: AppBar(
        backgroundColor: DailyV14.bg,
        elevation: 0,
        title: const Text('self_care · v14'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTodayCount(),
              const SizedBox(height: 20),
              _buildMethodSection(),
              const SizedBox(height: 20),
              _buildAddButton(),
              const SizedBox(height: 24),
              _buildRecentSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTodayCount() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users/$kUid/self_care_log')
          .where('date', isEqualTo: _today)
          .snapshots(),
      builder: (ctx, snap) {
        final count = snap.data?.docs.length ?? 0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [DailyV14.lilacSoft, DailyV14.peachSoft],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: DailyV14.line),
          ),
          child: Row(
            children: [
              Text(_today.substring(5),
                  style: const TextStyle(fontSize: 16, color: DailyV14.ink2, fontWeight: FontWeight.w500)),
              const Spacer(),
              Text('$count회',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: DailyV14.lilacInk,
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMethodSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('방법',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DailyV14.ink2)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _methodChip('M', 'M (자위)'),
            _methodChip('MV', 'MV (영상)'),
            _methodChip('V', 'V (영상만)'),
            _methodChip('partner', 'partner'),
          ],
        ),
      ],
    );
  }

  Widget _methodChip(String value, String label) {
    final selected = _method == value;
    return GestureDetector(
      onTap: () => setState(() => _method = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? DailyV14.lilacSoft : DailyV14.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? DailyV14.lilac : DailyV14.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 16, color: DailyV14.lilacInk),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? DailyV14.lilacInk : DailyV14.ink,
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [DailyV14.coral, DailyV14.peach],
          ),
          boxShadow: [
            BoxShadow(
              color: DailyV14.coral.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          onPressed: _saving ? null : _add,
          icon: const Icon(Icons.add, size: 22),
          label: Text(_saving ? '저장 중...' : '+ 기록 추가',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            shadowColor: Colors.transparent,
          ),
        ),
      ),
    );
  }

  Widget _buildRecentSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users/$kUid/self_care_log')
          .orderBy('ts', descending: true)
          .limit(50)
          .snapshots(),
      builder: (ctx, snap) {
        final waiting = snap.connectionState == ConnectionState.waiting;
        final hasError = snap.hasError;
        final allDocs = snap.data?.docs ?? [];
        final docs = allDocs.where((d) {
          final m = (d.data() as Map<String, dynamic>)['method'];
          return m != null && m.toString().isNotEmpty;
        }).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('최근 기록',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: DailyV14.ink2)),
                const Spacer(),
                Text('총 ${docs.length}건',
                    style: const TextStyle(fontSize: 12, color: DailyV14.ink3)),
              ],
            ),
            const SizedBox(height: 10),
            if (waiting)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2, color: DailyV14.coral),
                ),
              )
            else if (hasError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                child: Text('오류: ${snap.error}',
                    style: const TextStyle(color: DailyV14.error)),
              )
            else if (docs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                decoration: BoxDecoration(
                  color: DailyV14.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: DailyV14.line),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 40, color: DailyV14.ink4),
                    SizedBox(height: 10),
                    Text('아직 기록 없음',
                        style: TextStyle(fontSize: 15, color: DailyV14.ink3, fontWeight: FontWeight.w500)),
                    SizedBox(height: 4),
                    Text('위 + 기록 추가 버튼으로 등재',
                        style: TextStyle(fontSize: 12, color: DailyV14.ink4)),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: DailyV14.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: DailyV14.line),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < docs.length; i++) ...[
                      _recordRow(docs[i]),
                      if (i < docs.length - 1)
                        Container(height: 1, color: DailyV14.line),
                    ],
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _recordRow(QueryDocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    final tsRaw = d['ts'];
    DateTime? dt;
    if (tsRaw is Timestamp) {
      dt = tsRaw.toDate();
    } else if (tsRaw is String) {
      dt = DateTime.tryParse(tsRaw);
    }
    if (dt == null && d['date'] is String) {
      dt = DateTime.tryParse('${d['date']}T12:00:00');
    }
    final timeStr = dt != null ? DateFormat('MM/dd HH:mm').format(dt) : '-';
    final method = d['method']?.toString() ?? '?';

    // method 별 색상 구분 (warm: M·MV / cool: V·partner)
    final methodColor = switch (method) {
      'M' => (DailyV14.peachSoft, DailyV14.coral),
      'MV' => (DailyV14.apricotSoft, DailyV14.goldDeep),
      'V' => (DailyV14.skySoft, DailyV14.info),
      'partner' => (DailyV14.lilacSoft, DailyV14.lilacInk),
      _ => (DailyV14.cardSoft, DailyV14.ink3),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 36,
            decoration: BoxDecoration(
              color: methodColor.$1,
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(method,
                style: TextStyle(
                  color: methodColor.$2,
                  fontWeight: FontWeight.w800,
                  fontSize: method.length > 2 ? 11 : 14,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(timeStr,
                style: const TextStyle(fontSize: 14, color: DailyV14.ink, fontFamily: 'monospace')),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: DailyV14.ink3),
            onPressed: () => doc.reference.delete(),
          ),
        ],
      ),
    );
  }
}
