/// ===================================================================
/// CHEONHONG STUDIO -- Report Service
/// 일일 / 주간 통계 리포트 자동 생성 + Telegram 전송
/// ===================================================================

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/order_models.dart';
import '../models/todo_models.dart';
import '../utils/date_utils.dart';
import 'firebase_service.dart';
import 'telegram_service.dart';

class ReportService {
  static final ReportService _instance = ReportService._internal();
  factory ReportService() => _instance;
  ReportService._internal();

  // =====================================================================
  //  1. Enhanced Daily Report
  // =====================================================================

  /// 일일 리포트 문자열 생성 (취침 시 호출)
  /// [dateStr]: yyyy-MM-dd 형식
  Future<String> buildDailyReport(String dateStr) async {
    debugPrint('[Report] buildDailyReport: $dateStr');
    try {
      final fb = FirebaseService();
      final data = await fb.getStudyData();

      // ── TimeRecord ──
      final timeRecord = _extractTimeRecord(data, dateStr);

      // ── Todo ──
      final todoDaily = await _extractTodos(data, dateStr);

      // ── OrderData (습관) ──
      final orderData = _extractOrderData(data);

      // ── 리포트 조립 ──
      final buf = StringBuffer();
      buf.writeln('===== DAILY REPORT =====');
      buf.writeln('$dateStr (${_weekdayKr(dateStr)})');
      buf.writeln();

      // 활동시간
      if (timeRecord?.wake != null && timeRecord?.bedTime != null) {
        final activeMin = _timeDiffMin(timeRecord!.wake!, timeRecord.bedTime!);
        buf.writeln('-- ACTIVITY --');
        buf.writeln('  wake   ${timeRecord.wake}');
        buf.writeln('  bed    ${timeRecord.bedTime}');
        if (activeMin != null && activeMin > 0) {
          buf.writeln('  total  ${_fmtDuration(activeMin)}');
        }
        buf.writeln();
      } else if (timeRecord?.wake != null) {
        buf.writeln('-- ACTIVITY --');
        buf.writeln('  wake   ${timeRecord!.wake}');
        buf.writeln();
      }

      // 식사
      final completedMeals = timeRecord?.meals
          .where((m) => m.durationMin != null && m.durationMin! > 0)
          .toList() ?? [];
      if (completedMeals.isNotEmpty) {
        final totalMealMin = completedMeals.fold<int>(
            0, (s, m) => s + m.durationMin!);
        buf.writeln('-- MEALS --');
        buf.writeln('  count  ${completedMeals.length}');
        buf.writeln('  total  ${_fmtDuration(totalMealMin)}');
        for (int i = 0; i < completedMeals.length; i++) {
          final m = completedMeals[i];
          buf.writeln('  #${i + 1}     ${m.start} ~ ${m.end ?? "?"} (${m.durationMin}min)');
        }
        buf.writeln();
      }

      // 외출
      if (timeRecord?.outing != null && timeRecord?.returnHome != null) {
        final outMin = _timeDiffMin(timeRecord!.outing!, timeRecord.returnHome!);
        buf.writeln('-- OUTING --');
        buf.writeln('  out    ${timeRecord.outing}');
        buf.writeln('  back   ${timeRecord.returnHome}');
        if (outMin != null && outMin > 0) {
          buf.writeln('  total  ${_fmtDuration(outMin)}');
        }
        buf.writeln();
      }

      // 투두
      if (todoDaily != null && todoDaily.totalCount > 0) {
        buf.writeln('-- TODO --');
        buf.writeln('  done   ${todoDaily.completedCount}/${todoDaily.totalCount}');
        buf.writeln('  rate   ${(todoDaily.completionRate * 100).round()}%');
        buf.writeln();
      }

      // 습관
      if (orderData != null) {
        final activeHabits = orderData.habits
            .where((h) => !h.archived && !h.isSettled)
            .toList();
        if (activeHabits.isNotEmpty) {
          final doneToday = activeHabits
              .where((h) => h.isDoneOn(dateStr))
              .length;
          buf.writeln('-- HABITS --');
          buf.writeln('  done   $doneToday/${activeHabits.length}');
          for (final h in activeHabits) {
            final check = h.isDoneOn(dateStr) ? '[v]' : '[ ]';
            buf.writeln('  $check ${h.emoji} ${h.title} (${h.currentStreak}d)');
          }
          buf.writeln();
        }
      }

      // 격려 메시지
      buf.writeln(_pickEncouragement(dateStr, todoDaily));
      buf.writeln('========================');

      return buf.toString();
    } catch (e) {
      debugPrint('[Report] buildDailyReport error: $e');
      return '[$dateStr] Daily report error: $e';
    }
  }

