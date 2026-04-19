part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 수면 교정 카드 (WB 10주 위상전진 프로토콜 v3)
/// - SleepProtocol.today 로 오늘 DayTarget 산출
/// - 기상/취침 실측 + CoreTask 체크 + 블로커/트러블/PMID 서브시트
/// - Firestore: today.sleepLog.{yyyy-MM-dd} dual-write → history/{yyyy-MM}.days.{dd}.sleepLog
/// ═══════════════════════════════════════════════════
extension _HomeSleepCard on _HomeScreenState {

  // ── 오늘자 sleepLog 맵 (tasks 포함). null-safe 뷰 ──
  Map<String, dynamic> get _todaySleepLog {
    final d = _studyDate();
    final e = _sleepLog[d];
    if (e is Map) return Map<String, dynamic>.from(e);
    return <String, dynamic>{};
  }

  Map<String, dynamic> get _todaySleepTasks {
    final t = _todaySleepLog['tasks'];
    if (t is Map) return Map<String, dynamic>.from(t);
    return <String, dynamic>{};
  }

  // ── Firestore dual-write ──
  Future<void> _writeSleepLog(Map<String, dynamic> patch) async {
    final d = _studyDate();
    final current = _todaySleepLog;
    final merged = {...current, ...patch};

    _safeSetState(() {
      _sleepLog = {..._sleepLog, d: merged};
    });

    final fb = FirebaseService();
    try {
      // today doc: sleepLog.{date} 통째로 merge (updateTodayField는 dot-path 지원)
      await fb.updateTodayField('sleepLog.$d', merged);

      // history dual-write
      final month = d.substring(0, 7);
      final day = d.substring(8, 10);
      await FirebaseFirestore.instance
          .doc('users/$kUid/history/$month')
          .set({
            'days': {day: {'sleepLog': merged}},
          }, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
      fb.invalidateStudyCache();
    } catch (e) {
      debugPrint('[Sleep] writeSleepLog fail: $e');
    }
  }

  Future<void> _toggleSleepTask(String id, bool v) async {
    final tasks = _todaySleepTasks;
    tasks[id] = v;
    await _writeSleepLog({'tasks': tasks});
  }

  // ── 시간 입력 시트 (TimePicker) ──
  Future<void> _editSleepTime({required bool wake}) async {
    final target = _sleepProto?.today;
    if (target == null) return;

    final current = wake
        ? (_todaySleepLog['actualWake'] as String?)
        : (_todaySleepLog['actualSleep'] as String?);
    TimeOfDay initial;
    if (current != null && current.contains(':')) {
      final p = current.split(':');
      initial = TimeOfDay(
        hour: int.tryParse(p[0]) ?? 0,
        minute: int.tryParse(p[1]) ?? 0,
      );
    } else {
      initial = wake ? target.wakeTarget : target.sleepTarget;
    }

    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (ctx, child) {
        return MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox(),
        );
      },
    );
    if (picked == null) return;

    final actualStr = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';
    final diff = _signedDeltaMin(
      actualStr,
      wake ? target.wakeTarget : target.sleepTarget,
    );

