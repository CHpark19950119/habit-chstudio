// Sleep Protocol v3 data layer.
//
// Source: C:\dev\workbook\output\research\sleep_protocol_v3.html (2026-04-18 15:52)
// v3 changes reflected here:
//   - Blocker #1: phone on desk dock (not living room) + paper book reading.
//     Weekly ladder W1 30min / W2 1h / W3 1.5h / W4 2h.
//   - Blocker #3: no phone on bed.
//   - D1 04:00 timeline: phone dock + paper book (yellow lamp only).
//
// Protocol arc (task contract):
//   - Day 1 = 2026-04-18. Baseline wake 15:00, baseline sleep 07:00.
//   - Goal wake 07:00, goal sleep 23:00. 8h phase shift.
//   - Focus phase (weeks 1-4, days 1-28): daily -30min wake/sleep shift until
//     goal is reached (day 16 reaches 07:00/23:00), then clamp at goal.
//   - Maintain phase (weeks 5-10, days 29-70): fixed 07:00/23:00, +/-15min.
//
// No UI. Pure data + calculation. Firestore-serializable.

import 'package:flutter/material.dart' show TimeOfDay;

enum SleepPhase { focus, maintain }

enum Tier { tier1, tier2, tier3 }

// --------------------------------------------------------------------------
// PMID references (HTML footer + task contract §9 Tier1/Tier2).
// The HTML v3 footer cites three works; we treat them as Tier1 and add the
// Tier2 PRC/entrainment lineage commonly referenced in DSPS literature.
// --------------------------------------------------------------------------
class PmidRef {
  final String pmid;
  final String pmcId;
  final String title;
  final String url;
  final Tier tier;

  const PmidRef({
    required this.pmid,
    required this.pmcId,
    required this.title,
    required this.url,
    required this.tier,
  });

  Map<String, dynamic> toMap() => {
        'pmid': pmid,
        'pmcId': pmcId,
        'title': title,
        'url': url,
        'tier': tier.name,
      };

  factory PmidRef.fromMap(Map<String, dynamic> m) => PmidRef(
        pmid: m['pmid'] as String? ?? '',
        pmcId: m['pmcId'] as String? ?? '',
        title: m['title'] as String? ?? '',
        url: m['url'] as String? ?? '',
        tier: Tier.values.firstWhere(
          (t) => t.name == (m['tier'] as String? ?? 'tier1'),
          orElse: () => Tier.tier1,
        ),
      );
}

const List<PmidRef> _pmidLibrary = [
  // Tier 1 — AASM 2015 Clinical Practice Guideline (CRSWD)
  PmidRef(
    pmid: '26414986',
    pmcId: 'PMC4582061',
    title:
        'Clinical Practice Guideline for the Treatment of Intrinsic Circadian Rhythm Sleep-Wake Disorders (AASM 2015)',
    url: 'https://pubmed.ncbi.nlm.nih.gov/26414986/',
    tier: Tier.tier1,
  ),
  // Tier 1 — Lewy & Sack melatonin PRC
  PmidRef(
    pmid: '8746015',
    pmcId: '',
    title:
        'The dim light melatonin onset, melatonin assays and biological rhythm research in humans (Lewy & Sack 1996)',
    url: 'https://pubmed.ncbi.nlm.nih.gov/8746015/',
    tier: Tier.tier1,
  ),
  // Tier 1 — Czeisler bright light phase advance
  PmidRef(
    pmid: '3726555',
    pmcId: '',
    title:
        'Bright light resets the human circadian pacemaker independent of the timing of the sleep-wake cycle (Czeisler et al. 1986)',
    url: 'https://pubmed.ncbi.nlm.nih.gov/3726555/',
    tier: Tier.tier1,
  ),
  // Tier 2 — Morning bright light for DSPS
  PmidRef(
    pmid: '2188189',
    pmcId: '',
    title:
        'Phototherapy for delayed sleep phase syndrome (Rosenthal et al. 1990)',
    url: 'https://pubmed.ncbi.nlm.nih.gov/2188189/',
    tier: Tier.tier2,
  ),
  // Tier 2 — Low-dose melatonin
  PmidRef(
    pmid: '15763455',
    pmcId: '',
    title:
        'Meta-analysis: melatonin for the treatment of primary sleep disorders (Brzezinski et al. 2005)',
    url: 'https://pubmed.ncbi.nlm.nih.gov/15763455/',
    tier: Tier.tier2,
  ),
  // Tier 2 — Blue-light / screen suppression of melatonin
  PmidRef(
    pmid: '25535358',
    pmcId: 'PMC4313820',
    title:
        'Evening use of light-emitting eReaders negatively affects sleep, circadian timing, and next-morning alertness (Chang et al. 2015)',
    url: 'https://pubmed.ncbi.nlm.nih.gov/25535358/',
    tier: Tier.tier2,
  ),
];