  /// 일일 리포트 생성 + Telegram 전송
  Future<void> sendDailyReport(String dateStr) async {
    final report = await buildDailyReport(dateStr);
    await TelegramService().sendToMe(report);
    debugPrint('[Report] daily report sent for $dateStr');
  }

  // =====================================================================
  //  2. Weekly Report
  // =====================================================================

  /// 주간 리포트 생성 + Telegram 전송
  /// 최근 7일 데이터 집계
  Future<void> sendWeeklyReport() async {
    debugPrint('[Report] sendWeeklyReport');
    try {
      final fb = FirebaseService();
      final today = StudyDateUtils.todayKey();
      final todayDt = DateFormat('yyyy-MM-dd').parse(today);

      // 최근 7일 날짜 리스트
      final dates = List.generate(
          7, (i) => DateFormat('yyyy-MM-dd').format(todayDt.subtract(Duration(days: i))));

      // 데이터 수집
      final data = await fb.getStudyData();

      // 각 월의 history 데이터도 수집 (아카이브된 데이터 fallback)
      final months = <String>{};
      for (final d in dates) {
        months.add(d.substring(0, 7));
      }
      final historyByMonth = <String, Map<String, dynamic>?>{};
      for (final m in months) {
        historyByMonth[m] = await fb.getMonthHistory(m);
      }

      // 일별 데이터 수집
      final dailyWake = <String, String>{};
      final dailyBed = <String, String>{};
      final dailyMealCount = <String, int>{};
      final dailyMealMin = <String, int>{};
      int totalTodoDone = 0;
      int totalTodoCount = 0;

      for (final dateStr in dates) {
        // TimeRecord: study doc 우선, history fallback
        final tr = _extractTimeRecord(data, dateStr) ??
            _extractTimeRecordFromHistory(historyByMonth, dateStr);

        // 기상/취침
        if (tr?.wake != null) dailyWake[dateStr] = tr!.wake!;
        if (tr?.bedTime != null) dailyBed[dateStr] = tr!.bedTime!;

        // 식사
        final meals = tr?.meals ?? [];
        final doneMeals = meals.where((m) => m.durationMin != null && m.durationMin! > 0).toList();
        if (doneMeals.isNotEmpty) {
          dailyMealCount[dateStr] = doneMeals.length;
          dailyMealMin[dateStr] = doneMeals.fold<int>(0, (s, m) => s + m.durationMin!);
        }

        // Todo
        final td = await _extractTodos(data, dateStr) ??
            _extractTodosFromHistory(historyByMonth, dateStr);
        if (td != null && td.totalCount > 0) {
          totalTodoDone += td.completedCount;
          totalTodoCount += td.totalCount;
        }
      }

      // OrderData (습관)
      final orderData = _extractOrderData(data);

      // 기상/취침 평균
      final avgWake = _averageTime(dailyWake.values.toList());
      final avgBed = _averageTime(dailyBed.values.toList());

      // 식사 평균
      final mealCountList = dailyMealCount.values.toList();
      final mealMinList = dailyMealMin.values.toList();
      final avgMealCount = mealCountList.isNotEmpty
          ? (mealCountList.fold<int>(0, (s, v) => s + v) / mealCountList.length)
          : 0.0;
      final avgMealMin = mealMinList.isNotEmpty
          ? (mealMinList.fold<int>(0, (s, v) => s + v) / mealMinList.length).round()
          : 0;

      // ── 리포트 조립 ──
      final buf = StringBuffer();
      buf.writeln('===== WEEKLY REPORT =====');
      buf.writeln('${dates.last} ~ ${dates.first}');
      buf.writeln();

      // 투두
      if (totalTodoCount > 0) {
        buf.writeln('-- TODO --');
        buf.writeln('  done    $totalTodoDone/$totalTodoCount');
        buf.writeln('  rate    ${(totalTodoDone / totalTodoCount * 100).round()}%');
        buf.writeln();
      }

      // 습관 스트릭 top3
      if (orderData != null) {
        final activeHabits = orderData.habits
            .where((h) => !h.archived && !h.isSettled)
            .toList()
          ..sort((a, b) => b.currentStreak.compareTo(a.currentStreak));
        if (activeHabits.isNotEmpty) {
          buf.writeln('-- HABITS (top streak) --');
          final top = activeHabits.take(3);
          for (final h in top) {
            buf.writeln('  ${h.emoji} ${h.title}: ${h.currentStreak}d (best ${h.bestStreak}d)');
          }
          buf.writeln();
        }
      }

      // 식사 패턴
      if (dailyMealCount.isNotEmpty) {
        buf.writeln('-- MEALS --');
        buf.writeln('  avg count    ${avgMealCount.toStringAsFixed(1)}/day');
        buf.writeln('  avg duration ${_fmtDuration(avgMealMin)}/day');
        buf.writeln();
      }

      // 기상/취침 평균
      if (avgWake != null || avgBed != null) {
        buf.writeln('-- ROUTINE --');
        if (avgWake != null) buf.writeln('  avg wake  $avgWake');
        if (avgBed != null) buf.writeln('  avg bed   $avgBed');
        buf.writeln();
      }

      buf.writeln('=========================');

      await TelegramService().sendToMe(buf.toString());

      // 전송 기록
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weekly_report_last_sent', today);

      debugPrint('[Report] weekly report sent');
    } catch (e) {
      debugPrint('[Report] sendWeeklyReport error: $e');
    }
  }

