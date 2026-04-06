/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — 학습계획 · 피드백 · AI코칭 · 성장 모델
/// Batch 3: #3 학습계획·피드백관리 + #4 AI협업학습코칭
/// ═══════════════════════════════════════════════════════════

// ╔═══════════════════════════════════════════════════════════╗
// ║  PART 1: 학습 계획 (Study Plan)                           ║
// ╚═══════════════════════════════════════════════════════════╝

/// 동적 학습 계획 — Firestore studyPlan 필드
class StudyPlan {
  final String version;
  final String title;
  final String? updatedAt;
  final String? updatedBy; // "web" | "app" | "ai"
  final Map<String, AnnualGoal> annualGoals;
  final List<PlanPeriodDyn> periods;
  final List<DDayEvent> ddays;
  final StrategicDirection? strategy;
  final List<ScenarioBranch> scenarios;

  StudyPlan({
    this.version = '5.0',
    this.title = '',
    this.updatedAt,
    this.updatedBy,
    Map<String, AnnualGoal>? annualGoals,
    List<PlanPeriodDyn>? periods,
    List<DDayEvent>? ddays,
    this.strategy,
    List<ScenarioBranch>? scenarios,
  })  : annualGoals = annualGoals ?? {},
        periods = periods ?? [],
        ddays = ddays ?? [],
        scenarios = scenarios ?? [];

  /// 현재 날짜가 속한 기간
  PlanPeriodDyn? periodForDate(String ds) {
    for (final p in periods) {
      if (p.containsDate(ds)) return p;
    }
    return null;
  }

  /// 현재 날짜가 속한 하위 기간
  PlanSubPeriodDyn? subPeriodForDate(String ds) {
    return periodForDate(ds)?.subPeriodForDate(ds);
  }

  /// 활성 D-Day 중 가장 가까운 것
  DDayEvent? nearestDDay() {
    final future = ddays
        .where((d) => d.enabled && d.daysLeft >= 0)
        .toList()
      ..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
    return future.isNotEmpty ? future.first : null;
  }

  /// primary D-Day (없으면 가장 가까운 것)
  DDayEvent? primaryDDay() {
    try {
      return ddays.firstWhere((d) => d.primary && d.enabled);
    } catch (_) {
      return nearestDDay();
    }
  }

