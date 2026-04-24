part of 'calendar_screen.dart';

/// ═══════════════════════════════════════════════════
/// CALENDAR — 선택 날짜 상세 (일상 기록)
/// ═══════════════════════════════════════════════════
extension _CalendarDayDetail on _CalendarScreenState {
  // ══════════════════════════════════════════
  //  선택된 날짜 상세 카드
  // ══════════════════════════════════════════

  Widget _buildSelectedDayCard() {
    String dateLabel;
    try {
      dateLabel = DateFormat('M월 d일 (E)', 'ko').format(_selectedDate);
    } catch (_) {
      const labels = ['일', '월', '화', '수', '목', '금', '토'];
      dateLabel = '${_selectedDate.month}월 ${_selectedDate.day}일 (${labels[_selectedDate.weekday % 7]})';
    }
    final now = DateTime.now();
    final diff = _selectedDate.difference(DateTime(now.year, now.month, now.day)).inDays;
    final diffLabel = diff == 0 ? '오늘' : diff > 0 ? 'D-$diff' : 'D+${-diff}';
    final memos = _selectedMemos;
    final journals = _journalsForDate(_selectedDateStr);

    final isEmpty = memos.isEmpty && journals.isEmpty
        && _selectedTimeRecord == null;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border.withValues(alpha: 0.15)),
        boxShadow: _dk ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // 날짜 헤더
        Row(children: [
          Text(dateLabel, style: TextStyle(
            fontSize: 16, fontWeight: FontWeight.w800, color: _textMain)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: diff == 0 ? _accent.withValues(alpha: 0.1) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8)),
            child: Text(diffLabel, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w800,
              color: diff == 0 ? _accent : _textMuted))),
          const SizedBox(width: 6),
          // 쉬는날 토글
          GestureDetector(
            onTap: () async {
              final ds = _selectedDateStr;
              final isNowRest = await _fb.toggleRestDay(ds);
              if (isNowRest) { _restDays.add(ds); } else { _restDays.remove(ds); }
              _safeSetState(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _restDays.contains(_selectedDateStr)
                    ? const Color(0xFF64748B).withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _restDays.contains(_selectedDateStr)
                    ? const Color(0xFF64748B).withValues(alpha: 0.3) : _border.withValues(alpha: 0.3))),
              child: Text(
                _restDays.contains(_selectedDateStr) ? '😴 쉬는날' : '😴',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: _restDays.contains(_selectedDateStr)
                      ? const Color(0xFF64748B) : _textMuted))),
          ),
        ]),

        // ── 시간 기록 ──
        if (_selectedTimeRecord != null) ...[
          const SizedBox(height: 12),
          _buildTimeRecordRow(),
        ],

        // ── 메모 ──
        if (memos.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionLabel('💡', '메모'),
          const SizedBox(height: 6),
          ...memos.map(_memoTile),
        ],

        // ── 저널 ──
        if (journals.isNotEmpty) ...[
          const SizedBox(height: 14),
          _sectionLabel('📝', '저널'),
          const SizedBox(height: 6),
          ...journals.map(_journalTile),
        ],

        if (isEmpty) ...[
          const SizedBox(height: 20),
          Center(child: Column(children: [
            const Text('📭', style: TextStyle(fontSize: 28)),
            const SizedBox(height: 6),
            Text('기록이 없습니다', style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w600, color: _textMuted)),
          ])),
          const SizedBox(height: 12),
        ],
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  시간 기록 행 (기상/취침/외출/식사)
  // ══════════════════════════════════════════

  Widget _buildTimeRecordRow() {
    final tr = _selectedTimeRecord!;
    final fields = <_TRField>[
      if (tr.wake != null) _TRField('🌅', '기상', 'wake', tr.wake),
      if (tr.outing != null) _TRField('🚶', '외출', 'outing', tr.outing),
      if (tr.returnHome != null) _TRField('🏠', '귀가', 'returnHome', tr.returnHome),
      if (tr.bedTime != null) _TRField('🌙', '취침', 'bedTime', tr.bedTime),
    ];
    if (fields.isEmpty) return const SizedBox.shrink();

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionLabel('⏰', '시간 기록'),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: fields.map((f) =>
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border.withValues(alpha: 0.1))),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(f.emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Text(f.label, style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted)),
            const SizedBox(width: 4),
            Text(f.value ?? '-', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: _textMain)),
          ]),
        )).toList()),
    ]);
  }

  // ══════════════════════════════════════════
  //  공통 헬퍼
  // ══════════════════════════════════════════

  Widget _sectionLabel(String emoji, String label) {
    return Row(children: [
      Text(emoji, style: const TextStyle(fontSize: 14)),
      const SizedBox(width: 6),
      Text(label, style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w700, color: _textMain)),
    ]);
  }

  Widget _memoTile(String memo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.15))),
      child: Text(memo, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w500, color: _textMain, height: 1.4)),
    );
  }

  Widget _journalTile(Map<String, dynamic> journal) {
    final title = journal['title'] as String? ?? '';
    final body = journal['body'] as String? ?? '';
    final mood = journal['mood'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (mood != null) ...[
            Text(mood, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 6),
          ],
          Expanded(child: Text(title, style: TextStyle(
            fontSize: 13, fontWeight: FontWeight.w700, color: _textMain))),
        ]),
        if (body.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(body, style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w500, color: _textSub, height: 1.4),
            maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ]),
    );
  }
}
