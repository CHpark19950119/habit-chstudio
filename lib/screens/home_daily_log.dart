part of 'home_screen.dart';

/// ═══════════════════════════════════════════════════
/// HOME — 데일리 로그 블록 타임라인
/// ═══════════════════════════════════════════════════
extension _HomeDailyLog on _HomeScreenState {
  // ══════════════════════════════════════════
  //  데일리 로그 — 블록 프로그레스 바 (비율 기반)
  //  Premium animated block segments
  // ══════════════════════════════════════════

  Widget _locationSummaryCard() {
    final segments = <_DaySegment>[];

    // ★ B2/B4 FIX: 모든 이벤트를 시간순으로 수집한 뒤 정렬
    // 하루는 기상~취침까지만 표시 (수면시간은 별도 통계)

    // 1) 이벤트 수집 (시간이 있는 것만)
    final events = <({String time, String type})>[];
    if (_wake != null) events.add((time: _wake!, type: 'wake'));
    if (_outing != null) events.add((time: _outing!, type: 'outing'));
    // ★ v9: 다회 식사 이벤트 (meals가 있으면 레거시 무시)
    if (_todayMeals.isNotEmpty) {
      for (int i = 0; i < _todayMeals.length; i++) {
        final m = _todayMeals[i];
        events.add((time: m.start, type: 'meal_${i}_start'));
        if (m.end != null) events.add((time: m.end!, type: 'meal_${i}_end'));
      }
    } else {
      if (_mealStart != null) events.add((time: _mealStart!, type: 'mealStart'));
      if (_mealEnd != null) events.add((time: _mealEnd!, type: 'mealEnd'));
    }
    if (_returnHome != null) events.add((time: _returnHome!, type: 'returnHome'));
    if (_bedTime != null) events.add((time: _bedTime!, type: 'bedTime'));

    // 시간순 정렬 (자정 넘김 처리: 04:00 이전은 +24h)
    int safeMin(String t) {
      final m = _toMin(t);
      return m < 240 ? m + 1440 : m; // 04:00 이전은 다음날로 간주
    }
    events.sort((a, b) => safeMin(a.time).compareTo(safeMin(b.time)));

    // 2) ★ #8 FIX: 이벤트 순서대로 세그먼트 생성 (시간 수정 시 올바른 위치에 배치)
    // 모든 이벤트를 시작/종료 페어로 변환하여 시간순 분포

    Color _colorFor(String label) {
      switch (label) {
        case '준비': return const Color(0xFFF59E0B);
        case '재택': return const Color(0xFF5B7ABF);
        case '이동': return const Color(0xFF3B8A6B);
        case '체류': return const Color(0xFF8B5CF6);
        case '공부': return const Color(0xFF6366F1);
        case '휴식': return const Color(0xFF94A3B8);
        case '식사': return const Color(0xFFFF8A65);
        case '자유': return const Color(0xFF94A3B8);
        case '취침': return const Color(0xFF6B5DAF);
        default: return const Color(0xFF94A3B8);
      }
    }

    String _emojiFor(String label) {
      switch (label) {
        case '준비': return '🌅';
        case '재택': return '🏠';
        case '이동': return '🚶';
        case '체류': return '📍';
        case '공부': return '📖';
        case '휴식': return '☕';
        case '식사': return '🍽️';
        case '자유': return '🏠';
        case '취침': return '🛏️';
        default: return '📍';
      }
    }
    
    // 연속 이벤트 페어로 세그먼트 생성
    for (int i = 0; i < events.length; i++) {
      final curr = events[i];
      final String segEnd;
      
      if (i + 1 < events.length) {
        segEnd = events[i + 1].time;
      } else if (curr.type == 'bedTime') {
        // 취침은 시점 마커
        segments.add(_DaySegment(
          start: curr.time, end: curr.time,
          label: '취침', emoji: '🛏️', color: const Color(0xFF6B5DAF),
          startEvent: 'bedTime'));
        continue;
      } else {
        segEnd = _fmt24Now();
      }
      
      // 시작과 종료가 같으면 스킵
      if (curr.time == segEnd) continue;
      
      // 이벤트 타입에 따라 세그먼트 라벨 결정
      String label;
      final nextType = i + 1 < events.length ? events[i + 1].type : '';
      switch (curr.type) {
        case 'wake':
          if (nextType == 'outing') { label = _isHomeDay ? '재택' : '준비'; }
          else if (nextType.isEmpty) {
            // 마지막 세그먼트 (현재까지) → 홈데이 우선, 상태 기반
            if (_isHomeDay) { label = '재택'; }
            else if (_day.isOut) { label = '이동'; }
            else { label = '자유'; }
          } else if (nextType == 'studyStart' || nextType.startsWith('focus_')) {
            label = _isHomeDay ? '재택' : '준비';
          } else if (_isHomeDay) { label = '재택'; }
          else { label = '자유'; }
          break;
        case 'outing': label = '이동'; break;
        case 'studyStart':
          // 공부시작 → 다음이 포커스면 휴식(대기), 아니면 휴식
          label = nextType.startsWith('focus_') && nextType.endsWith('_start') ? '휴식' : '휴식';
          break;
        case 'studyEnd':
          label = nextType == 'returnHome' ? '이동' : '자유';
          break;
        case 'mealStart': label = '식사'; break;
        case 'mealEnd':
          // 식사종료 → 다음이 포커스면 휴식, 아니면 자유
          label = nextType.startsWith('focus_') ? '휴식' :
                  nextType == 'studyEnd' || nextType == 'returnHome' ? '휴식' : '자유';
          break;
        case 'returnHome': label = '자유'; break;
        case 'bedTime': label = '취침'; break;
        default:
          if (curr.type.startsWith('focus_') && curr.type.endsWith('_start')) {
            // 포커스 시작 → 공부
            label = '공부';
          } else if (curr.type.startsWith('focus_') && curr.type.endsWith('_end')) {
            // 포커스 종료 → 다음 포커스까지 휴식, 아니면 휴식/자유
            label = nextType.startsWith('focus_') || nextType == 'studyEnd' ? '휴식' :
                    nextType.startsWith('meal_') || nextType == 'mealStart' ? '식사' : '자유';
          }
          // meal_N_start, meal_N_end
          else if (curr.type.endsWith('_start')) { label = '식사'; }
          else if (curr.type.endsWith('_end')) {
            label = nextType.startsWith('focus_') ? '휴식' :
                    nextType == 'studyEnd' ? '휴식' : '자유';
          }
          else { label = '자유'; }
      }
      
      segments.add(_DaySegment(
        start: curr.time, end: segEnd,
        label: label, emoji: _emojiFor(label), color: _colorFor(label),
        startEvent: curr.type));
    }

    // ★ B4 FIX: 세그먼트를 시작 시간순으로 최종 정렬
    segments.sort((a, b) => safeMin(a.start).compareTo(safeMin(b.start)));

    // 중복/겹침 제거: 동일 시작시간 세그먼트 중 라벨이 같은 것 제거
    final seen = <String>{};
    segments.removeWhere((seg) {
      final key = '${seg.start}_${seg.label}';
      if (seen.contains(key)) return true;
      seen.add(key);
      return false;
    });

    // ── Activity Recognition: "이동" 세그먼트 → 이동/체류 세분화 (5분 이상만) ──
    final actTransitions = _day.activityTransitions;
    if (actTransitions.isNotEmpty) {
      final refined = <_DaySegment>[];
      for (final seg in segments) {
        if (seg.label != '이동') {
          refined.add(seg);
          continue;
        }
        final segStartMin = safeMin(seg.start);
        final segEndMin = safeMin(seg.end);

        // 이 세그먼트 시간대의 activity transitions
        final relevant = actTransitions.where((t) {
          final m = safeMin(t['time'] ?? '00:00');
          return m > segStartMin && m < segEndMin;
        }).toList()
          ..sort((a, b) =>
              safeMin(a['time']!).compareTo(safeMin(b['time']!)));

        if (relevant.isEmpty) {
          final before = actTransitions.where((t) =>
              safeMin(t['time']!) <= segStartMin).toList();
          if (before.isNotEmpty) {
            before.sort((a, b) =>
                safeMin(a['time']!).compareTo(safeMin(b['time']!)));
            if (before.last['type'] == 'still') {
              refined.add(_DaySegment(
                start: seg.start, end: seg.end,
                label: '체류', emoji: '📍',
                color: const Color(0xFF8B5CF6)));
              continue;
            }
          }
          refined.add(seg);
          continue;
        }

        // 세그먼트 시작 전 마지막 transition → 초기 상태
        String curType = 'moving';
        final before = actTransitions.where((t) =>
            safeMin(t['time']!) <= segStartMin).toList();
        if (before.isNotEmpty) {
          before.sort((a, b) =>
              safeMin(a['time']!).compareTo(safeMin(b['time']!)));
          curType = before.last['type'] ?? 'moving';
        }

        // 원시 sub-segments 생성
        final raw = <_DaySegment>[];
        String cursor = seg.start;
        for (final t in relevant) {
          final tTime = t['time']!;
          if (cursor != tTime && safeMin(cursor) < safeMin(tTime)) {
            final label = curType == 'still' ? '체류' : '이동';
            raw.add(_DaySegment(
              start: cursor, end: tTime,
              label: label, emoji: _emojiFor(label),
              color: _colorFor(label)));
          }
          cursor = tTime;
          curType = t['type'] ?? 'moving';
        }
        if (safeMin(cursor) < segEndMin) {
          final label = curType == 'still' ? '체류' : '이동';
          raw.add(_DaySegment(
            start: cursor, end: seg.end,
            label: label, emoji: _emojiFor(label),
            color: _colorFor(label)));
        }

        // ★ 5분 미만 세그먼트를 인접 세그먼트에 병합
        final merged = <_DaySegment>[];
        for (final r in raw) {
          final dur = safeMin(r.end) - safeMin(r.start);
          if (dur < 5 && merged.isNotEmpty) {
            // 짧은 세그먼트 → 이전 세그먼트에 흡수
            final prev = merged.removeLast();
            merged.add(_DaySegment(
              start: prev.start, end: r.end,
              label: prev.label, emoji: prev.emoji,
              color: prev.color));
          } else if (dur < 5 && merged.isEmpty) {
            // 첫 세그먼트가 짧으면 일단 추가 (다음에서 병합)
            merged.add(r);
          } else {
            // 충분히 긴 세그먼트
            if (merged.isNotEmpty && merged.last.label == r.label) {
              // 같은 라벨이면 합치기
              final prev = merged.removeLast();
              merged.add(_DaySegment(
                start: prev.start, end: r.end,
                label: prev.label, emoji: prev.emoji,
                color: prev.color));
            } else {
              merged.add(r);
            }
          }
        }
        refined.addAll(merged.isNotEmpty ? merged : [seg]);
      }
      segments
        ..clear()
        ..addAll(refined);
    }

    if (segments.isEmpty) return const SizedBox.shrink();

    // 각 세그먼트 duration 계산 (자정 넘김 보정)
    final durations = segments.map((seg) {
      final s = safeMin(seg.start);
      final e = seg.end == seg.start ? s + 1 : safeMin(seg.end);
      return (e - s).clamp(0, 1440);
    }).toList();
    final totalDur = durations.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border.withValues(alpha: 0.12)),
        boxShadow: _dk ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── 헤더 ──
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                const Color(0xFF6366F1).withValues(alpha: 0.15),
                const Color(0xFF8B5CF6).withValues(alpha: 0.08)]),
              borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.timeline_rounded, size: 14, color: Color(0xFF6366F1))),
          const SizedBox(width: 8),
          Text('데일리 로그', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w800, color: _textMain)),
          const Spacer(),
          // ── 수정 버튼 ──
          GestureDetector(
            onTap: () => _editTimeField('', '데일리 로그', null),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withValues(alpha: _dk ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.edit_rounded, size: 11, color: const Color(0xFF6366F1).withValues(alpha: 0.7)),
                const SizedBox(width: 3),
                Text('수정', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                  color: const Color(0xFF6366F1).withValues(alpha: 0.7))),
              ]),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: _dk ? 0.1 : 0.06),
              borderRadius: BorderRadius.circular(8)),
            child: Text('${segments.first.start} ~ ${_fmt24Now()}',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                color: _accent, fontFeatures: const [FontFeature.tabularFigures()]))),
        ]),
        const SizedBox(height: 12),

        // ── ★ E: 무드 셀렉터 ──
        _moodSelector(),
        const SizedBox(height: 14),

        // ── ★ E: 순공 미니 링 + 통계 ──
        _compactStatsRow(),
        const SizedBox(height: 14),

        // ── 블록 프로그레스 바 (비율 기반) ──
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (ctx, animVal, _) {
            return Column(children: [
              // 시간 마커 (시작, 끝)
              Row(children: [
                Text(segments.first.start,
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: _textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
                const Spacer(),
                Text(_fmt24Now(),
                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                    color: _accent, fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              const SizedBox(height: 4),
              // 메인 블록 바
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 28,
                  child: Row(
                    children: List.generate(segments.length, (i) {
                      final ratio = totalDur > 0 ? durations[i] / totalDur : 1.0 / segments.length;
                      final seg = segments[i];
                      // 애니메이션: 좌→우로 순차 등장
                      final segStart = i / segments.length;
                      final segProgress = ((animVal - segStart) / (1.0 - segStart)).clamp(0.0, 1.0);
                      return Expanded(
                        flex: (ratio * 1000).round().clamp(1, 1000),
                        child: Opacity(
                          opacity: segProgress,
                          child: Container(
                            margin: EdgeInsets.only(
                              left: i == 0 ? 0 : 1.5,
                              right: i == segments.length - 1 ? 0 : 1.5),
                            decoration: BoxDecoration(
                              color: seg.color.withValues(alpha: _dk ? 0.75 : 0.85),
                              borderRadius: BorderRadius.horizontal(
                                left: i == 0 ? const Radius.circular(12) : Radius.zero,
                                right: i == segments.length - 1 ? const Radius.circular(12) : Radius.zero),
                              boxShadow: [BoxShadow(
                                color: seg.color.withValues(alpha: 0.2),
                                blurRadius: 4, offset: const Offset(0, 2))]),
                            child: Center(child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                child: Text(seg.emoji,
                                  style: const TextStyle(fontSize: 13)))))),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ]);
          },
        ),
        const SizedBox(height: 14),

        // ── 디테일 리스트 ──
        ...List.generate(segments.length, (i) {
          final seg = segments[i];
          final dur = durations[i];
          final durStr = dur >= 60
            ? '${dur ~/ 60}시간${dur % 60 > 0 ? " ${dur % 60}분" : ""}'
            : '${dur}분';
          final pct = totalDur > 0 ? (dur / totalDur * 100).round() : 0;

          return TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: 500 + i * 80),
            curve: Curves.easeOutCubic,
            builder: (ctx, val, child) {
              return Opacity(
                opacity: val,
                child: Transform.translate(
                  offset: Offset(0, 12 * (1 - val)),
                  child: child),
              );
            },
            child: GestureDetector(
              onTap: seg.startEvent != null ? () => _editSegmentTime(seg) : null,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  // 색상 바
                  Container(width: 3, height: 36,
                    decoration: BoxDecoration(
                      color: seg.color, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 10),
                  // 이모지
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: seg.color.withValues(alpha: _dk ? 0.1 : 0.08),
                      borderRadius: BorderRadius.circular(8)),
                    child: Center(child: Text(seg.emoji, style: const TextStyle(fontSize: 14)))),
                  const SizedBox(width: 8),
                  // 활동명 + 시간
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(seg.label, style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: _textMain)),
                      Text('${seg.start} → ${seg.end == seg.start ? seg.start : seg.end}',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500,
                          color: _textMuted, fontFeatures: const [FontFeature.tabularFigures()])),
                    ],
                  )),
                  // 비율 + 시간 뱃지
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: seg.color.withValues(alpha: _dk ? 0.1 : 0.08),
                        borderRadius: BorderRadius.circular(8)),
                      child: Text(durStr, style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w800, color: seg.color,
                        fontFeatures: const [FontFeature.tabularFigures()]))),
                    const SizedBox(height: 2),
                    Text('$pct%', style: TextStyle(
                      fontSize: 9, fontWeight: FontWeight.w600,
                      color: _textMuted.withValues(alpha: 0.7))),
                  ]),
                  // 편집 아이콘
                  if (seg.startEvent != null) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.edit_rounded, size: 12,
                      color: _textMuted.withValues(alpha: 0.3)),
                  ],
                ]),
              ),
            ),
          );
        }),

        // ── 시간 집계 요약 ──
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _dk ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            ...(() {
              // 카테고리별 합산
              final catMin = <String, int>{};
              for (int i = 0; i < segments.length; i++) {
                final key = segments[i].label;
                catMin[key] = (catMin[key] ?? 0) + durations[i];
              }
              // 이동, 공부, 자유 순서로 표시
              final display = <MapEntry<String, int>>[];
              for (final k in ['공부', '휴식', '이동', '체류', '자유', '준비', '재택', '식사']) {
                if (catMin.containsKey(k)) display.add(MapEntry(k, catMin[k]!));
              }
              if (display.isEmpty) return <Widget>[];
              return display.asMap().entries.map((entry) {
                final e = entry.value;
                final emoji = e.key == '공부' ? '📖' : e.key == '휴식' ? '☕' : e.key == '이동' ? '🚶' : e.key == '체류' ? '📍' : e.key == '자유' ? '🏠' : e.key == '준비' ? '🌅' : e.key == '재택' ? '🏠' : e.key == '식사' ? '🍽️' : '📍';
                final h = e.value ~/ 60; final m = e.value % 60;
                final timeStr = h > 0 ? '${h}h${m > 0 ? " ${m}m" : ""}' : '${m}m';
                return Expanded(child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(emoji, style: const TextStyle(fontSize: 11)),
                  const SizedBox(width: 4),
                  Text(timeStr, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: _textMain,
                    fontFeatures: const [FontFeature.tabularFigures()])),
                ]));
              }).toList();
            })(),
          ]),
        ),

        // ── ★ E: 메모 섹션 (항상 표시 — 입력 포함) ──
        const SizedBox(height: 14),
        _memoSection(),

        // ── ★ E: 한 줄 요약 ──
        const SizedBox(height: 12),
        _oneLinerSummary(),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ★ E: 무드 셀렉터
  // ══════════════════════════════════════════
  Widget _moodSelector() {
    const moods = ['😊', '😐', '😔', '🔥', '😴'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: moods.map((emoji) {
        final selected = _mood == emoji;
        return GestureDetector(
          onTap: () async {
            final newMood = _mood == emoji ? null : emoji;
            _safeSetState(() => _mood = newMood);
            final fb = FirebaseService();
            await fb.updateTodayField('mood', newMood ?? '');
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: selected
                ? _accent.withValues(alpha: _dk ? 0.2 : 0.12)
                : _dk ? Colors.white.withValues(alpha: 0.04) : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? _accent.withValues(alpha: 0.5) : Colors.transparent,
                width: 1.5),
            ),
            child: Center(child: Text(emoji,
              style: TextStyle(fontSize: selected ? 22 : 18))),
          ),
        );
      }).toList(),
    );
  }

  // ══════════════════════════════════════════
  //  ★ E: 순공 미니 링 + 통계
  // ══════════════════════════════════════════
  Widget _compactStatsRow() {
    // TODO: study time tracking removed — show placeholder until new system
    const goalMin = 8 * 60; // 8시간 목표
    const effMin = 0;
    final pct = (effMin / goalMin).clamp(0.0, 1.0);
    const effH = 0;
    const effM = 0;
    final effStr = effH > 0
      ? '${effH}h${effM > 0 ? " ${effM}m" : ""}'
      : '${effM}m';
    final pctStr = '${(pct * 100).round()}%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.03) : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        // 미니 순공 링
        SizedBox(
          width: 56, height: 56,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 50, height: 50,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: pct),
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeOutCubic,
                builder: (_, val, __) => CircularProgressIndicator(
                  value: val,
                  strokeWidth: 4.5,
                  strokeCap: StrokeCap.round,
                  backgroundColor: _dk
                    ? Colors.white.withValues(alpha: 0.06)
                    : Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(_accent),
                ),
              ),
            ),
            Text(pctStr, style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800,
              color: _accent,
              fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        ),
        const SizedBox(width: 14),
        // 통계 그리드
        Expanded(child: Column(children: [
          Row(children: [
            _miniStat('기상', _wake ?? '--:--'),
            _miniStat('순공', effStr),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            _miniStat('달성', pctStr),
            _miniStat('취침', _bedTime ?? '--:--'),
          ]),
        ])),
      ]),
    );
  }

  Widget _miniStat(String label, String value) {
    return Expanded(child: Row(children: [
      Text('$label ', style: TextStyle(
        fontSize: 10, fontWeight: FontWeight.w600,
        color: _textMuted)),
      Text(value, style: TextStyle(
        fontSize: 12, fontWeight: FontWeight.w800,
        color: _textMain,
        fontFeatures: const [FontFeature.tabularFigures()])),
    ]));
  }

  // ══════════════════════════════════════════
  //  ★ E: 메모 섹션 (기존 + 입력 필드)
  // ══════════════════════════════════════════
  Widget _memoSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB07D3A).withValues(alpha: 0.1))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('📝', style: TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Text('메모', style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w700, color: _textMain)),
          const Spacer(),
          if (_dailyMemos.isNotEmpty)
            Text('${_dailyMemos.length}개', style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: _textMuted)),
        ]),
        if (_dailyMemos.isNotEmpty) ...[
          const SizedBox(height: 8),
          ..._dailyMemos.asMap().entries.map((entry) {
            final idx = entry.key;
            final memo = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Container(
                    width: 4, height: 4,
                    decoration: BoxDecoration(
                      color: memo.startsWith('📌')
                        ? const Color(0xFFB07D3A)
                        : _textMuted.withValues(alpha: 0.4),
                      shape: BoxShape.circle)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(memo, style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w500,
                  color: _textSub, height: 1.4))),
                GestureDetector(
                  onTap: () async {
                    final updated = List<String>.from(_dailyMemos)..removeAt(idx);
                    _safeSetState(() => _dailyMemos = updated);
                    await FirebaseService().updateTodayField('dailyMemos', updated);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 12,
                      color: _textMuted.withValues(alpha: 0.4)))),
              ]),
            );
          }),
        ],
        const SizedBox(height: 8),
        // ── 메모 입력 필드 ──
        _MemoInputField(
          dk: _dk,
          textMuted: _textMuted,
          accent: _accent,
          onSubmit: (text) async {
            final updated = List<String>.from(_dailyMemos)..add(text);
            _safeSetState(() => _dailyMemos = updated);
            await FirebaseService().updateTodayField('dailyMemos', updated);
          },
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  ★ E: 한 줄 요약
  // ══════════════════════════════════════════
  Widget _oneLinerSummary() {
    final wakeStr = _wake ?? '--:--';
    // TODO: study time tracking removed — show placeholder
    const effStr = '0m';

    // D-Day 계산 (목표일이 있으면 사용, 없으면 비표시)
    String dDayStr = '';
    try {
      final goals = _orderData?.goals ?? [];
      final activeGoals = goals.where((g) =>
        !g.isCompleted && g.deadline != null && g.deadline!.isNotEmpty).toList();
      if (activeGoals.isNotEmpty) {
        activeGoals.sort((a, b) => a.deadline!.compareTo(b.deadline!));
        final nearest = activeGoals.first;
        final deadline = DateFormat('yyyy-MM-dd').parse(nearest.deadline!);
        final diff = deadline.difference(DateTime.now()).inDays;
        dDayStr = ' · D-$diff';
      }
    } catch (_) {}

    return Center(
      child: Text(
        '기상 $wakeStr · 순공 $effStr$dDayStr',
        style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w600,
          color: _textMuted,
          fontFeatures: const [FontFeature.tabularFigures()],
          letterSpacing: -0.2),
      ),
    );
  }

  /// ★ 세그먼트 탭 → 시간 편집
  Future<void> _editSegmentTime(_DaySegment seg) async {
    if (seg.startEvent == null) return;

    int hour = 8, minute = 0;
    if (seg.start.contains(':')) {
      final parts = seg.start.split(':');
      hour = int.tryParse(parts[0]) ?? 8;
      minute = int.tryParse(parts[1]) ?? 0;
    }
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!),
    );
    if (picked == null || !mounted) return;

    final newTime = '${picked.hour.toString().padLeft(2, '0')}:'
        '${picked.minute.toString().padLeft(2, '0')}';

    // TODO: getTimeRecords/updateTimeRecord removed with firebase_study_part.dart
    // Segment time editing needs reimplementation with new data layer
    final evt = seg.startEvent!;
    switch (evt) {
      case 'wake':
      case 'outing':
      case 'returnHome':
      case 'bedTime':
        break;
      default: return;
    }

    _safeSetState(() {
      switch (evt) {
        case 'wake': _wake = newTime; break;
        case 'outing': _outing = newTime; break;
        case 'returnHome': _returnHome = newTime; break;
        case 'bedTime': _bedTime = newTime; break;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${seg.label} → $newTime'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating));
    }
  }

  String _fmt24Now() => DateFormat('HH:mm').format(DateTime.now());

  String _isoToHhmm(String t) {
    if (t.contains('T')) {
      try {
        final dt = DateTime.parse(t);
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    return t;
  }

  int _toMin(String hhmm) {
    try {
      // ISO 8601 형식 처리 (2026-02-24T12:30:00.000)
      if (hhmm.contains('T')) {
        final dt = DateTime.parse(hhmm);
        return dt.hour * 60 + dt.minute;
      }
      final p = hhmm.split(':');
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    } catch (_) { return 0; }
  }

}

/// ★ E: 메모 입력 StatefulWidget (TextField 상태 격리)
class _MemoInputField extends StatefulWidget {
  final bool dk;
  final Color textMuted;
  final Color accent;
  final Future<void> Function(String text) onSubmit;
  const _MemoInputField({
    required this.dk, required this.textMuted,
    required this.accent, required this.onSubmit});
  @override
  State<_MemoInputField> createState() => _MemoInputFieldState();
}

class _MemoInputFieldState extends State<_MemoInputField> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onSubmit(text);
      _ctrl.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: _ctrl,
          style: TextStyle(
            fontSize: 12,
            color: widget.dk ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A)),
          decoration: InputDecoration(
            hintText: '메모 추가...',
            hintStyle: TextStyle(
              fontSize: 12, color: widget.textMuted.withValues(alpha: 0.5)),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            filled: true,
            fillColor: widget.dk
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: widget.textMuted.withValues(alpha: 0.15))),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: widget.textMuted.withValues(alpha: 0.15))),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: widget.accent.withValues(alpha: 0.5))),
          ),
          textInputAction: TextInputAction.send,
          onSubmitted: (_) => _submit(),
        ),
      ),
      const SizedBox(width: 8),
      GestureDetector(
        onTap: _submit,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: widget.accent.withValues(alpha: widget.dk ? 0.15 : 0.1),
            borderRadius: BorderRadius.circular(8)),
          child: Icon(
            _sending ? Icons.hourglass_empty_rounded : Icons.add_rounded,
            size: 16, color: widget.accent),
        ),
      ),
    ]);
  }
}