// --------------------------------------------------------------------------
// Core daily tasks (HTML §4 checklist master).
// --------------------------------------------------------------------------
class CoreTask {
  final String id;
  final String label;
  final Tier tier;
  final List<PmidRef> refs;

  const CoreTask({
    required this.id,
    required this.label,
    required this.tier,
    required this.refs,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        'tier': tier.name,
        'refs': refs.map((r) => r.toMap()).toList(),
      };

  factory CoreTask.fromMap(Map<String, dynamic> m) => CoreTask(
        id: m['id'] as String? ?? '',
        label: m['label'] as String? ?? '',
        tier: Tier.values.firstWhere(
          (t) => t.name == (m['tier'] as String? ?? 'tier1'),
          orElse: () => Tier.tier1,
        ),
        refs: ((m['refs'] as List?) ?? [])
            .map((e) => PmidRef.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

// Master checklist — all tasks the protocol can schedule.
// IDs are stable keys used in Firestore boolean maps
// (users/{uid}/data/today.sleepProtocol.checks.{id} = bool).
final List<CoreTask> _allTasks = [
  CoreTask(
    id: 'light_30min',
    label: '기상 즉시 광노출 30분 (실외 우선, 흐린 날도 야외)',
    tier: Tier.tier1,
    refs: [_pmidLibrary[2], _pmidLibrary[3]],
  ),
  CoreTask(
    id: 'caffeine_cutoff',
    label: '카페인 컷오프 (취침 8h 전)',
    tier: Tier.tier2,
    refs: [_pmidLibrary[0]],
  ),
  CoreTask(
    id: 'meal_cutoff',
    label: '식사 종료 (취침 3h 전, 야식 0)',
    tier: Tier.tier2,
    refs: [_pmidLibrary[0]],
  ),
  CoreTask(
    id: 'melatonin_dose',
    label: '멜라토닌 0.3~0.5mg 복용 (취침 5h 전)',
    tier: Tier.tier1,
    refs: [_pmidLibrary[1], _pmidLibrary[4]],
  ),
  CoreTask(
    id: 'screen_off_ladder',
    label: '화면 OFF — 이번 주 사다리 지속시간만큼 취침 전 유지',
    tier: Tier.tier1,
    refs: [_pmidLibrary[5]],
  ),
  CoreTask(
    id: 'phone_desk_dock',
    label: '폰은 책상 거치대에. 침대 위 반입 금지',
    tier: Tier.tier2,
    refs: [_pmidLibrary[5]],
  ),
  CoreTask(
    id: 'paper_book',
    label: '종이책 읽기 (노란 스탠드만, 천장등 OFF, 소설 권장)',
    tier: Tier.tier2,
    refs: [_pmidLibrary[5]],
  ),
  CoreTask(
    id: 'blackout_room',
    label: '침실 암막 — 가로등·LED 차단',
    tier: Tier.tier2,
    refs: [_pmidLibrary[2]],
  ),
  CoreTask(
    id: 'room_temp',
    label: '침실 온도 18~20℃ (시원하게)',
    tier: Tier.tier2,
    refs: [_pmidLibrary[0]],
  ),
  CoreTask(
    id: 'bed_sleep_only',
    label: '침대=잠 전용. 20분 내 못 자면 침대 밖으로',
    tier: Tier.tier2,
    refs: [_pmidLibrary[0]],
  ),
  CoreTask(
    id: 'wake_fixed',
    label: '기상 시각 고정 (±15분, 주말 늦잠 금지)',
    tier: Tier.tier1,
    refs: [_pmidLibrary[0]],
  ),
  CoreTask(
    id: 'sleep_fixed',
    label: '취침 시각 고정 (±15분)',
    tier: Tier.tier1,
    refs: [_pmidLibrary[0]],
  ),
];

CoreTask _taskById(String id) => _allTasks.firstWhere((t) => t.id == id);

// --------------------------------------------------------------------------
// Blocker info (HTML "선결 5개" — 5 prerequisites, v3-adjusted).
// The task contract requires at least #1 (phone dock + paper book) and #3
// (no phone on bed). All 5 are included for completeness; app decides which
// to surface per day.
// --------------------------------------------------------------------------
class BlockerInfo {
  final int index;
  final String title;
  final String body;
  final String solution;

  const BlockerInfo({
    required this.index,
    required this.title,
    required this.body,
    required this.solution,
  });

  Map<String, dynamic> toMap() => {
        'index': index,
        'title': title,
        'body': body,
        'solution': solution,
      };

  factory BlockerInfo.fromMap(Map<String, dynamic> m) => BlockerInfo(
        index: m['index'] as int? ?? 0,
        title: m['title'] as String? ?? '',
        body: m['body'] as String? ?? '',
        solution: m['solution'] as String? ?? '',
      );
}

const List<BlockerInfo> _allBlockers = [
  BlockerInfo(
    index: 1,
    title: '폰 책상 거치대 + 종이책',
    body:
        '청색광은 멜라토닌을 50%+ 억제한다. 폰을 거실 충전이 아니라 '
        '침대에서 손이 닿지 않는 책상 거치대에 고정하고 스크린타임 '
        '다운타임을 동시에 활성화한다. 대신 종이책(소설 권장, 자기계발서는 '
        '각성)을 노란 스탠드만 켜고 읽는다. 천장등은 OFF.',
    solution:
        '침대 위 폰 금지. 기상 후 폰은 책상 거치대에만. 사다리 '
        'W1 30분 / W2 1h / W3 1h30 / W4 2h 로 화면 OFF 시간을 늘린다.',
  ),
  BlockerInfo(
    index: 2,
    title: '침실 암막 (가로등 차단)',
    body:
        '이번 주 안에 암막 커튼을 설치한다. 임시로는 두꺼운 천 + 클립. '
        '기기의 LED 표시등은 검정 테이프로 가린다.',
    solution: '암막 커튼 설치 + LED 차단 테이프.',
  ),
  BlockerInfo(
    index: 3,
    title: '침대 = 잠만 (폰·TV 침대 위 금지)',
    body:
        '책상 거치대 외에는 침대 위로 폰을 들고 가지 않는다. '
        '20분 내에 잠들지 못하면 침대에서 나와 다른 방이나 소파에서 '
        '종이책을 읽는다. 침대 = 각성 학습 고리를 끊는다.',
    solution: '20분 규칙 + 폰 반입 금지.',
  ),
  BlockerInfo(
    index: 4,
    title: '매일 야외 30분 (기상 직후)',
    body:
        '광치료 + 운동 + zeitgeber 의 3중 효과. 흐린 날 야외(1~3만 lux)도 '
        '실내(<1000 lux)보다 강하다. 빠른 걷기·조깅 OK.',
    solution: '기상 직후 야외 30분 고정.',
  ),
  BlockerInfo(
    index: 5,
    title: '야식 0회 + 침실 18~20℃',
    body:
        '야식은 코르티솔 상승을 유발한다. 현재 실온 21~23℃ 를 낮춘다 — '
        '체온 강하는 수면 진입 신호다.',
    solution: '취침 3h 전 식사 종료 + 침실 온도 낮춤.',
  ),
];

// --------------------------------------------------------------------------
// Trouble triggers (HTML §5 응급 대처 — emergency cases mapped to triggers).
// --------------------------------------------------------------------------
class TroubleTrigger {
  final String id;
  final String pattern;
  final String signal;
  final String recovery;
  final Tier tier;

  const TroubleTrigger({
    required this.id,
    required this.pattern,
    required this.signal,
    required this.recovery,
    required this.tier,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'pattern': pattern,
        'signal': signal,
        'recovery': recovery,
        'tier': tier.name,
      };

  factory TroubleTrigger.fromMap(Map<String, dynamic> m) => TroubleTrigger(
        id: m['id'] as String? ?? '',
        pattern: m['pattern'] as String? ?? '',
        signal: m['signal'] as String? ?? '',
        recovery: m['recovery'] as String? ?? '',
        tier: Tier.values.firstWhere(
          (t) => t.name == (m['tier'] as String? ?? 'tier2'),
          orElse: () => Tier.tier2,
        ),
      );
}

const List<TroubleTrigger> _allTroubles = [
  TroubleTrigger(
    id: 'weekend_relapse',
    pattern: '주말 reflapse (사회적 시차 ≥1h)',
    signal: '월요일 SOL ≥30분',
    recovery: '주말 기상 시각 ±30분 강제. 늦잠 절대 금지.',
    tier: Tier.tier1,
  ),
  TroubleTrigger(
    id: 'week3_4_plateau',
    pattern: 'Week 3-4 정체 (시프트가 안 먹힘)',
    signal: '2일 연속 목표 취침 시각에 30분 이상 못 잠',
    recovery:
        '시프트 폭을 30분 → 20~25분/일로 하향. 멜라토닌 0.3mg 복용 재점검 '
        '+ 광치료 강도 확인. 해당 주는 시프트 일시 중단 + 같은 시각 유지 '
        '안정화.',
    tier: Tier.tier2,
  ),
  TroubleTrigger(
    id: 'melatonin_dependency',
    pattern: '멜라토닌 의존',
    signal: '멜라토닌 없이는 입면 불가',
    recovery:
        '복용 시각이 취침 1~2h 전으로 밀리면 오히려 위상 지연. 취침 5h 전 '
        '원칙을 재확인. 놓치면 30분 이내만 즉시, 초과 시 그날 스킵. '
        '2주 후 효과 평가 후 감량/중단 계획 수립.',
    tier: Tier.tier2,
  ),
  TroubleTrigger(
    id: 'withdrawal_insomnia',
    pattern: 'Withdrawal insomnia (취침 시각에 못 잠)',
    signal: '30분+ 누워있어도 못 잠',
    recovery:
        '침대에서 나와 거실에서 종이책 15분 → 다시 침대. 시각 자체는 지킨다. '
        '첫 1주는 흔하며, 멜라토닌 + 화면 OFF 적용 후 개선된다.',
    tier: Tier.tier2,
  ),
  TroubleTrigger(
    id: 'wake_failure',
    pattern: '기상 시각에 못 일어남',
    signal: '알람 후 60분+ 지나 기상',
    recovery:
        '그날은 그 시각을 기상으로 인정. 다음 날부터 30분 당기기 재개. '
        '이틀 연속 실패면 그 주 시프트 중단 + 같은 시각 유지.',
    tier: Tier.tier2,
  ),
];

// --------------------------------------------------------------------------
// Day target — computed snapshot for a given date.
// --------------------------------------------------------------------------
class DayTarget {
  final int week;
  final int dayInWeek;
  final int dayNumber;
  final SleepPhase phase;
  final TimeOfDay wakeTarget;
  final TimeOfDay sleepTarget;
  final Duration cumulativeShift;
  final List<CoreTask> coreTasks;
  final String? weeklyWarning;
  final List<BlockerInfo> activeBlockers;

  const DayTarget({
    required this.week,
    required this.dayInWeek,
    required this.dayNumber,
    required this.phase,
    required this.wakeTarget,
    required this.sleepTarget,
    required this.cumulativeShift,
    required this.coreTasks,
    required this.weeklyWarning,
    required this.activeBlockers,
  });

  Map<String, dynamic> toMap() => {
        'week': week,
        'dayInWeek': dayInWeek,
        'dayNumber': dayNumber,
        'phase': phase.name,
        'wakeTarget': _tod2str(wakeTarget),
        'sleepTarget': _tod2str(sleepTarget),
        'cumulativeShiftMinutes': cumulativeShift.inMinutes,
        'coreTasks': coreTasks.map((t) => t.toMap()).toList(),
        'weeklyWarning': weeklyWarning,
        'activeBlockers': activeBlockers.map((b) => b.toMap()).toList(),
      };

  factory DayTarget.fromMap(Map<String, dynamic> m) => DayTarget(
        week: m['week'] as int? ?? 1,
        dayInWeek: m['dayInWeek'] as int? ?? 1,
        dayNumber: m['dayNumber'] as int? ?? 1,
        phase: SleepPhase.values.firstWhere(
          (p) => p.name == (m['phase'] as String? ?? 'focus'),
          orElse: () => SleepPhase.focus,
        ),
        wakeTarget: _str2tod(m['wakeTarget'] as String? ?? '07:00'),
        sleepTarget: _str2tod(m['sleepTarget'] as String? ?? '23:00'),
        cumulativeShift:
            Duration(minutes: m['cumulativeShiftMinutes'] as int? ?? 0),
        coreTasks: ((m['coreTasks'] as List?) ?? [])
            .map((e) => CoreTask.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
        weeklyWarning: m['weeklyWarning'] as String?,
        activeBlockers: ((m['activeBlockers'] as List?) ?? [])
            .map(
                (e) => BlockerInfo.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

// --------------------------------------------------------------------------
// SleepProtocol — public entry.
// --------------------------------------------------------------------------
class SleepProtocol {
  final DateTime startDate;
  final TimeOfDay baselineWake;
  final TimeOfDay baselineSleep;
  final TimeOfDay goalWake;
  final TimeOfDay goalSleep;

  // HTML §3.1 — 30 min/day shift during focus phase.
  static const int shiftMinPerDay = 30;

  // HTML Blocker #1 ladder — W1 30m / W2 1h / W3 1h30 / W4 2h.
  static const List<int> screenOffLadderMinByWeek = [30, 60, 90, 120];

  // Protocol total horizon used for week/day math.
  static const int totalDays = 70; // 10 weeks

  const SleepProtocol({
    required this.startDate,
    required this.baselineWake,
    required this.baselineSleep,
    required this.goalWake,
    required this.goalSleep,
  });

  factory SleepProtocol.defaultForUser() {
    return SleepProtocol(
      startDate: DateTime(2026, 4, 18),
      baselineWake: const TimeOfDay(hour: 15, minute: 0),
      baselineSleep: const TimeOfDay(hour: 7, minute: 0),
      goalWake: const TimeOfDay(hour: 7, minute: 0),
      goalSleep: const TimeOfDay(hour: 23, minute: 0),
    );
  }

  // Date math --------------------------------------------------------------

  int _dayNumberFor(DateTime date) {
    final s = DateTime(startDate.year, startDate.month, startDate.day);
    final d = DateTime(date.year, date.month, date.day);
    final diff = d.difference(s).inDays;
    return diff + 1; // Day 1 at startDate
  }

  // Minutes needed to go from baselineWake to goalWake going backward
  // (phase-advance). baselineWake 15:00 -> goalWake 07:00 = -480 min.
  int _totalShiftMinutes() {
    final baseMin = baselineWake.hour * 60 + baselineWake.minute;
    final goalMin = goalWake.hour * 60 + goalWake.minute;
    // Phase-advance: going earlier. Compute shortest backward delta.
    var delta = baseMin - goalMin;
    if (delta <= 0) delta += 24 * 60;
    return delta;
  }

  int _maxShiftDays() {
    final total = _totalShiftMinutes();
    return (total / shiftMinPerDay).ceil();
  }

  TimeOfDay _advance(TimeOfDay base, int minutesEarlier) {
    final baseMin = base.hour * 60 + base.minute;
    var m = (baseMin - minutesEarlier) % (24 * 60);
    if (m < 0) m += 24 * 60;
    return TimeOfDay(hour: m ~/ 60, minute: m % 60);
  }

  // Main query -------------------------------------------------------------

  DayTarget dayFor(DateTime date) {
    // Clamp to [1, totalDays]; outside range falls back to boundary.
    var n = _dayNumberFor(date);
    if (n < 1) n = 1;
    if (n > totalDays) n = totalDays;

    final week = ((n - 1) ~/ 7) + 1; // 1..10
    final dayInWeek = ((n - 1) % 7) + 1; // 1..7

    final maxShiftDays = _maxShiftDays(); // e.g. 16 days for 480min
    final phase = (n <= maxShiftDays) ? SleepPhase.focus : SleepPhase.maintain;

    final TimeOfDay wake;
    final TimeOfDay sleep;
    final Duration shift;
    if (phase == SleepPhase.focus) {
      final shiftMin = shiftMinPerDay * n; // Day 1 = -30min, Day 2 = -60min...
      final clampedShiftMin = shiftMin.clamp(0, _totalShiftMinutes());
      wake = _advance(baselineWake, clampedShiftMin);
      sleep = _advance(baselineSleep, clampedShiftMin);
      shift = Duration(minutes: clampedShiftMin);
    } else {
      wake = goalWake;
      sleep = goalSleep;
      shift = Duration(minutes: _totalShiftMinutes());
    }

    final tasks = _coreTasksFor(week, phase);
    final warn = _weeklyWarningFor(week, phase);
    final blockers = _activeBlockersFor(week, phase);

    return DayTarget(
      week: week,
      dayInWeek: dayInWeek,
      dayNumber: n,
      phase: phase,
      wakeTarget: wake,
      sleepTarget: sleep,
      cumulativeShift: shift,
      coreTasks: tasks,
      weeklyWarning: warn,
      activeBlockers: blockers,
    );
  }

  DayTarget get today => dayFor(DateTime.now());

  // Task/blocker mapping ---------------------------------------------------

  List<CoreTask> _coreTasksFor(int week, SleepPhase phase) {
    // Daily baseline 4 tasks (HTML §4 legend).
    final base = <CoreTask>[
      _taskById('light_30min'),
      _taskById('caffeine_cutoff'),
      _taskById('meal_cutoff'),
      _taskById('melatonin_dose'),
      _taskById('screen_off_ladder'),
    ];

    // Week-specific additions — phone dock + paper book + bedroom hygiene.
    if (week >= 1 && week <= 4) {
      // Focus weeks 1-4: ladder build-up + environment setup.
      base.add(_taskById('phone_desk_dock'));
      base.add(_taskById('paper_book'));
      if (week == 1) {
        base.add(_taskById('blackout_room'));
        base.add(_taskById('room_temp'));
      }
      if (week >= 2) {
        base.add(_taskById('bed_sleep_only'));
      }
    } else {
      // Weeks 5-10 (maintain, and any remaining focus days in week 3-4 tail):
      // minimal maintenance set.
      base.add(_taskById('phone_desk_dock'));
      base.add(_taskById('wake_fixed'));
      base.add(_taskById('sleep_fixed'));
    }

    return base;
  }

  String? _weeklyWarningFor(int week, SleepPhase phase) {
    switch (week) {
      case 1:
        return '첫 주는 선결 5개 동시 가동. 화면 OFF 사다리 W1 = 30분.';
      case 2:
        return '화면 OFF 사다리 W2 = 1시간. 침대=잠 전용 룰 가동.';
      case 3:
        return '화면 OFF 사다리 W3 = 1시간 30분. Week 3-4 정체 구간 주의.';
      case 4:
        return '화면 OFF 사다리 W4 = 2시간. 목표 도달 근처.';
      case 5:
      case 6:
        return '안정화 초기. 주말 늦잠 절대 금지 (±15분).';
      case 7:
      case 8:
        return '멜라토닌 감량/중단 검토 구간 (2주+ 효과 평가).';
      case 9:
      case 10:
        return '데드라인 임박. 고정 시각 유지.';
      default:
        return null;
    }
  }

  List<BlockerInfo> _activeBlockersFor(int week, SleepPhase phase) {
    // Week 1: all 5 blockers active (선결 5개 동시).
    if (week == 1) return List<BlockerInfo>.from(_allBlockers);
    // Weeks 2-4: phone-dock + bed-only + outdoor stay active; blackout and
    // meal/temp should already be set up.
    if (week >= 2 && week <= 4) {
      return _allBlockers.where((b) => b.index == 1 || b.index == 3 || b.index == 4).toList();
    }
    // Maintain phase: keep #1 (phone dock) and #3 (no phone on bed) as the
    // two v3-highlighted anchors.
    return _allBlockers.where((b) => b.index == 1 || b.index == 3).toList();
  }

  // Public exposures -------------------------------------------------------

  List<TroubleTrigger> get troubles => List.unmodifiable(_allTroubles);
  List<CoreTask> get allChecklistItems => List.unmodifiable(_allTasks);
  List<PmidRef> get references => List.unmodifiable(_pmidLibrary);
  List<BlockerInfo> get allBlockers => List.unmodifiable(_allBlockers);

  // Week ladder helper -----------------------------------------------------
  int screenOffMinutesForWeek(int week) {
    if (week < 1) return screenOffLadderMinByWeek.first;
    if (week <= 4) return screenOffLadderMinByWeek[week - 1];
    // Weeks 5+ hold at W4 target (2h).
    return screenOffLadderMinByWeek.last;
  }

  // Firestore serialization ------------------------------------------------

  Map<String, dynamic> toMap() => {
        'startDate': startDate.toIso8601String(),
        'baselineWake': _tod2str(baselineWake),
        'baselineSleep': _tod2str(baselineSleep),
        'goalWake': _tod2str(goalWake),
        'goalSleep': _tod2str(goalSleep),
      };

  factory SleepProtocol.fromMap(Map<String, dynamic> m) => SleepProtocol(
        startDate: DateTime.parse(
            m['startDate'] as String? ?? '2026-04-18T00:00:00.000'),
        baselineWake: _str2tod(m['baselineWake'] as String? ?? '15:00'),
        baselineSleep: _str2tod(m['baselineSleep'] as String? ?? '07:00'),
        goalWake: _str2tod(m['goalWake'] as String? ?? '07:00'),
        goalSleep: _str2tod(m['goalSleep'] as String? ?? '23:00'),
      );
}

// --------------------------------------------------------------------------
// TimeOfDay <-> "HH:mm" helpers.
// --------------------------------------------------------------------------
String _tod2str(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

TimeOfDay _str2tod(String s) {
  final parts = s.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return TimeOfDay(hour: h, minute: m);
}
