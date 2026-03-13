/// ===================================================================
/// CHEONHONG STUDIO -- Report Service
/// 일일 / 주간 통계 리포트 자동 생성 + Telegram 전송
/// ===================================================================

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../models/order_models.dart';
import '../models/plan_models.dart';
import '../utils/study_date_utils.dart';
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

      // ── StudyTimeRecord (순공시간) ──
      final studyTimeRecord = _extractStudyTimeRecord(data, dateStr);

      // ── Todo ──
      final todoDaily = await _extractTodos(data, dateStr);

      // ── OrderData (습관) ──
      final orderData = _extractOrderData(data);

      // ── FocusCycles ──
      final focusCycles = _extractFocusCycles(data, dateStr);

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

      // 순공시간
      if (timeRecord?.study != null) {
        final studyEnd = timeRecord!.studyEnd;
        buf.writeln('-- STUDY --');
        buf.writeln('  start  ${timeRecord.study}');
        if (studyEnd != null) {
          buf.writeln('  end    $studyEnd');
          final grossMin = _timeDiffMin(timeRecord.study!, studyEnd);
          final mealMin = timeRecord.totalMealMinutes;
          final netMin = grossMin != null ? (grossMin - mealMin).clamp(0, 1440) : null;
          if (grossMin != null) {
            buf.writeln('  gross  ${_fmtDuration(grossMin)}');
          }
          if (netMin != null && netMin > 0) {
            buf.writeln('  net    ${_fmtDuration(netMin)}');
          }
        }
        // studyTimeRecords의 effectiveMinutes (포커스 기반 순공)
        if (studyTimeRecord != null && studyTimeRecord.effectiveMinutes > 0) {
          buf.writeln('  focus  ${_fmtDuration(studyTimeRecord.effectiveMinutes)}');
        }
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

      // 포커스 세션
      if (focusCycles.isNotEmpty) {
        final totalFocusMin = focusCycles.fold<int>(
            0, (s, c) => s + c.effectiveMin);
        buf.writeln('-- FOCUS --');
        buf.writeln('  sessions  ${focusCycles.length}');
        if (totalFocusMin > 0) {
          buf.writeln('  total     ${_fmtDuration(totalFocusMin)}');
        }
        buf.writeln();
      }

      // 격려 메시지
      buf.writeln(_pickEncouragement(dateStr, todoDaily, studyTimeRecord));
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
      final dailyStudyMin = <String, int>{};
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

        // StudyTimeRecord
        final str = _extractStudyTimeRecord(data, dateStr) ??
            _extractStudyTimeRecordFromHistory(historyByMonth, dateStr);

        // 순공시간 계산: effectiveMinutes 우선, 없으면 study~studyEnd - meals
        int studyMin = 0;
        if (str != null && str.effectiveMinutes > 0) {
          studyMin = str.effectiveMinutes;
        } else if (tr?.study != null && tr?.studyEnd != null) {
          final gross = _timeDiffMin(tr!.study!, tr.studyEnd!);
          final mealMin = tr.totalMealMinutes;
          studyMin = gross != null ? (gross - mealMin).clamp(0, 1440) : 0;
        }
        // history의 studyTime.total fallback
        if (studyMin == 0) {
          studyMin = _extractStudyMinFromHistory(historyByMonth, dateStr);
        }
        dailyStudyMin[dateStr] = studyMin;

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

      // ── 집계 ──
      final totalStudy = dailyStudyMin.values.fold<int>(0, (s, v) => s + v);
      final studyDays = dailyStudyMin.values.where((v) => v > 0).length;
      final avgStudy = studyDays > 0 ? (totalStudy / studyDays).round() : 0;

      // 최다/최소 공부일
      String? bestDay, worstDay;
      int bestMin = 0, worstMin = 99999;
      for (final entry in dailyStudyMin.entries) {
        if (entry.value > bestMin) {
          bestMin = entry.value;
          bestDay = entry.key;
        }
        if (entry.value > 0 && entry.value < worstMin) {
          worstMin = entry.value;
          worstDay = entry.key;
        }
      }
      if (worstMin == 99999) { worstMin = 0; worstDay = null; }

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

      // 지난주 대비 트렌드 계산
      final prevDates = List.generate(
          7, (i) => DateFormat('yyyy-MM-dd').format(todayDt.subtract(Duration(days: i + 7))));
      int prevTotalStudy = 0;
      for (final d in prevDates) {
        final pStr = _extractStudyTimeRecord(data, d) ??
            _extractStudyTimeRecordFromHistory(historyByMonth, d);
        if (pStr != null && pStr.effectiveMinutes > 0) {
          prevTotalStudy += pStr.effectiveMinutes;
        } else {
          prevTotalStudy += _extractStudyMinFromHistory(historyByMonth, d);
        }
      }

      // ── 리포트 조립 ──
      final buf = StringBuffer();
      buf.writeln('===== WEEKLY REPORT =====');
      buf.writeln('${dates.last} ~ ${dates.first}');
      buf.writeln();

      // 공부시간
      buf.writeln('-- STUDY TIME --');
      buf.writeln('  total   ${_fmtDuration(totalStudy)}');
      buf.writeln('  avg/day ${_fmtDuration(avgStudy)}');
      buf.writeln('  days    $studyDays/7');
      if (bestDay != null) {
        buf.writeln('  best    ${bestDay.substring(5)} (${_fmtDuration(bestMin)})');
      }
      if (worstDay != null && worstDay != bestDay) {
        buf.writeln('  worst   ${worstDay.substring(5)} (${_fmtDuration(worstMin)})');
      }
      buf.writeln();

      // 트렌드
      buf.writeln('-- TREND --');
      if (prevTotalStudy > 0) {
        final diff = totalStudy - prevTotalStudy;
        final pct = (diff / prevTotalStudy * 100).round();
        final arrow = diff >= 0 ? '+' : '';
        buf.writeln('  vs last week  $arrow${_fmtDuration(diff.abs())} ($arrow$pct%)');
      } else {
        buf.writeln('  vs last week  (no data)');
      }
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

      // 일별 미니 바 차트
      buf.writeln('-- DAILY --');
      for (final d in dates.reversed) {
        final min = dailyStudyMin[d] ?? 0;
        final bar = _miniBar(min, 480); // 8시간 기준
        buf.writeln('  ${d.substring(5)} $bar ${_fmtDuration(min)}');
      }
      buf.writeln();
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

  /// study doc에서 StudyTimeRecord 추출
  StudyTimeRecord? _extractStudyTimeRecord(Map<String, dynamic>? data, String dateStr) {
    if (data == null) return null;
    final raw = data['studyTimeRecords'];
    if (raw is! Map) return null;
    final dayData = raw[dateStr];
    if (dayData is! Map) return null;
    try {
      return StudyTimeRecord.fromMap(dateStr, Map<String, dynamic>.from(dayData));
    } catch (_) {
      return null;
    }
  }

  /// history에서 StudyTimeRecord 추출
  StudyTimeRecord? _extractStudyTimeRecordFromHistory(
      Map<String, Map<String, dynamic>?> historyByMonth, String dateStr) {
    final month = dateStr.substring(0, 7);
    final day = dateStr.substring(8, 10);
    final history = historyByMonth[month];
    if (history == null) return null;
    final days = history['days'];
    if (days is! Map) return null;
    final dayData = days[day];
    if (dayData is! Map) return null;
    final str = dayData['studyTimeRecords'];
    if (str is! Map) return null;
    try {
      return StudyTimeRecord.fromMap(dateStr, Map<String, dynamic>.from(str));
    } catch (_) {
      return null;
    }
  }

  /// history의 studyTime.total에서 분 추출
  int _extractStudyMinFromHistory(
      Map<String, Map<String, dynamic>?> historyByMonth, String dateStr) {
    final month = dateStr.substring(0, 7);
    final day = dateStr.substring(8, 10);
    final history = historyByMonth[month];
    if (history == null) return 0;
    final days = history['days'];
    if (days is! Map) return 0;
    final dayData = days[day];
    if (dayData is! Map) return 0;
    final st = dayData['studyTime'];
    if (st is Map && st['total'] is num) {
      return (st['total'] as num).toInt();
    }
    return 0;
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

  /// study doc에서 FocusCycles 추출
  List<FocusCycle> _extractFocusCycles(Map<String, dynamic>? data, String dateStr) {
    if (data == null) return [];
    final raw = data['focusCycles'];
    if (raw is! Map) return [];
    final dayData = raw[dateStr];
    if (dayData is! List) return [];
    try {
      return dayData
          .map((c) => FocusCycle.fromMap(Map<String, dynamic>.from(c as Map)))
          .toList();
    } catch (_) {
      return [];
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

  /// 미니 바 차트 (최대 maxMin 기준 8칸)
  String _miniBar(int minutes, int maxMin) {
    const barLen = 8;
    final filled = maxMin > 0
        ? (minutes / maxMin * barLen).round().clamp(0, barLen)
        : 0;
    return '${'#' * filled}${'-' * (barLen - filled)}';
  }

  /// 격려 메시지 선택
  String _pickEncouragement(
      String dateStr, TodoDaily? todo, StudyTimeRecord? str) {
    final effectiveMin = str?.effectiveMinutes ?? 0;
    final todoRate = todo != null && todo.totalCount > 0
        ? todo.completionRate
        : 0.0;

    if (effectiveMin >= 480 && todoRate >= 0.8) {
      return 'Perfect day. Keep going.';
    }
    if (effectiveMin >= 360) {
      return 'Solid effort today.';
    }
    if (effectiveMin >= 240) {
      return 'Good start. Push harder tomorrow.';
    }
    if (todoRate >= 0.8) {
      return 'Tasks cleared. Well done.';
    }
    if (effectiveMin > 0) {
      return 'Every minute counts. Build on this.';
    }
    return 'Rest well. Tomorrow is a new day.';
  }
}
