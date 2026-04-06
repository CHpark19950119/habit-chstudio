/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — Todo Service
/// 간결한 할일 관리 CRUD
/// study 문서의 todos 필드에서 읽기/쓰기
/// ═══════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/plan_models.dart';
import '../models/models.dart';
import '../utils/study_date_utils.dart';
import 'firebase_service.dart';
import 'widget_render_service.dart';
import 'write_queue_service.dart';

class TodoService {
  static final TodoService _instance = TodoService._internal();
  factory TodoService() => _instance;
  TodoService._internal();

  static final String _todosDoc = kStudyDoc;

  /// 4AM 경계 적용 오늘 날짜
  static String _todayDate() => StudyDateUtils.todayKey();

  /// 특정 날짜의 Todo 로드
  Future<TodoDaily?> getTodos(String date) async {
    try {
      final data = await FirebaseService().getStudyData();
      if (data == null) return null;
      final todosMap = _extractTodosMap(data['todos']);
      if (todosMap == null || todosMap[date] == null) return null;
      return TodoDaily.fromMap(
          Map<String, dynamic>.from(todosMap[date] as Map));
    } catch (e) {
      debugPrint('[TodoService] getTodos error: $e');
      return null;
    }
  }

  /// todos 필드가 Map이면 그대로, List면 null 반환 (잘못된 형식 무시)
  Map<String, dynamic>? _extractTodosMap(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    // List<dynamic> 등 비정상 형태 → 무시
    debugPrint('[TodoService] todos 필드가 Map이 아님: ${raw.runtimeType}');
    return null;
  }

  /// 오늘의 Todo 로드 (4AM 경계)
  Future<TodoDaily?> getTodayTodos() async {
    return getTodos(_todayDate());
  }

  /// Todo 저장 -- Optimistic: 캐시 즉시 갱신, Firestore fire-and-forget
  void saveTodos(TodoDaily todos) {
    final map = todos.toMap();
    if (map['createdAt'] == null) {
      map['createdAt'] = DateTime.now().toIso8601String();
    }
    map['updatedAt'] = DateTime.now().toIso8601String();

    // 1) 캐시 즉시 갱신 (write 보호 마킹 포함)
    FirebaseService().updateTodosCache(todos.date, map);

    // 2) Phase D: today doc only (single source of truth)
    if (todos.date == _todayDate()) {
      final todayList = todos.items.map((t) => {
        'id': t.id,
        'title': t.title,
        'done': t.completed,
        'completedAt': t.completedAt,
      }).toList();
      FirebaseService().updateTodayField('todos', todayList);
    }

    // 3) study doc (legacy compat -- will be removed in future)
    FirestoreWriteQueue().enqueue(_todosDoc, {
      'todos.${todos.date}': map,
    });

    // 4) Home widget refresh
    WidgetRenderService().updateWidget().catchError((_) {});
  }

  /// 개별 Todo 완료 토글
  Future<void> toggleTodo(String date, String id, bool completed) async {
    final todos = await getTodos(date);
    if (todos == null) return;

    final items = todos.items.map((t) {
      if (t.id == id) {
        return t.copyWith(
          completed: completed,
          completedAt:
              completed ? DateTime.now().toIso8601String() : null,
        );
      }
      return t;
    }).toList();

    saveTodos(TodoDaily(
      date: todos.date,
      items: items,
      memo: todos.memo,
      createdAt: todos.createdAt,
    ));

    // ★ 진행도 자동 반영: goalId가 있는 투두 완료 시 ProgressGoal 업데이트
    if (completed) {
      final item = items.firstWhere((t) => t.id == id);
      if (item.goalId != null) {
        _advanceGoalProgress(item.goalId!, item.goalUnits ?? 1, date);
      }
    }
  }

  /// goalId로 연결된 ProgressGoal의 currentUnit을 증가시킴
  Future<void> _advanceGoalProgress(String goalId, int units, String date) async {
    try {
      final goals = await FirebaseService().getProgressGoals();
      final idx = goals.indexWhere((g) => g.id == goalId);
      if (idx < 0) return;

      final goal = goals[idx];
      if (goal.completed) return; // 이미 완료된 목표

      final newUnit = (goal.currentUnit + units).clamp(0, goal.totalUnits);
      final now = DateTime.now();

      // dailyLog 추가
      final log = ProgressLog(
        date: date,
        from: goal.currentUnit,
        to: newUnit,
        loggedAt: now.toIso8601String(),
      );

      final updatedGoal = ProgressGoal(
        id: goal.id,
        subject: goal.subject,
        title: goal.title,
        totalUnits: goal.totalUnits,
        unitName: goal.unitName,
        goalType: goal.goalType,
        startPage: goal.startPage,
        endPage: goal.endPage,
        currentUnit: newUnit,
        completed: newUnit >= goal.totalUnits,
        startDate: goal.startDate,
        endDate: goal.endDate,
        dailyLogs: [...goal.dailyLogs, log],
        completionHistory: goal.completionHistory,
        lastLogDate: date,
        completedAt: newUnit >= goal.totalUnits ? now.toIso8601String() : goal.completedAt,
        completedRound: goal.completedRound,
        groupId: goal.groupId,
        groupName: goal.groupName,
        createdAt: goal.createdAt,
      );

      goals[idx] = updatedGoal;
      await FirebaseService().saveProgressGoals(goals);
      debugPrint('[TodoService] Goal "$goalId" advanced: ${goal.currentUnit} → $newUnit');
    } catch (e) {
      debugPrint('[TodoService] Goal advance error: $e');
    }
  }

  /// 내일 Todo 준비 (미완료 이월 + 새 항목)
  Future<TodoDaily> prepareTomorrowTodos({
    List<TodoItem> additionalItems = const [],
  }) async {
    final today = _todayDate();
    final todayTodos = await getTodos(today);

    final todayDt = DateFormat('yyyy-MM-dd').parse(today);
    final tomorrowStr =
        DateFormat('yyyy-MM-dd').format(todayDt.add(const Duration(days: 1)));

    final carryOver = (todayTodos?.items ?? [])
        .where((t) => !t.completed)
        .toList();

    int order = 0;
    final items = <TodoItem>[];
    for (final item in carryOver) {
      items.add(item.copyWith(
        completed: false,
        completedAt: null,
        order: order++,
      ));
    }
    for (final item in additionalItems) {
      items.add(TodoItem(
        id: item.id,
        title: item.title,
        order: order++,
      ));
    }

    final tomorrow = TodoDaily(
      date: tomorrowStr,
      items: items,
      createdAt: DateTime.now().toIso8601String(),
    );
    saveTodos(tomorrow);
    return tomorrow;
  }

  /// 최근 N일 완료율 히스토리
  Future<Map<String, double>> getCompletionHistory({int days = 7}) async {
    try {
      final data = await FirebaseService().getStudyData();
      final raw = _extractTodosMap(data?['todos']);
      if (raw == null) return {};

      final cutoff = DateFormat('yyyy-MM-dd')
          .format(DateTime.now().subtract(Duration(days: days)));

      final result = <String, double>{};
      for (final entry in raw.entries) {
        if (entry.key.compareTo(cutoff) >= 0) {
          try {
            final td = TodoDaily.fromMap(
                Map<String, dynamic>.from(entry.value as Map));
            result[entry.key] = td.completionRate;
          } catch (_) {}
        }
      }
      return result;
    } catch (e) {
      debugPrint('[TodoService] getCompletionHistory error: $e');
      return {};
    }
  }
}
