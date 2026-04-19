part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 루틴 스트립 (컴팩트 1줄)
/// ═══════════════════════════════════════════════════
extension _HomeRoutineCard on _HomeScreenState {

  Widget _routineStatusCard() {
    final hasWake = _wake != null;
    final isOut = _outing != null && _returnHome == null;
    final hasReturn = _outing != null && _returnHome != null;
    final hasBed = _bedTime != null;
    final hasMeal = _todayMeals.isNotEmpty || _day.isMealing;

    final items = <_RItem>[
      _RItem('☀️', '기상', hasWake, _wake, BotanicalColors.gold,
        live: false,
        onTap: () => _editTimeField('wake', '기상', _wake)),
      // ★ 홈데이: 외출 없이 2시간+ → 홈데이 표시
      _isHomeDay && !isOut && !hasReturn
        ? _RItem('🏡', '홈데이', true, null, const Color(0xFF5B7ABF),
            onTap: () => _editTimeField('outing', '외출', _outing))
        : _RItem(isOut ? '🚶' : '🏠', '외출', isOut || hasReturn,
            isOut ? _outing : _returnHome, const Color(0xFF3B8A6B),
            live: isOut,
            onTap: () => _editTimeField('outing', '외출', _outing)),
      _RItem('🍽️', '식사', hasMeal, null, const Color(0xFFFF8A65)),
      _RItem('🌙', '취침', hasBed, _bedTime, const Color(0xFF6B5DAF),
        onTap: () => _editTimeField('bedTime', '취침', _bedTime)),
    ];
    final done = items.where((i) => i.active).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: _dk
            ? [BotanicalColors.cardDark, const Color(0xFF1A2332)]
            : [Colors.white, const Color(0xFFFAFBFF)]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: (_dk ? Colors.black : Colors.blueGrey).withValues(alpha: _dk ? 0.2 : 0.06),
            blurRadius: 12, offset: const Offset(0, 3)),
        ]),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // ── 아이콘 스트립 ──
        Row(children: [
          ...items.map((i) => Expanded(child: _routineChip(i))),
          GestureDetector(
            onTap: () => _editTimeField('wake', '기상', _wake),
            child: Icon(Icons.tune_rounded, size: 14, color: _textMuted.withValues(alpha: 0.3))),
        ]),
        // ── 프로그레스 ──
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: done / items.length, minHeight: 2.5,
              backgroundColor: _dk ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
              valueColor: AlwaysStoppedAnimation(BotanicalColors.primary)))),
          const SizedBox(width: 8),
          if (_sleepDurationLabel != null) ...[
            Text('😴$_sleepDurationLabel', style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w600,
              color: BotanicalColors.primaryMuted)),
            const SizedBox(width: 4),
          ],
          Text('$done/${items.length}', style: TextStyle(
            fontSize: 9, fontWeight: FontWeight.w700, color: _textMuted)),
        ]),
      ]),
    );
  }

  Widget _routineChip(_RItem i) {
    return GestureDetector(
      onTap: i.onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 아이콘 원
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: i.active ? LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [
                i.color.withValues(alpha: _dk ? 0.18 : 0.12),
                i.color.withValues(alpha: _dk ? 0.06 : 0.04),
              ]) : null,
            color: i.active ? null
              : (_dk ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
            border: Border.all(
              color: i.active ? i.color.withValues(alpha: 0.35) : Colors.transparent, width: 1.5),
            boxShadow: i.active ? [
              BoxShadow(color: i.color.withValues(alpha: 0.15), blurRadius: 8, spreadRadius: 1),
            ] : null),
          child: Stack(alignment: Alignment.center, children: [
            Text(i.emoji, style: TextStyle(fontSize: i.active ? 16 : 14)),
            if (i.live) Positioned(right: 0, top: 0,
              child: Container(width: 7, height: 7,
                decoration: BoxDecoration(color: i.color, shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: i.color.withValues(alpha: 0.5), blurRadius: 4)]))),
          ]),
        ),
        const SizedBox(height: 3),
        // 시간 or 라벨
        Text(
          i.time ?? i.label,
          style: TextStyle(
            fontSize: i.time != null ? 9 : 8,
            fontWeight: i.active ? FontWeight.w700 : FontWeight.w500,
            color: i.active ? (_dk ? Colors.white70 : i.color) : _textMuted.withValues(alpha: 0.5)),
          maxLines: 1, overflow: TextOverflow.clip,
        ),
      ]),
    );
  }

  Future<void> _editTimeField(String field, String label, String? current) async {
    // TODO: getTimeRecords/updateTimeRecord removed with firebase_study_part.dart
    // StatusEditorSheet needs TimeRecord — pass null for now
    if (!mounted) return;

    final result = await showModalBottomSheet<TimeRecord>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatusEditorSheet(existing: null, dk: _dk, highlightField: field),
    );
    if (result == null) return;

    if (result.outing != null && result.returnHome == null) {
      _day.forceOutState(true);
    } else {
      _day.forceOutState(false);
    }
    _safeSetState(() {
      _wake = result.wake;
      _outing = result.outing;
      _returnHome = result.returnHome;
      _bedTime = result.bedTime;
      _mealStart = result.mealStart;
      _mealEnd = result.mealEnd;
      if (result.meals.isNotEmpty) _todayMeals = result.meals;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('저장됨'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

}

/// 루틴 아이템 데이터
class _RItem {
  final String emoji, label;
  final bool active;
  final String? time;
  final Color color;
  final bool live;
  final String? sub;
  final VoidCallback? onTap;
  const _RItem(this.emoji, this.label, this.active, this.time, this.color,
    {this.live = false, this.sub, this.onTap});
}