  // =====================================================================
  //  3. Auto-schedule check
  // =====================================================================

  /// 일요일이고 이번 주 미전송이면 자동 발송
  Future<void> checkWeeklyReport() async {
    try {
      final now = DateTime.now();
      // 일요일 체크 (DateTime.sunday == 7)
      if (now.weekday != DateTime.sunday) return;

      final prefs = await SharedPreferences.getInstance();
      final lastSent = prefs.getString('weekly_report_last_sent');

      // 이번 주 월요일 날짜 계산
      final monday = now.subtract(Duration(days: now.weekday - 1));
      final mondayStr = DateFormat('yyyy-MM-dd').format(monday);

      // 이번 주 내에 이미 전송했으면 skip
      if (lastSent != null && lastSent.compareTo(mondayStr) >= 0) {
        debugPrint('[Report] weekly report already sent this week ($lastSent)');
        return;
      }

      debugPrint('[Report] Sunday auto-send weekly report');
      await sendWeeklyReport();
    } catch (e) {
      debugPrint('[Report] checkWeeklyReport error: $e');
    }
  }

  // =====================================================================
  //  Private helpers: Data extraction
  // =====================================================================

  /// study doc에서 특정 날짜의 TimeRecord 추출
  TimeRecord? _extractTimeRecord(Map<String, dynamic>? data, String dateStr) {
    if (data == null) return null;
    final raw = data['timeRecords'];
    if (raw is! Map) return null;
    final dayData = raw[dateStr];
    if (dayData is! Map) return null;
    try {
      return TimeRecord.fromMap(dateStr, Map<String, dynamic>.from(dayData));
    } catch (_) {
      return null;
    }
  }

  /// history에서 TimeRecord 추출
  TimeRecord? _extractTimeRecordFromHistory(
      Map<String, Map<String, dynamic>?> historyByMonth, String dateStr) {
    final month = dateStr.substring(0, 7);
    final day = dateStr.substring(8, 10);
    final history = historyByMonth[month];
    if (history == null) return null;
    final days = history['days'];
    if (days is! Map) return null;
    final dayData = days[day];
    if (dayData is! Map) return null;
    final tr = dayData['timeRecords'];
    if (tr is! Map) return null;
    try {
      return TimeRecord.fromMap(dateStr, Map<String, dynamic>.from(tr));
    } catch (_) {
      return null;
    }
  }

