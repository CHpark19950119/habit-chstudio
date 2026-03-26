part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 루틴 스트립 (컴팩트 1줄)
/// ═══════════════════════════════════════════════════
extension _HomeRoutineCard on _HomeScreenState {

  Widget _nfcStatusCard() {
    final hasWake = _wake != null;
    final hasStudy = _studyStart != null;
    final isOut = _outing != null && _returnHome == null;
    final hasReturn = _outing != null && _returnHome != null;
    final hasBed = _bedTime != null;
    final hasMeal = _todayMeals.isNotEmpty || _nfc.isMealing;

    final items = <_RItem>[
      _RItem('☀️', '기상', hasWake, _wake, BotanicalColors.gold,
        live: false,
        onTap: () => _editTimeField('wake', '기상', _wake)),
      _RItem('📖', '공부', hasStudy, _studyStart, BotanicalColors.primary,
        live: _ft.isRunning || (hasStudy && _studyEnd == null),
        sub: _studyEnd,
        onTap: () => _editTimeField('study', '공부', _studyStart)),
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
        color: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border.withValues(alpha: _dk ? 0.15 : 0.6))),
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
      onLongPress: i.onLong,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // 아이콘 원
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: i.active
              ? i.color.withValues(alpha: _dk ? 0.12 : 0.08)
              : (_dk ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
            border: Border.all(
              color: i.active ? i.color.withValues(alpha: 0.3) : Colors.transparent, width: 1.5)),
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

