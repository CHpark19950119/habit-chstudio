// DAILY · self_care 페이지 v13.2 — 코드 전면 재작성 (사용자 5/5 15:27 명시)
// 목표: 회색 영역 X / 모든 widget 명시적 background / 단순 SingleChildScrollView.
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
    return Container(
      color: DailyPalette.paper,
      child: Scaffold(
        backgroundColor: DailyPalette.paper,
        appBar: AppBar(
          backgroundColor: DailyPalette.paper,
          elevation: 0,
          title: const Text('self_care · v13.2'),
        ),
        body: SafeArea(
          child: Container(
            color: DailyPalette.paper,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTodayCount(),
                  const SizedBox(height: 24),
                  _buildMethodSection(),
                  const SizedBox(height: 24),
                  _buildAddButton(),
                  const SizedBox(height: 28),
                  _buildRecentSection(),
                ],
              ),
            ),
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
            color: DailyPalette.goldSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DailyPalette.gold.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Text(_today.substring(5),
                  style: const TextStyle(fontSize: 17, color: Color(0xFF8A857C))),
              const Spacer(),
              Text('$count회',
                  style: const TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFC8975B),
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
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF8A857C))),
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
          color: selected ? DailyPalette.goldSurface : DailyPalette.paper,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? DailyPalette.gold : DailyPalette.line,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (selected) ...[
              const Icon(Icons.check, size: 16, color: Color(0xFFC8975B)),
              const SizedBox(width: 4),
            ],
            Text(label,
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: const Color(0xFF2C2A26),
                )),
          ],
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return SizedBox(
      width: double.infinity,
      height: 60,
      child: ElevatedButton.icon(
        onPressed: _saving ? null : _add,
        icon: const Icon(Icons.add, size: 22),
        label: Text(_saving ? '저장 중...' : '+ 기록 추가',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: DailyPalette.gold,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
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
        // 명시적 connection state 처리
        final waiting = snap.connectionState == ConnectionState.waiting;
        final hasError = snap.hasError;
        final allDocs = snap.data?.docs ?? [];
        // method 필드 있는 docs만 (이전 schema 무시)
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF8A857C))),
                const Spacer(),
                Text('총 ${docs.length}건',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8A857C))),
              ],
            ),
            const SizedBox(height: 10),
            if (waiting)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(40),
                color: DailyPalette.paper,
                alignment: Alignment.center,
                child: const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (hasError)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                color: DailyPalette.paper,
                child: Text('오류: ${snap.error}',
                    style: const TextStyle(color: Color(0xFFB05A5A))),
              )
            else if (docs.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                decoration: BoxDecoration(
                  color: DailyPalette.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DailyPalette.line),
                ),
                child: const Column(
                  children: [
                    Icon(Icons.inbox_outlined, size: 40, color: Color(0xFFE8E2D4)),
                    SizedBox(height: 10),
                    Text('아직 기록 없음',
                        style: TextStyle(fontSize: 15, color: Color(0xFF8A857C), fontWeight: FontWeight.w500)),
                    SizedBox(height: 4),
                    Text('위 + 기록 추가 버튼으로 등재',
                        style: TextStyle(fontSize: 12, color: Color(0xFFB8B2A6))),
                  ],
                ),
              )
            else
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: DailyPalette.paper,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: DailyPalette.line),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < docs.length; i++) ...[
                      _recordRow(docs[i]),
                      if (i < docs.length - 1)
                        Container(height: 1, color: DailyPalette.line),
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
    final ts = d['ts'] as Timestamp?;
    final timeStr = ts != null ? DateFormat('MM/dd HH:mm').format(ts.toDate()) : '-';
    final method = d['method']?.toString() ?? '?';
    return Container(
      color: DailyPalette.paper,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 36,
            decoration: BoxDecoration(
              color: DailyPalette.goldSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(method,
                style: TextStyle(
                  color: DailyPalette.gold,
                  fontWeight: FontWeight.w800,
                  fontSize: method.length > 2 ? 11 : 14,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(timeStr,
                style: const TextStyle(fontSize: 14, color: Color(0xFF2C2A26))),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF8A857C)),
            onPressed: () => doc.reference.delete(),
          ),
        ],
      ),
    );
  }
}