  /// study doc에서 Todo 추출
  Future<TodoDaily?> _extractTodos(Map<String, dynamic>? data, String dateStr) async {
    if (data == null) return null;
    final raw = data['todos'];
    if (raw is! Map) return null;
    final dayData = raw[dateStr];
    if (dayData is! Map) return null;
    try {
      return TodoDaily.fromMap(Map<String, dynamic>.from(dayData));
    } catch (_) {
      return null;
    }
  }

  /// history에서 Todo 추출
  TodoDaily? _extractTodosFromHistory(
      Map<String, Map<String, dynamic>?> historyByMonth, String dateStr) {
    final month = dateStr.substring(0, 7);
    final day = dateStr.substring(8, 10);
    final history = historyByMonth[month];
    if (history == null) return null;
    final days = history['days'];
    if (days is! Map) return null;
    final dayData = days[day];
    if (dayData is! Map) return null;
    final todos = dayData['todos'];
    if (todos is List && todos.isNotEmpty) {
      // history 형식: [{id, title, done, completedAt}, ...]
      final items = <TodoItem>[];
      for (final t in todos) {
        if (t is Map) {
          final m = Map<String, dynamic>.from(t);
          items.add(TodoItem(
            id: m['id'] ?? '',
            title: m['title'] ?? '',
            completed: m['done'] == true || m['completed'] == true,
            completedAt: m['completedAt'] as String?,
          ));
        }
      }
      return TodoDaily(date: dateStr, items: items);
    }
    return null;
  }

  /// study doc에서 OrderData 추출
  OrderData? _extractOrderData(Map<String, dynamic>? data) {
    if (data == null) return null;
    final raw = data['orderData'];
    if (raw is! Map) return null;
    try {
      return OrderData.fromMap(Map<String, dynamic>.from(raw));
    } catch (_) {
      return null;
    }
  }

  // =====================================================================
  //  Private helpers: Time calculation
  // =====================================================================

  /// HH:mm 형식 두 시각의 차이 (분)
  int? _timeDiffMin(String from, String to) {
    try {
      final fp = from.split(':');
      final tp = to.split(':');
      final fm = int.parse(fp[0]) * 60 + int.parse(fp[1]);
      final tm = int.parse(tp[0]) * 60 + int.parse(tp[1]);
      int diff = tm - fm;
      if (diff < 0) diff += 1440; // 자정 넘김
      return diff <= 720 ? diff : null; // 12시간 초과 비정상
    } catch (_) {
      return null;
    }
  }

  /// 분 -> "Xh Ym" 포맷
  String _fmtDuration(int minutes) {
    if (minutes <= 0) return '0m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  /// HH:mm 시각 리스트의 평균 계산
  String? _averageTime(List<String> times) {
    if (times.isEmpty) return null;
    int totalMin = 0;
    int count = 0;
    for (final t in times) {
      try {
        final parts = t.split(':');
        var min = int.parse(parts[0]) * 60 + int.parse(parts[1]);
        // 새벽 시간(0~4시)은 24시간 기준으로 보정
        if (min < 240) min += 1440;
        totalMin += min;
        count++;
      } catch (_) {}
    }
    if (count == 0) return null;
    var avg = totalMin ~/ count;
    if (avg >= 1440) avg -= 1440;
    final h = avg ~/ 60;
    final m = avg % 60;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  /// 요일 한글
  String _weekdayKr(String dateStr) {
    try {
      final dt = DateFormat('yyyy-MM-dd').parse(dateStr);
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[dt.weekday - 1];
    } catch (_) {
      return '';
    }
  }

  /// 격려 메시지 선택
  String _pickEncouragement(String dateStr, TodoDaily? todo) {
    final todoRate = todo != null && todo.totalCount > 0
        ? todo.completionRate
        : 0.0;
    if (todoRate >= 0.8) return 'Tasks cleared. Well done.';
    if (todoRate >= 0.5) return 'Solid effort today.';
    if (todoRate > 0) return 'Every small step counts.';
    return 'Rest well. Tomorrow is a new day.';
  }
}