    await _writeSleepLog({
      if (wake) 'actualWake': actualStr else 'actualSleep': actualStr,
      if (wake) 'diffWakeMin': diff else 'diffSleepMin': diff,
    });
  }

  // 목표 대비 실측 분 차이. 양수 = 늦음, 음수 = 이름.
  // wake 기준: 타겟 07:00, 실측 07:30 -> +30. 자정 경계는 ±12h 안쪽으로 정규화.
  int _signedDeltaMin(String actual, TimeOfDay target) {
    final p = actual.split(':');
    final aMin = (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
    final tMin = target.hour * 60 + target.minute;
    var diff = aMin - tMin;
    if (diff > 12 * 60) diff -= 24 * 60;
    if (diff < -12 * 60) diff += 24 * 60;
    return diff;
  }

  String _fmtSignedMin(int m) {
    final sign = m > 0 ? '+' : (m < 0 ? '-' : '±');
    return '$sign${m.abs()}m';
  }

  String _fmtTod(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  // ── 메인 카드 ──
  Widget _sleepCard() {
    final proto = _sleepProto;
    if (proto == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _dk ? BotanicalColors.cardDark : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(children: [
          Icon(Icons.bedtime_outlined, size: 16, color: _textMuted),
          const SizedBox(width: 8),
          Text('수면 프로토콜 로딩 중', style: TextStyle(
              fontSize: 12, color: _textMuted)),
        ]),
      );
    }

    final target = proto.today;
    final log = _todaySleepLog;
    final tasks = _todaySleepTasks;
    final doneCount = target.coreTasks.where((t) => tasks[t.id] == true).length;
    final totalCount = target.coreTasks.length;
    final progress = totalCount == 0 ? 0.0 : doneCount / totalCount;

    final maxShiftDays = (_shiftTotalMinutes(proto) /
            SleepProtocol.shiftMinPerDay)
        .ceil();
    final focusLeft = target.phase == SleepPhase.focus
        ? (maxShiftDays - target.dayNumber).clamp(0, maxShiftDays)
        : 0;

    final phaseLabel = target.phase == SleepPhase.focus ? 'focus' : 'maintain';
    final indigo = _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: _dk ? BotanicalColors.cardDark : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
              color: (_dk ? Colors.black : Colors.blueGrey)
                  .withValues(alpha: _dk ? 0.2 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── 헤더 ──
        Row(children: [
          Icon(Icons.bedtime_outlined, size: 16, color: indigo),
          const SizedBox(width: 6),
          Text(
            '수면 교정 D${target.dayNumber.toString().padLeft(2, '0')}'
            ' · W${target.week}'
            ' · $phaseLabel',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w800, color: _textMain),
          ),
          const Spacer(),
          Text(
            target.phase == SleepPhase.focus
                ? '포커스 $focusLeft일 남음'
                : '유지',
            style: TextStyle(
                fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted),
          ),
        ]),

        // ── 주간 경고 배너 ──
        if (target.weeklyWarning != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: BotanicalColors.warning.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: BotanicalColors.warning.withValues(alpha: 0.3)),
            ),
            child: Row(children: [
              Icon(Icons.warning_amber_rounded,
                  size: 14, color: BotanicalColors.warning),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  target.weeklyWarning!,
                  style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                      color: _textSub),
                ),
              ),
            ]),
          ),
        ],

        // ── 오늘 목표 블록 ──
        const SizedBox(height: 12),
        _sleepTargetBlock(target, log),

        // ── 실제 입력 행 ──
        const SizedBox(height: 10),
        _sleepActualRow(target, log),

        // ── 체크리스트 ──
        const SizedBox(height: 14),
        Row(children: [
          Text('오늘 과제',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: _textMuted)),
          const Spacer(),
          Text('$doneCount/$totalCount',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _textSub)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 3,
            backgroundColor: _dk
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.04),
            valueColor: AlwaysStoppedAnimation(indigo),
          ),
        ),
        const SizedBox(height: 8),
        ...target.coreTasks.map((t) => _taskRow(t, tasks[t.id] == true)),

        // ── 활성 블로커 ──
        if (target.activeBlockers.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('활성 블로커',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: _textMuted)),
          const SizedBox(height: 6),
          ...target.activeBlockers.map(_blockerTile),
        ],

        // ── 하단 버튼 행 ──
        const SizedBox(height: 10),
        Row(children: [
          TextButton.icon(
            onPressed: _openTroubleSheet,
            icon: Icon(Icons.healing_outlined, size: 14, color: indigo),
            label: Text('문제 발생?',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: indigo)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: _openPmidSheet,
            icon: Icon(Icons.menu_book_outlined, size: 13, color: _textMuted),
            label: Text('근거',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _textMuted)),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              minimumSize: const Size(0, 28),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ]),
      ]),
    );
  }

  // 베이스라인 → 골 총 전진 분
  int _shiftTotalMinutes(SleepProtocol p) {
    final b = p.baselineWake.hour * 60 + p.baselineWake.minute;
    final g = p.goalWake.hour * 60 + p.goalWake.minute;
    var d = b - g;
    if (d <= 0) d += 24 * 60;
    return d;
  }

  // ── 목표 블록 (큰 숫자 2개) ──
  Widget _sleepTargetBlock(DayTarget t, Map<String, dynamic> log) {
    final totalShift = _sleepProto != null
        ? _shiftTotalMinutes(_sleepProto!)
        : 0;
    final shiftMin = t.cumulativeShift.inMinutes;
    final arrow = shiftMin > 0 ? '←' : '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: _dk
            ? Colors.white.withValues(alpha: 0.04)
            : BotanicalColors.primarySurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: _targetCell(
              icon: '☀️',
              label: '기상 목표',
              value: _fmtTod(t.wakeTarget),
            ),
          ),
          Container(
              width: 1,
              height: 36,
              color: _border.withValues(alpha: 0.5)),
          Expanded(
            child: _targetCell(
              icon: '🌙',
              label: '취침 목표',
              value: _fmtTod(t.sleepTarget),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Text('$arrow ${shiftMin}m shifted',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _textSub)),
          const SizedBox(width: 6),
          Text('/ ${totalShift}m goal',
              style: TextStyle(fontSize: 10, color: _textMuted)),
        ]),
      ]),
    );
  }

  Widget _targetCell({
    required String icon,
    required String label,
    required String value,
  }) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(icon, style: const TextStyle(fontSize: 11)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _textMuted)),
      ]),
      const SizedBox(height: 2),
      Text(value,
          style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: _textMain)),
    ]);
  }

  // ── 실측 입력 행 ──
  Widget _sleepActualRow(DayTarget t, Map<String, dynamic> log) {
    final wake = log['actualWake'] as String?;
    final sleep = log['actualSleep'] as String?;
    final diffWake = log['diffWakeMin'];
    final diffSleep = log['diffSleepMin'];

    return Row(children: [
      Expanded(
        child: _actualChip(
          label: '실제 기상',
          value: wake,
          diff: diffWake is num ? diffWake.toInt() : null,
          onTap: () => _editSleepTime(wake: true),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _actualChip(
          label: '실제 취침',
          value: sleep,
          diff: diffSleep is num ? diffSleep.toInt() : null,
          onTap: () => _editSleepTime(wake: false),
        ),
      ),
    ]);
  }

  Widget _actualChip({
    required String label,
    required String? value,
    required int? diff,
    required VoidCallback onTap,
  }) {
    final hasVal = value != null && value.isNotEmpty;
    final diffColor = diff == null
        ? _textMuted
        : (diff.abs() <= 15
            ? BotanicalColors.success
            : (diff.abs() <= 30
                ? BotanicalColors.warning
                : BotanicalColors.error));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: _dk
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.black.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border.withValues(alpha: 0.5)),
        ),
        child: Row(children: [
          Icon(Icons.edit_outlined, size: 12, color: _textMuted),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _textMuted)),
                  const SizedBox(height: 2),
                  Row(children: [
                    Text(
                      hasVal ? value : '--:--',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: hasVal ? _textMain : _textMuted),
                    ),
                    if (diff != null) ...[
                      const SizedBox(width: 6),
                      Text(_fmtSignedMin(diff),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: diffColor)),
                    ],
                  ]),
                ]),
          ),
        ]),
      ),
    );
  }

  // ── 체크리스트 행 ──
  Widget _taskRow(CoreTask task, bool done) {
    final tierLabel = switch (task.tier) {
      Tier.tier1 => 'T1',
      Tier.tier2 => 'T2',
      Tier.tier3 => 'T3',
    };
    final tierWeight = switch (task.tier) {
      Tier.tier1 => FontWeight.w800,
      Tier.tier2 => FontWeight.w600,
      Tier.tier3 => FontWeight.w500,
    };
    final tierAlpha = switch (task.tier) {
      Tier.tier1 => 1.0,
      Tier.tier2 => 0.85,
      Tier.tier3 => 0.55,
    };

    return InkWell(
      onTap: () => _toggleSleepTask(task.id, !done),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(
            done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            size: 18,
            color: done
                ? BotanicalColors.success
                : _textMuted.withValues(alpha: 0.5),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: (task.tier == Tier.tier1
                      ? BotanicalColors.primary
                      : _textMuted)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(tierLabel,
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: task.tier == Tier.tier1
                        ? BotanicalColors.primary
                        : _textSub)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.label,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: tierWeight,
                color: (done ? _textMuted : _textMain)
                    .withValues(alpha: done ? 0.6 : tierAlpha),
                decoration: done ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
        ]),
      ),
    );
  }

  // ── 블로커 타일 (접힘) ──
  Widget _blockerTile(BlockerInfo b) {
    // v3 강조: #1(폰 책상 거치대) + #3(침대 위 폰 금지)
    final highlighted = b.index == 1 || b.index == 3;
    final indigo = _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: highlighted
            ? indigo.withValues(alpha: 0.07)
            : (_dk
                ? Colors.white.withValues(alpha: 0.02)
                : Colors.black.withValues(alpha: 0.015)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: highlighted
                ? indigo.withValues(alpha: 0.3)
                : _border.withValues(alpha: 0.4)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          childrenPadding:
              const EdgeInsets.fromLTRB(12, 0, 12, 10),
          dense: true,
          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
          leading: Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: highlighted
                  ? indigo
                  : _textMuted.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('#${b.index}',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: highlighted ? Colors.white : _textSub)),
          ),
          title: Text(
            b.title,
            style: TextStyle(
                fontSize: 12,
                fontWeight:
                    highlighted ? FontWeight.w800 : FontWeight.w600,
                color: _textMain),
          ),
          iconColor: _textMuted,
          collapsedIconColor: _textMuted,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                b.body,
                style: TextStyle(
                    fontSize: 11, height: 1.4, color: _textSub),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: BotanicalColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '해결: ${b.solution}',
                style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    fontWeight: FontWeight.w600,
                    color: _textSub),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 트러블 진단 시트 ──
  void _openTroubleSheet() {
    final proto = _sleepProto;
    if (proto == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SubSheetContainer(
        dk: _dk,
        title: '트러블 진단',
        subtitle: '증상을 선택하면 복구 프로토콜이 펼쳐진다',
        children: proto.troubles
            .map((t) => _troubleTile(ctx, t))
            .toList(),
      ),
    );
  }

  Widget _troubleTile(BuildContext ctx, TroubleTrigger t) {
    final tierColor = t.tier == Tier.tier1
        ? BotanicalColors.error
        : BotanicalColors.warning;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _dk
            ? BotanicalColors.surfaceDark.withValues(alpha: 0.3)
            : BotanicalColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border.withValues(alpha: 0.5)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        title: Row(children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(t.tier == Tier.tier1 ? 'T1' : 'T2',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: tierColor)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(t.pattern,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _textMain)),
          ),
        ]),
        iconColor: _textMuted,
        collapsedIconColor: _textMuted,
        children: [
          _troubleRow('신호', t.signal),
          const SizedBox(height: 6),
          _troubleRow('복구', t.recovery, emphasize: true),
        ],
      ),
    );
  }

  Widget _troubleRow(String label, String body, {bool emphasize = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: emphasize
            ? BotanicalColors.success.withValues(alpha: 0.07)
            : (_dk
                ? Colors.white.withValues(alpha: 0.03)
                : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: _textMuted)),
        const SizedBox(height: 2),
        Text(body,
            style: TextStyle(
                fontSize: 12, height: 1.4, color: _textSub)),
      ]),
    );
  }

  // ── PMID 근거 시트 ──
  void _openPmidSheet() {
    final proto = _sleepProto;
    if (proto == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SubSheetContainer(
        dk: _dk,
        title: '근거 문헌',
        subtitle: '탭하면 PMID 를 클립보드로 복사한다',
        children: proto.references.map((r) => _pmidTile(ctx, r)).toList(),
      ),
    );
  }

  Widget _pmidTile(BuildContext ctx, PmidRef r) {
    final tierColor = r.tier == Tier.tier1
        ? BotanicalColors.primary
        : BotanicalColors.gold;
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: 'PMID:${r.pmid}'));
        if (ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
            content: Text('PMID:${r.pmid} 복사됨'),
            duration: const Duration(seconds: 2),
          ));
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _dk
              ? BotanicalColors.surfaceDark.withValues(alpha: 0.3)
              : BotanicalColors.surfaceLight,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(r.tier == Tier.tier1 ? 'T1' : 'T2',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: tierColor)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(r.title,
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: _textMain)),
                  const SizedBox(height: 3),
                  Text('PMID ${r.pmid}'
                      '${r.pmcId.isNotEmpty ? " · ${r.pmcId}" : ""}',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _textMuted)),
                ]),
          ),
          Icon(Icons.copy_rounded, size: 14, color: _textMuted),
        ]),
      ),
    );
  }
}

