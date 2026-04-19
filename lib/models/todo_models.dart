/// ═══════════════════════════════════════════════════════════
/// CHEONHONG DAILY — Todo 모델
/// plan_models.dart에서 분리 (2026-04-17 앱 분리 Phase A)
/// ═══════════════════════════════════════════════════════════

/// Todo 개별 항목
class TodoItem {
  final String id;
  final String title;
  final bool completed;
  final String? completedAt; // ISO8601
  final int order; // 정렬 순서
  final int? estimatedMinutes; // 예상 시간 (분)
  final String? priority; // high/medium/low
  final String? type; // task/errand

  static const priorities = ['high', 'medium', 'low'];
  static const priorityLabels = {'high': '상', 'medium': '중', 'low': '하'};

  /// 할일 유형
  static const types = <String, String>{
    'task': '✅ 과제',
    'errand': '🏃 기타',
  };
  static const typeKeys = ['task', 'errand'];

  TodoItem({
    required this.id,
    required this.title,
    this.completed = false,
    this.completedAt,
    this.order = 0,
    this.estimatedMinutes,
    this.priority,
    this.type,
  });

  TodoItem copyWith({
    String? title,
    bool? completed,
    String? completedAt,
    int? order,
    int? estimatedMinutes,
    bool clearEstimatedMinutes = false,
    String? priority,
    bool clearPriority = false,
    String? type,
    bool clearType = false,
  }) =>
      TodoItem(
        id: id,
        title: title ?? this.title,
        completed: completed ?? this.completed,
        completedAt: completedAt ?? this.completedAt,
        order: order ?? this.order,
        estimatedMinutes: clearEstimatedMinutes
            ? null
            : (estimatedMinutes ?? this.estimatedMinutes),
        priority: clearPriority ? null : (priority ?? this.priority),
        type: clearType ? null : (type ?? this.type),
      );

  factory TodoItem.fromMap(Map<String, dynamic> m) => TodoItem(
        id: m['id'] ?? '',
        title: m['title'] ?? '',
        completed: m['completed'] ?? false,
        completedAt: m['completedAt'] as String?,
        order: (m['order'] as num?)?.toInt() ?? 0,
        estimatedMinutes: (m['estimatedMinutes'] as num?)?.toInt(),
        priority: m['priority'] as String?,
        type: m['type'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'completed': completed,
        if (completedAt != null) 'completedAt': completedAt,
        'order': order,
        if (estimatedMinutes != null) 'estimatedMinutes': estimatedMinutes,
        if (priority != null) 'priority': priority,
        if (type != null) 'type': type,
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
