part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 부곡도서관 좌석 현황 카드 + 선호 좌석 확인
/// ═══════════════════════════════════════════════════
extension _HomeLibraryCard on _HomeScreenState {

  Future<void> _loadLibrary() async {
    final r = await LibraryService().fetch();
    await LibraryService().getFavSeats(); // 선호 좌석 미리 로드
    _safeSetState(() => _libraryRoom = r);
  }

  Widget _libraryCard() {
    final r = _libraryRoom;
    final dk = _dk;

    if (r == null) {
      return GestureDetector(
        onTap: _loadLibrary,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BotanicalDeco.card(dk),
          child: Row(children: [
            const Text('📚', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('부곡도서관', style: BotanicalTypo.body(
                size: 14, weight: FontWeight.w700, color: _textMain)),
              const SizedBox(height: 2),
              Text('탭하여 좌석 현황 불러오기', style: BotanicalTypo.label(
                size: 11, color: _textMuted)),
            ])),
            Icon(Icons.refresh_rounded, size: 18, color: _textMuted),
          ]),
        ),
      );
    }

    final pct = r.total > 0 ? r.used / r.total : 0.0;
    final statusColor = r.available <= 0
        ? const Color(0xFFEF4444)
        : r.available <= 5
            ? const Color(0xFFF59E0B)
            : const Color(0xFF10B981);
    final statusLabel = r.available <= 0
        ? '만석'
        : r.available <= 5
            ? '거의 만석'
            : '여유';
    final timeLabel =
        '${r.fetchedAt.hour.toString().padLeft(2, '0')}:${r.fetchedAt.minute.toString().padLeft(2, '0')} 기준';

    // 선호 좌석 상태
    final favStatuses = LibraryService().getFavSeatStatuses();

    return GestureDetector(
      onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => const LibrarySeatMapScreen()))
        .then((_) => _loadLibrary()),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BotanicalDeco.card(dk),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header row
          Row(children: [
            const Text('📚', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('부곡도서관 일반열람실', style: BotanicalTypo.body(
                size: 13, weight: FontWeight.w700, color: _textMain)),
              const SizedBox(height: 2),
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(dk ? 0.15 : 0.10),
                    borderRadius: BorderRadius.circular(6)),
                  child: Text(statusLabel, style: TextStyle(
                    fontSize: 9, fontWeight: FontWeight.w800, color: statusColor)),
                ),
                if (r.waiting > 0) ...[
                  const SizedBox(width: 6),
                  Text('대기 ${r.waiting}명', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: Colors.orange)),
                ],
              ]),
            ])),
            // Circular gauge
            SizedBox(width: 44, height: 44,
              child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(
                  value: pct,
                  strokeWidth: 3.5,
                  backgroundColor: dk ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation(statusColor.withOpacity(0.7)),
                ),
                Text('${(pct * 100).toInt()}%', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w800, color: statusColor,
                  fontFeatures: const [FontFeature.tabularFigures()])),
              ])),
          ]),
          const SizedBox(height: 12),
          // Big number row
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
            Text('${r.available}', style: TextStyle(
              fontSize: 32, fontWeight: FontWeight.w900, color: statusColor,
              fontFamily: 'monospace', fontFeatures: const [FontFeature.tabularFigures()])),
            const SizedBox(width: 4),
            Text('석 남음', style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: _textSub)),
            const Spacer(),
            Text('${r.used} / ${r.total}', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _textMuted,
              fontFeatures: const [FontFeature.tabularFigures()])),
          ]),

          // ═══ 선호 좌석 상태 ═══
          if (favStatuses.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: dk ? Colors.white.withOpacity(0.04) : const Color(0xFFF8F7F5),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: dk ? Colors.white.withOpacity(0.08) : const Color(0xFFEEE9E2)),
              ),
              child: Row(children: [
                Icon(Icons.star_rounded, size: 14,
                  color: dk ? const Color(0xFFFBBF24) : const Color(0xFFD97706)),
                const SizedBox(width: 6),
                Text('내 자리', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: dk ? Colors.white.withOpacity(0.5) : const Color(0xFF94A3B8))),
                const SizedBox(width: 10),
                Expanded(child: Wrap(spacing: 6, runSpacing: 4, children:
                  favStatuses.entries.map((e) {
                    final isAvail = e.value == SeatStatus.available;
                    final c = isAvail ? const Color(0xFF10B981) : const Color(0xFFEF4444);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.withOpacity(dk ? 0.15 : 0.10),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.withOpacity(0.3)),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text('${e.key}번', style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w800, color: c)),
                        const SizedBox(width: 4),
                        Icon(isAvail ? Icons.check_circle_rounded : Icons.cancel_rounded,
                          size: 12, color: c),
                      ]),
                    );
                  }).toList(),
                )),
              ]),
            ),
          ],

          const SizedBox(height: 8),
          // Footer
          Row(children: [
            Text(timeLabel, style: TextStyle(fontSize: 9, color: _textMuted.withOpacity(0.6))),
            const Spacer(),
            // 선호 좌석 설정 버튼
            GestureDetector(
              onTap: () => _showFavSeatDialog(),
              child: Row(children: [
                Icon(Icons.star_outline_rounded, size: 12, color: _textMuted),
                const SizedBox(width: 2),
                Text('좌석설정', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted)),
              ]),
            ),
            const SizedBox(width: 12),
            Row(children: [
              Text('좌석 배치도', style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted)),
              Icon(Icons.chevron_right_rounded, size: 14, color: _textMuted),
            ]),
          ]),
        ]),
      ),
    );
  }

  /// 선호 좌석 설정 다이얼로그
  Future<void> _showFavSeatDialog() async {
    final lib = LibraryService();
    final current = await lib.getFavSeats();
    final controller = TextEditingController(text: current.join(', '));

    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('선호 좌석 설정', style: BotanicalTypo.heading(size: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('자주 앉는 좌석 번호를 입력하세요\n(쉼표로 구분, 최대 5개)',
            style: TextStyle(fontSize: 12, color: _textMuted)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '예: 42, 43, 55',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text('취소', style: TextStyle(color: _textMuted))),
          TextButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('저장')),
        ],
      ),
    );

    if (result != null) {
      final seats = result
          .split(RegExp(r'[,\s]+'))
          .map((s) => int.tryParse(s.trim()))
          .where((n) => n != null && n > 0)
          .cast<int>()
          .take(5)
          .toList();
      await lib.setFavSeats(seats);
      _safeSetState(() {}); // 리빌드
    }
  }
}