/// 공용 서브시트 컨테이너 (handle + 제목 + children).
class _SubSheetContainer extends StatelessWidget {
  final bool dk;
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _SubSheetContainer({
    required this.dk,
    required this.title,
    this.subtitle,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final pad = mq.viewInsets.bottom > 0
        ? mq.viewInsets.bottom
        : mq.viewPadding.bottom;
    return Container(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.8),
      decoration: BoxDecoration(
        color: dk ? BotanicalColors.cardDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(16, 0, 16, pad + 16),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          margin: const EdgeInsets.only(top: 10, bottom: 12),
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: (dk
                    ? BotanicalColors.textMutedDark
                    : BotanicalColors.textHint)
                .withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Row(children: [
          Text(title,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: dk
                      ? BotanicalColors.textMainDark
                      : BotanicalColors.textMain)),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(Icons.close_rounded,
                size: 18,
                color: dk
                    ? BotanicalColors.textMutedDark
                    : BotanicalColors.textMuted),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ]),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(subtitle!,
                style: TextStyle(
                    fontSize: 11,
                    color: dk
                        ? BotanicalColors.textMutedDark
                        : BotanicalColors.textMuted)),
          ),
        ],
        const SizedBox(height: 12),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: children,
          ),
        ),
      ]),
    );
  }
}