  // ── 외출/귀가 토글 ──
  Future<void> _toggleOuting() async {
    final d = _studyDate();
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final fb = FirebaseService();
    final records = await fb.getTimeRecords();
    final existing = records[d];

    if (_outing == null || (_outing != null && _returnHome != null)) {
      await fb.updateTimeRecord(d, TimeRecord(
        date: d, wake: existing?.wake,
        study: existing?.study, studyEnd: existing?.studyEnd,
        outing: timeStr, returnHome: null,
        arrival: existing?.arrival, bedTime: existing?.bedTime,
        mealStart: existing?.mealStart, mealEnd: existing?.mealEnd,
        meals: existing?.meals,
      ));
      _nfc.forceOutState(true);
      _safeSetState(() { _outing = timeStr; _returnHome = null; _outingMinutes = null; });
    } else if (_outing != null && _returnHome == null) {
      await fb.updateTimeRecord(d, TimeRecord(
        date: d, wake: existing?.wake,
        study: existing?.study, studyEnd: existing?.studyEnd,
        outing: existing?.outing, returnHome: timeStr,
        arrival: existing?.arrival, bedTime: existing?.bedTime,
        mealStart: existing?.mealStart, mealEnd: existing?.mealEnd,
        meals: existing?.meals,
      ));
      _nfc.forceOutState(false);
      final outMin = TimeRecord(date: d, outing: _outing, returnHome: timeStr).outingMinutes;
      _safeSetState(() { _returnHome = timeStr; _outingMinutes = outMin; });
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) await _load();
      if (now.hour >= 22 && mounted) _showDayEndDialog(d);
    }
  }

  Future<void> _showDayEndDialog(String dateStr) async {
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('🌙 하루 마무리', style: BotanicalTypo.heading(size: 18, weight: FontWeight.w800)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('오늘 하루 수고하셨습니다.\n공부를 종료하고 하루를 마무리할까요?',
            style: TextStyle(fontSize: 14, color: _textSub, height: 1.5)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: BotanicalColors.primary.withValues(alpha: _dk ? 0.08 : 0.04),
              borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              Text('📚', style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Text('순공 ${_effMin ~/ 60}h ${_effMin % 60}m',
                style: BotanicalTypo.label(size: 14, weight: FontWeight.w800, color: BotanicalColors.primary)),
            ]),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false),
            child: Text('아직', style: TextStyle(color: _textMuted))),
          ElevatedButton(
            onPressed: () => Navigator.pop(c, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D5F2D),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('마무리', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final now = DateTime.now();
      final endStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      final fb = FirebaseService();
      final records = await fb.getTimeRecords();
      final existing = records[dateStr];
      if (existing != null && existing.studyEnd == null) {
        await fb.updateTimeRecord(dateStr, TimeRecord(
          date: dateStr, wake: existing.wake,
          study: existing.study, studyEnd: endStr,
          outing: existing.outing, returnHome: existing.returnHome,
          arrival: existing.arrival, bedTime: existing.bedTime,
          mealStart: existing.mealStart, mealEnd: existing.mealEnd,
          meals: existing.meals,
        ));
      }
      _load();
    }
  }

  int _calcOutingElapsed() {
    if (_outing == null) return 0;
    try {
      final p = _outing!.split(':');
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day, int.parse(p[0]), int.parse(p[1]));
      return now.difference(start).inMinutes.clamp(0, 1440);
    } catch (_) { return 0; }
  }

  Future<void> _editTimeField(String field, String label, String? current) async {
    final d = _studyDate();
    final fb = FirebaseService();
    final records = await fb.getTimeRecords();
    final existing = records[d];
    if (!mounted) return;

    final result = await showModalBottomSheet<TimeRecord>(
      context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
      builder: (ctx) => StatusEditorSheet(existing: existing, dk: _dk, highlightField: field),
    );
    if (result == null) return;

    final updated = TimeRecord(
      date: d, wake: result.wake, study: result.study,
      studyEnd: result.studyEnd, outing: result.outing,
      returnHome: result.returnHome,
      arrival: result.arrival ?? existing?.arrival,
      bedTime: result.bedTime,
      mealStart: result.mealStart, mealEnd: result.mealEnd,
      meals: result.meals,
    );
    await fb.updateTimeRecord(d, updated);
    if (updated.outing != null && updated.returnHome == null) {
      _nfc.forceOutState(true);
    } else {
      _nfc.forceOutState(false);
    }
    if (updated.study != null && updated.studyEnd == null) {
      _nfc.forceStudyState(true);
    } else {
      _nfc.forceStudyState(false);
    }
    _safeSetState(() {
      _wake = updated.wake;
      _studyStart = updated.study;
      _studyEnd = updated.studyEnd;
      _outing = updated.outing;
      _returnHome = updated.returnHome;
      _bedTime = updated.bedTime;
      _mealStart = updated.mealStart;
      _mealEnd = updated.mealEnd;
      if (updated.meals != null) _todayMeals = updated.meals!;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('저장됨'),
        duration: const Duration(seconds: 2),
      ));
    }
  }

  String _fmt12h(String? hhmm) {
    if (hhmm == null || !hhmm.contains(':')) return '--:--';
    try {
      final p = hhmm.split(':');
      final h = int.parse(p[0]); final m = p[1];
      final prefix = h < 12 ? '오전' : '오후';
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return '$prefix $h12:$m';
    } catch (_) { return hhmm; }
  }

  Widget _pulseDot(Color c) => Container(width: 8, height: 8,
    decoration: BoxDecoration(color: c, shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6, spreadRadius: 1)]));

  Future<void> _quickWake() async {
    await WakeService().recordWake();
    await _load();
  }

  /// 공부 시작/종료 토글
  Future<void> _quickStudy() async {
    final d = _studyDate();
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final fb = FirebaseService();
    final records = await fb.getTimeRecords();
    final ex = records[d];

    if (_studyStart != null && _studyEnd == null) {
      // 공부 종료
      await fb.updateTimeRecord(d, TimeRecord(
        date: d, wake: ex?.wake, study: ex?.study, studyEnd: timeStr,
        outing: ex?.outing, returnHome: ex?.returnHome,
        arrival: ex?.arrival, bedTime: ex?.bedTime,
        mealStart: ex?.mealStart, mealEnd: ex?.mealEnd, meals: ex?.meals));
      _nfc.forceStudyState(false);
      _safeSetState(() => _studyEnd = timeStr);
    } else {
      // 공부 시작 (기상 안했으면 자동 기상)
      if (_wake == null) await WakeService().recordWake();
      await fb.updateTimeRecord(d, TimeRecord(
        date: d, wake: ex?.wake ?? timeStr, study: timeStr, studyEnd: null,
        outing: ex?.outing, returnHome: ex?.returnHome,
        arrival: ex?.arrival, bedTime: ex?.bedTime,
        mealStart: ex?.mealStart, mealEnd: ex?.mealEnd, meals: ex?.meals));
      _nfc.forceStudyState(true);
      _safeSetState(() { _studyStart = timeStr; _studyEnd = null; if (_wake == null) _wake = timeStr; });
    }
  }

  /// 식사 토글 (NFC 서비스 위임 — 다회 식사 로직)
  Future<void> _quickMeal() async {
    await _nfc.manualTestRole(ActionType.meal);
    await _load();
  }

  /// 취침 기록
  Future<void> _quickSleep() async {
    final d = _studyDate();
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final fb = FirebaseService();
    final records = await fb.getTimeRecords();
    final ex = records[d];

    // 공부 중이면 자동 종료
    final studyEnd = (ex?.study != null && ex?.studyEnd == null) ? timeStr : ex?.studyEnd;

    await fb.updateTimeRecord(d, TimeRecord(
      date: d, wake: ex?.wake, study: ex?.study, studyEnd: studyEnd,
      outing: ex?.outing, returnHome: ex?.returnHome,
      arrival: ex?.arrival, bedTime: timeStr,
      mealStart: ex?.mealStart, mealEnd: ex?.mealEnd, meals: ex?.meals));

    if (ex?.study != null && ex?.studyEnd == null) _nfc.forceStudyState(false);
    _safeSetState(() {
      _bedTime = timeStr;
      if (_studyStart != null && _studyEnd == null) _studyEnd = timeStr;
    });
  }

  // ═══════════════════════════════════════════════════
  // IoT Presence 카드 — mmWave 센서 실시간 상태
  // ═══════════════════════════════════════════════════

  Widget _presenceCard() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.doc(kIotDoc).snapshots(),
      builder: (ctx, snap) {
        String emoji = '📡', label = '센서 연결 대기';
        Color color = _textMuted;
        int? dist;
        String? timerStr;

        if (snap.hasData && snap.data!.exists) {
          final data = snap.data!.data() as Map<String, dynamic>? ?? {};
          final presence = data['presence'] as Map<String, dynamic>?;
          final config = data['config'] as Map<String, dynamic>?;
          // ★ configurable 임계값 (Firestore iot.config.bedThresholdCm, 기본 220)
          final bedThreshold = (config?['bedThresholdCm'] as num?)?.toInt() ?? 220;
          if (presence != null) {
            final state = presence['state'] as String? ?? 'unknown';
            // ★ 필터된 거리 우선, fallback raw distance
            final filtRaw = presence['filteredDistance'];
            final rawDist = presence['distance'];
            final filtDist = filtRaw is num ? filtRaw.toInt() : null;
            dist = rawDist is int ? rawDist : (rawDist is num ? rawDist.toInt() : null);
            final zoneDist = filtDist ?? dist;
            final since = presence['stationarySince'];

            switch (state) {
              case 'peaceful':
                final isBed = zoneDist != null && zoneDist <= bedThreshold;
                emoji = isBed ? '🛏️' : '🪑';
                label = isBed ? '침대' : '책상';
                color = isBed ? const Color(0xFF6B5DAF) : BotanicalColors.primary;
                break;
              case 'presence':
                emoji = '🚶';
                label = '움직임';
                color = const Color(0xFFE8A735);
                break;
              case 'none':
                emoji = '🚫';
                label = '비어있음';
                color = _textMuted;
                break;
              default:
                emoji = '📡';
                label = state;
                color = _textMuted;
            }

            if (since != null && since is Timestamp && state == 'peaceful'
                && zoneDist != null && zoneDist <= bedThreshold) {
              final elapsed = DateTime.now().difference(since.toDate());
              final min = elapsed.inMinutes;
              timerStr = min < 60 ? '${min}분째' : '${min ~/ 60}h ${min % 60}m째';
            }
          }
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _dk ? BotanicalColors.cardDark : BotanicalColors.cardLight,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border.withValues(alpha: _dk ? 0.15 : 0.6))),
          child: Row(children: [
            Text(emoji, style: const TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: color)),
            if (dist != null) ...[
              const SizedBox(width: 6),
              Text('${dist}cm', style: TextStyle(
                fontSize: 10, color: _textMuted)),
            ],
            if (timerStr != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4)),
                child: Text(timerStr, style: TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w700, color: color))),
            ],
            const Spacer(),
            Icon(Icons.sensors_rounded, size: 14, color: _textMuted.withValues(alpha: 0.2)),
          ]),
        );
      },
    );
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
  final VoidCallback? onLong;
  const _RItem(this.emoji, this.label, this.active, this.time, this.color,
    {this.live = false, this.sub, this.onTap, this.onLong});
}