  factory StudyPlan.fromMap(Map<String, dynamic> m) {
    // annualGoals 파싱
    final goalsRaw = m['annualGoals'] as Map<String, dynamic>? ?? {};
    final goals = goalsRaw.map((k, v) =>
        MapEntry(k, AnnualGoal.fromMap(Map<String, dynamic>.from(v as Map))));

    return StudyPlan(
      version: m['version'] ?? '5.0',
      title: m['title'] ?? '',
      updatedAt: m['updatedAt'] as String?,
      updatedBy: m['updatedBy'] as String?,
      annualGoals: goals,
      periods: (m['periods'] as List?)
              ?.map((e) =>
                  PlanPeriodDyn.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      ddays: (m['ddays'] as List?)
              ?.map((e) =>
                  DDayEvent.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      strategy: m['strategicDirection'] != null
          ? StrategicDirection.fromMap(
              Map<String, dynamic>.from(m['strategicDirection'] as Map))
          : null,
      scenarios: (m['scenarios'] as List?)
              ?.map((e) =>
                  ScenarioBranch.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() => {
        'version': version,
        'title': title,
        if (updatedAt != null) 'updatedAt': updatedAt,
        if (updatedBy != null) 'updatedBy': updatedBy,
        'annualGoals':
            annualGoals.map((k, v) => MapEntry(k, v.toMap())),
        'periods': periods.map((p) => p.toMap()).toList(),
        'ddays': ddays.map((d) => d.toMap()).toList(),
        if (strategy != null) 'strategicDirection': strategy!.toMap(),
        'scenarios': scenarios.map((s) => s.toMap()).toList(),
      };
}

/// 연간 목표
class AnnualGoal {
  final String title;
  final int priority;
  final String status; // "active" | "completed" | "paused" | "dropped"

  AnnualGoal({
    required this.title,
    this.priority = 0,
    this.status = 'active',
  });

  bool get isActive => status == 'active';

  factory AnnualGoal.fromMap(Map<String, dynamic> m) => AnnualGoal(
        title: m['title'] ?? '',
        priority: (m['priority'] as num?)?.toInt() ?? 0,
        status: m['status'] ?? 'active',
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'priority': priority,
        'status': status,
      };
}

/// 기간 (Period) — 동적 버전
class PlanPeriodDyn {
  final String id;
  final String name;
  final String start; // yyyy-MM-dd
  final String end;
  final String goal;
  final int totalDays;
  final String status; // "active" | "completed" | "upcoming" | "skipped"
  final List<PlanSubPeriodDyn> subPeriods;
  final List<PlanSubjectDyn> subjects;

  PlanPeriodDyn({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    required this.goal,
    this.totalDays = 0,
    this.status = 'upcoming',
    List<PlanSubPeriodDyn>? subPeriods,
    List<PlanSubjectDyn>? subjects,
  })  : subPeriods = subPeriods ?? [],
        subjects = subjects ?? [];

  bool containsDate(String ds) =>
      ds.compareTo(start) >= 0 && ds.compareTo(end) <= 0;

  PlanSubPeriodDyn? subPeriodForDate(String ds) {
    for (final sp in subPeriods) {
      if (sp.containsDate(ds)) return sp;
    }
    return null;
  }

  double progressForDate(String ds) {
    final s = DateTime.tryParse(start);
    final e = DateTime.tryParse(end);
    final d = DateTime.tryParse(ds);
    if (s == null || e == null || d == null) return 0;
    final total = e.difference(s).inDays;
    if (total <= 0) return 0;
    return (d.difference(s).inDays / total).clamp(0.0, 1.0);
  }

  factory PlanPeriodDyn.fromMap(Map<String, dynamic> m) => PlanPeriodDyn(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        start: m['start'] ?? '',
        end: m['end'] ?? '',
        goal: m['goal'] ?? '',
        totalDays: (m['totalDays'] as num?)?.toInt() ?? 0,
        status: m['status'] ?? 'upcoming',
        subPeriods: (m['subPeriods'] as List?)
                ?.map((e) => PlanSubPeriodDyn.fromMap(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        subjects: (m['subjects'] as List?)
                ?.map((e) => PlanSubjectDyn.fromMap(
                    Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start': start,
        'end': end,
        'goal': goal,
        'totalDays': totalDays,
        'status': status,
        'subPeriods': subPeriods.map((s) => s.toMap()).toList(),
        'subjects': subjects.map((s) => s.toMap()).toList(),
      };
}

/// 하위 기간
class PlanSubPeriodDyn {
  final String id;
  final String name;
  final String start;
  final String end;
  final int days;
  final String? instructor;
  final String primaryGoal;
  final List<String> goals;
  final List<String> checkpoints;
  final String status;

  PlanSubPeriodDyn({
    required this.id,
    required this.name,
    required this.start,
    required this.end,
    this.days = 0,
    this.instructor,
    required this.primaryGoal,
    List<String>? goals,
    List<String>? checkpoints,
    this.status = 'upcoming',
  })  : goals = goals ?? [],
        checkpoints = checkpoints ?? [];

  bool containsDate(String ds) =>
      ds.compareTo(start) >= 0 && ds.compareTo(end) <= 0;

  factory PlanSubPeriodDyn.fromMap(Map<String, dynamic> m) =>
      PlanSubPeriodDyn(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        start: m['start'] ?? '',
        end: m['end'] ?? '',
        days: (m['days'] as num?)?.toInt() ?? 0,
        instructor: m['instructor'] as String?,
        primaryGoal: m['primaryGoal'] ?? '',
        goals: (m['goals'] as List?)?.map((e) => e.toString()).toList() ?? [],
        checkpoints:
            (m['checkpoints'] as List?)?.map((e) => e.toString()).toList() ??
                [],
        status: m['status'] ?? 'upcoming',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'start': start,
        'end': end,
        'days': days,
        if (instructor != null) 'instructor': instructor,
        'primaryGoal': primaryGoal,
        'goals': goals,
        'checkpoints': checkpoints,
        'status': status,
      };
}

/// 과목
class PlanSubjectDyn {
  final String title;
  final String tag;
  final String? instructor;
  final String? period; // 보류 등 메모
  final List<String> curriculum;

  PlanSubjectDyn({
    required this.title,
    required this.tag,
    this.instructor,
    this.period,
    List<String>? curriculum,
  }) : curriculum = curriculum ?? [];

  factory PlanSubjectDyn.fromMap(Map<String, dynamic> m) => PlanSubjectDyn(
        title: m['title'] ?? '',
        tag: m['tag'] ?? '',
        instructor: m['instructor'] as String?,
        period: m['period'] as String?,
        curriculum:
            (m['curriculum'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );

  Map<String, dynamic> toMap() => {
        'title': title,
        'tag': tag,
        if (instructor != null) 'instructor': instructor,
        if (period != null) 'period': period,
        'curriculum': curriculum,
      };
}

/// D-Day 이벤트
class DDayEvent {
  final int id;
  final String name;
  final String date; // yyyy-MM-dd
  final bool primary;
  final bool enabled;

  DDayEvent({
    required this.id,
    required this.name,
    required this.date,
    this.primary = false,
    this.enabled = true,
  });

  int get daysLeft {
    final now = DateTime.now();
    final target = DateTime.tryParse(date);
    if (target == null) return 999;
    return target
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
  }

  bool get isPast => daysLeft < 0;

  String get dDayLabel {
    final d = daysLeft;
    if (d == 0) return 'D-Day';
    return d > 0 ? 'D-$d' : 'D+${d.abs()}';
  }

  factory DDayEvent.fromMap(Map<String, dynamic> m) => DDayEvent(
        id: (m['id'] as num?)?.toInt() ?? 0,
        name: m['name'] ?? '',
        date: m['date'] ?? '',
        primary: m['primary'] ?? false,
        enabled: m['enabled'] ?? true,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'date': date,
        'primary': primary,
        'enabled': enabled,
      };
}

/// 전략 방향
class StrategicDirection {
  final String diagnosis;
  final String? lastEvaluated;
  final String? nextEvaluation;
  final Map<String, String> notes; // 키-값 자유 메모

  StrategicDirection({
    required this.diagnosis,
    this.lastEvaluated,
    this.nextEvaluation,
    Map<String, String>? notes,
  }) : notes = notes ?? {};

  factory StrategicDirection.fromMap(Map<String, dynamic> m) {
    final notesRaw = m['notes'] as Map<String, dynamic>? ?? {};
    return StrategicDirection(
      diagnosis: m['diagnosis'] ?? '',
      lastEvaluated: m['lastEvaluated'] as String?,
      nextEvaluation: m['nextEvaluation'] as String?,
      notes: notesRaw.map((k, v) => MapEntry(k, v.toString())),
    );
  }

  Map<String, dynamic> toMap() => {
        'diagnosis': diagnosis,
        if (lastEvaluated != null) 'lastEvaluated': lastEvaluated,
        if (nextEvaluation != null) 'nextEvaluation': nextEvaluation,
        'notes': notes,
      };
}

/// 시나리오 분기
class ScenarioBranch {
  final String id;
  final String condition;
  final String trigger;
  final List<String> actions;
  final String nextPeriod;

  ScenarioBranch({
    required this.id,
    required this.condition,
    required this.trigger,
    List<String>? actions,
    required this.nextPeriod,
  }) : actions = actions ?? [];

  factory ScenarioBranch.fromMap(Map<String, dynamic> m) => ScenarioBranch(
        id: m['id'] ?? '',
        condition: m['condition'] ?? '',
        trigger: m['trigger'] ?? '',
        actions:
            (m['actions'] as List?)?.map((e) => e.toString()).toList() ?? [],
        nextPeriod: m['nextPeriod'] ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'condition': condition,
        'trigger': trigger,
        'actions': actions,
        'nextPeriod': nextPeriod,
      };
}

// ╔═══════════════════════════════════════════════════════════╗
// ║  PART 1-B: Todo (할일 관리)                                 ║
// ╚═══════════════════════════════════════════════════════════╝

/// Todo 개별 항목
// ★ AUDIT FIX: B-09 — mutable 필드를 final로 변경 (불변성 규칙 준수, copyWith 사용)
class TodoItem {
  final String id;
  final String title;
  final bool completed;
  final String? completedAt; // ISO8601
  final int order; // 정렬 순서
  final String? subject;        // 과목 태그: 언어/자료/상황/경제/7급전공
  final int? estimatedMinutes;  // 예상 시간 (분)
  final String? priority;       // high/medium/low
  final String? type;           // study/review/mock/task/errand
  final String? goalId;         // ProgressGoal 연결 (진행도 자동 반영)
  final int? goalUnits;         // 완료 시 진행할 단위 수 (기본 1)

  static const subjects = ['언어', '자료', '상황', '경제', '7급전공'];
  static const priorities = ['high', 'medium', 'low'];
  static const priorityLabels = {'high': '상', 'medium': '중', 'low': '하'};

  /// 할일 유형 (입력 단계에서 분류)
  static const types = <String, String>{
    'study':   '📖 학습',
    'review':  '🔄 복습',
    'mock':    '📝 모의고사',
    'task':    '✅ 과제',
    'errand':  '🏃 기타',
  };
  static const typeKeys = ['study', 'review', 'mock', 'task', 'errand'];

  TodoItem({
    required this.id,
    required this.title,
    this.completed = false,
    this.completedAt,
    this.order = 0,
    this.subject,
    this.estimatedMinutes,
    this.priority,
    this.type,
    this.goalId,
    this.goalUnits,
  });

  /// [clearSubject], [clearPriority] 등을 true로 전달하면 해당 필드를 null로 설정
  TodoItem copyWith({
    String? title,
    bool? completed,
    String? completedAt,
    int? order,
    String? subject,
    bool clearSubject = false,
    int? estimatedMinutes,
    bool clearEstimatedMinutes = false,
    String? priority,
    bool clearPriority = false,
    String? type,
    bool clearType = false,
    String? goalId,
    bool clearGoalId = false,
    int? goalUnits,
    bool clearGoalUnits = false,
  }) =>
      TodoItem(
        id: id,
        title: title ?? this.title,
        completed: completed ?? this.completed,
        completedAt: completedAt ?? this.completedAt,
        order: order ?? this.order,
        subject: clearSubject ? null : (subject ?? this.subject),
        estimatedMinutes: clearEstimatedMinutes ? null : (estimatedMinutes ?? this.estimatedMinutes),
        priority: clearPriority ? null : (priority ?? this.priority),
        type: clearType ? null : (type ?? this.type),
        goalId: clearGoalId ? null : (goalId ?? this.goalId),
        goalUnits: clearGoalUnits ? null : (goalUnits ?? this.goalUnits),
      );

  factory TodoItem.fromMap(Map<String, dynamic> m) => TodoItem(
        id: m['id'] ?? '',
        title: m['title'] ?? '',
        completed: m['completed'] ?? false,
        completedAt: m['completedAt'] as String?,
        order: (m['order'] as num?)?.toInt() ?? 0,
        subject: m['subject'] as String?,
        estimatedMinutes: (m['estimatedMinutes'] as num?)?.toInt(),
        priority: m['priority'] as String?,
        type: m['type'] as String?,
        goalId: m['goalId'] as String?,
        goalUnits: (m['goalUnits'] as num?)?.toInt(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'completed': completed,
        if (completedAt != null) 'completedAt': completedAt,
        'order': order,
        if (subject != null) 'subject': subject,
        if (estimatedMinutes != null) 'estimatedMinutes': estimatedMinutes,
        if (priority != null) 'priority': priority,
        if (type != null) 'type': type,
        if (goalId != null) 'goalId': goalId,
        if (goalUnits != null) 'goalUnits': goalUnits,
      };
}

/// 일일 Todo 전체 (하루 한 문서)
class TodoDaily {
  final String date; // yyyy-MM-dd
  final List<TodoItem> items;
  final String? memo;
  final String? createdAt;
  final String? updatedAt;

  TodoDaily({
    required this.date,
    List<TodoItem>? items,
    this.memo,
    this.createdAt,
    this.updatedAt,
  }) : items = items ?? [];

  /// 완료율 (0.0 ~ 1.0)
  double get completionRate {
    if (items.isEmpty) return 0.0;
    return items.where((t) => t.completed).length / items.length;
  }

  int get completedCount => items.where((t) => t.completed).length;
  int get totalCount => items.length;

  factory TodoDaily.fromMap(Map<String, dynamic> m) => TodoDaily(
        date: m['date'] ?? '',
        items: (m['items'] as List?)
                ?.map((e) =>
                    TodoItem.fromMap(Map<String, dynamic>.from(e as Map)))
                .toList() ??
            [],
        memo: m['memo'] as String?,
        createdAt: m['createdAt'] as String?,
        updatedAt: m['updatedAt'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'date': date,
        'items': items.map((t) => t.toMap()).toList(),
        if (memo != null) 'memo': memo,
        if (createdAt != null) 'createdAt': createdAt,
        if (updatedAt != null) 'updatedAt': updatedAt,
      };
}

