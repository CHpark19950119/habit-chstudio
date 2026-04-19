import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:intl/intl.dart';
import '../services/firebase_service.dart';
import '../models/models.dart';
import '../theme/botanical_theme.dart';
import '../utils/date_utils.dart';

part 'calendar_day_detail.dart';
part 'calendar_sheets.dart';

/// ═══════════════════════════════════════════════════════════════
/// 캘린더 — 일상 기록 + 저널 + 메모
/// ═══════════════════════════════════════════════════════════════

class CalendarScreen extends StatefulWidget {
  final bool embedded;
  const CalendarScreen({super.key, this.embedded = false});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  final _fb = FirebaseService();

  late DateTime _viewMonth;
  late DateTime _selectedDate;
  bool _loading = true;
  bool _loadLock = false;   // 중복 호출 방지 (UI 상태와 분리)
  bool _pendingReload = false; // ★ Bug #2 fix: 로딩 중 월 변경 시 재로드 예약

  List<String> _selectedMemos = [];
  TimeRecord? _selectedTimeRecord;
  List<String> _restDays = [];
  List<Map<String, dynamic>> _monthJournals = [];

  // ★ Todo 완료율 (날짜별)
  Map<String, double> _monthTodoRates = {};

  // ★ 홈데이 (외출 없는 날)
  Set<String> _monthHomeDays = {};

  // ★ 특별한 날 (노는 날 등)
  Set<String> _specialDayDates = {};

  late AnimationController _fadeCtrl;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;
  Color get _textMain => _dk ? BotanicalColors.textMainDark : BotanicalColors.textMain;
  Color get _textSub => _dk ? BotanicalColors.textSubDark : BotanicalColors.textSub;
  Color get _textMuted => _dk ? BotanicalColors.textMutedDark : BotanicalColors.textMuted;
  Color get _border => _dk ? BotanicalColors.borderDark : BotanicalColors.borderLight;
  Color get _accent => _dk ? BotanicalColors.lanternGold : BotanicalColors.primary;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _viewMonth = DateTime(now.year, now.month);
    _selectedDate = now;
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));
    _loadMonth();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  Future<void> _loadMonth({bool forceServer = false}) async {
    if (_loadLock) { _pendingReload = true; return; }
    _loadLock = true;
    _safeSetState(() => _loading = true);
    const t = Duration(seconds: 8);

    try {
      // Phase D: history + today doc only (study doc fallback removed)
      final monthKey = DateFormat('yyyy-MM').format(_viewMonth);

      // 1. history doc (past days)
      var historyData = await _fb.getMonthHistory(monthKey).timeout(t, onTimeout: () => null);
      if (historyData == null || (historyData['days'] as Map?)?.isEmpty != false) {
        final archiveData = await _fb.getArchive(monthKey).timeout(t, onTimeout: () => null);
        if (archiveData != null) {
          historyData = _archiveToHistoryFormat(archiveData, monthKey);
        }
      }

      // 2. today doc (current day only)
      final todayKey = StudyDateUtils.todayKey();
      Map<String, dynamic>? todayDoc;
      if (todayKey.startsWith(monthKey)) {
        todayDoc = await _fb.getTodayDoc();
      }

      // study doc (legacy read for restDays, journals, todos, homeDays)
      final studyData = await _fb.getStudyData(forceServer: forceServer).timeout(t, onTimeout: () => null);

      // restDays, journals (study doc legacy read)
      try {
        final raw = studyData?['restDays'] as List<dynamic>?;
        _restDays = raw?.map((e) => e.toString()).toList() ?? [];
      } catch (_) { _restDays = []; }

      try {
        final raw = studyData?['journals'] as List<dynamic>?;
        _monthJournals = raw?.map((j) => Map<String, dynamic>.from(j as Map)).toList() ?? [];
      } catch (_) { _monthJournals = []; }

      // Todo completion rate: history + today doc
      try {
        _monthTodoRates = {};
        // history todos
        if (historyData != null) {
          final days = historyData['days'] as Map<String, dynamic>? ?? {};
          for (final entry in days.entries) {
            final dateKey = '$monthKey-${entry.key}';
            final dayData = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null;
            if (dayData == null) continue;
            final todos = dayData['todos'];
            if (todos is List && todos.isNotEmpty) {
              final done = todos.where((i) => i is Map && (i['done'] == true || i['completed'] == true)).length;
              _monthTodoRates[dateKey] = done / todos.length;
            }
          }
        }
        // today doc todos
        if (todayDoc != null && todayKey.startsWith(monthKey)) {
          final todos = todayDoc['todos'];
          if (todos is List && todos.isNotEmpty) {
            final done = todos.where((i) => i is Map && (i['done'] == true || i['completed'] == true)).length;
            _monthTodoRates[todayKey] = done / todos.length;
          }
        }
      } catch (_) { _monthTodoRates = {}; }

      // home days: history + today
      try {
        _monthHomeDays = {};
        if (historyData != null) {
          final days = historyData['days'] as Map<String, dynamic>? ?? {};
          for (final entry in days.entries) {
            final dateKey = '$monthKey-${entry.key}';
            final dayData = entry.value is Map ? Map<String, dynamic>.from(entry.value as Map) : null;
            if (dayData == null) continue;
            final tr = dayData['timeRecords'];
            if (tr is Map) {
              final m = Map<String, dynamic>.from(tr);
              if (m['noOuting'] == true || (m['wake'] != null && m['outing'] == null)) {
                _monthHomeDays.add(dateKey);
              }
            }
          }
        }
        if (todayDoc != null && todayKey.startsWith(monthKey)) {
          final tr = todayDoc['timeRecords'];
          if (tr is Map) {
            final m = Map<String, dynamic>.from(tr);
            if (m['noOuting'] == true || (m['wake'] != null && m['outing'] == null)) {
              _monthHomeDays.add(todayKey);
            }
          }
        }
      } catch (_) { _monthHomeDays = {}; }

      // special day
      try {
        _specialDayDates = {};
        if (todayDoc != null && todayDoc['specialDay'] is Map) {
          final docDate = todayDoc['date'] as String?;
          if (docDate != null) _specialDayDates.add(docDate);
        }
      } catch (_) {}

      try { await _loadSelectedDay(); } catch (_) { _selectedMemos = []; }
    } catch (e) {
      debugPrint('[Calendar] _loadMonth error: $e');
    } finally {
      _loadLock = false;
      _safeSetState(() => _loading = false);
      if (mounted) _fadeCtrl.forward(from: 0);
      if (_pendingReload) {
        _pendingReload = false;
        _loadMonth(forceServer: true);
      }
    }
  }

  /// archive 문서 형식 → history 형식으로 변환
  Map<String, dynamic> _archiveToHistoryFormat(Map<String, dynamic> archive, String month) {
    final days = <String, Map<String, dynamic>>{};
    final trMap = archive['timeRecords'] as Map?;
    final todosMap = archive['todos'] as Map?;
    for (final dateKey in {...?trMap?.keys, ...?todosMap?.keys}) {
      final ds = dateKey.toString();
      if (ds.length < 10 || !ds.startsWith(month)) continue;
      final day = ds.substring(8, 10);
      days.putIfAbsent(day, () => {});
      if (trMap?[dateKey] != null) days[day]!['timeRecords'] = trMap![dateKey];
      if (todosMap?[dateKey] != null) {
        final td = todosMap![dateKey];
        if (td is Map) days[day]!['todos'] = td['items'] ?? [];
      }
    }
    return {'month': month, 'days': days};
  }

  Future<void> _loadSelectedDay() async {
    final ds = DateFormat('yyyy-MM-dd').format(_selectedDate);
    const t = Duration(seconds: 5);

    _selectedMemos = [];
    final fTimeRecords = _fb.getTimeRecords().timeout(t, onTimeout: () => <String, TimeRecord>{});

    try {
      final records = await fTimeRecords;
      _selectedTimeRecord = records[ds];
    } catch (_) {
      _selectedTimeRecord = null;
    }
  }

  void _changeMonth(int delta) {
    _safeSetState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + delta);
    });
    _loadMonth(forceServer: true);
  }

  void _selectDay(DateTime day) async {
    // 같은 날짜 재탭 방지
    if (day.year == _selectedDate.year &&
        day.month == _selectedDate.month &&
        day.day == _selectedDate.day) return;
    _safeSetState(() => _selectedDate = day);
    try {
      await _loadSelectedDay().timeout(const Duration(seconds: 8));
    } catch (_) {}
    _safeSetState(() {});
  }

  String get _selectedDateStr => DateFormat('yyyy-MM-dd').format(_selectedDate);
  List<Map<String, dynamic>> _journalsForDate(String ds) =>
    _monthJournals.where((j) => j['date'] == ds).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.embedded
        ? _buildContent()
        : Stack(children: [
            Positioned.fill(child: Container(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: _dk
                  ? [const Color(0xFF1C1410), const Color(0xFF0F172A)]
                  : [const Color(0xFFFDF9F2), const Color(0xFFF8FAFC)])))),
            SafeArea(child: _buildContent()),
          ]),
      floatingActionButton: _buildFab(),
    );
  }

  Widget _buildContent() {
    return Column(children: [
      _buildHeader(),
      Expanded(child: _loading
        ? Center(child: CircularProgressIndicator(color: _accent))
        : FadeTransition(
            opacity: CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                const SizedBox(height: 8),
                _buildMonthGrid(),
                const SizedBox(height: 12),
                _buildMonthSummary(),
                const SizedBox(height: 12),
                _buildSelectedDayCard(),
                const SizedBox(height: 80),
              ],
            ),
          )),
    ]);
  }

  // ══════════════════════════════════════════
  //  헤더 — 오늘 버튼
  // ══════════════════════════════════════════

  Widget _buildHeader() {
    final monthLabel = DateFormat('yyyy년 M월').format(_viewMonth);

    return Container(
      padding: EdgeInsets.fromLTRB(widget.embedded ? 16 : 8, 8, 16, 12),
      child: Row(children: [
        if (!widget.embedded)
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: _textSub)),
        if (widget.embedded) ...[
          Text('캘린더', style: TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: _textMain)),
          const SizedBox(width: 12),
        ],
        GestureDetector(
          onTap: () => _changeMonth(-1),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.chevron_left_rounded, size: 20, color: _textSub))),
        const SizedBox(width: 8),
        Text(monthLabel, style: TextStyle(
          fontSize: 18, fontWeight: FontWeight.w800, color: _textMain)),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _changeMonth(1),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _dk ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8)),
            child: Icon(Icons.chevron_right_rounded, size: 20, color: _textSub))),
        const Spacer(),
        // 오늘 버튼
        GestureDetector(
          onTap: () {
            final now = DateTime.now();
            final newMonth = DateTime(now.year, now.month);
            _selectedDate = now;
            if (_viewMonth.year == newMonth.year && _viewMonth.month == newMonth.month) {
              // 같은 월이면 서버에서 리프레시
              _loadMonth(forceServer: true);
            } else {
              _viewMonth = newMonth;
              _loadMonth(forceServer: true);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8)),
            child: Text('오늘', style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700, color: _accent)))),
      ]),
    );
  }

  // ══════════════════════════════════════════
  //  월간 그리드
  // ══════════════════════════════════════════

  Widget _buildMonthGrid() {
    final year = _viewMonth.year;
    final month = _viewMonth.month;
    final daysInMonth = DateTime(year, month + 1, 0).day;
    final startWeekday = DateTime(year, month, 1).weekday % 7;
    final today = DateTime.now();
    final todayStr = DateFormat('yyyy-MM-dd').format(today);
    final selectedStr = _selectedDateStr;

    const weekLabels = ['일', '월', '화', '수', '목', '금', '토'];

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border.withValues(alpha: 0.15)),
        boxShadow: _dk ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 16)]),
      child: Column(children: [
        // 요일 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(children: List.generate(7, (i) => Expanded(
            child: Center(child: Text(weekLabels[i], style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w700,
              color: i == 0 ? const Color(0xFFEF4444).withValues(alpha: 0.7)
                   : i == 6 ? const Color(0xFF3B82F6).withValues(alpha: 0.7)
                   : _textMuted)))))),
        ),
        const SizedBox(height: 6),
        // 날짜 그리드
        ...List.generate(6, (week) {
          final cells = List.generate(7, (dow) {
            final dayIdx = week * 7 + dow - startWeekday + 1;
            if (dayIdx < 1 || dayIdx > daysInMonth) {
              return const Expanded(child: SizedBox());
            }
            final dateStr = '$year-${month.toString().padLeft(2, '0')}-${dayIdx.toString().padLeft(2, '0')}';
            return Expanded(child: _buildDayCell(
              dateStr, dayIdx, dow, todayStr, selectedStr));
          });
          final hasValidDay = List.generate(7, (dow) {
            final dayIdx = week * 7 + dow - startWeekday + 1;
            return dayIdx >= 1 && dayIdx <= daysInMonth;
          }).any((v) => v);
          if (!hasValidDay) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(children: cells));
        }),
      ]),
    );
  }

  Widget _buildDayCell(String dateStr, int day, int dow,
      String todayStr, String selectedStr) {
    final today = DateTime.now();
    final date = DateTime(_viewMonth.year, _viewMonth.month, day);
    final isToday = dateStr == todayStr;
    final isSelected = dateStr == selectedStr;
    final isPast = date.isBefore(DateTime(today.year, today.month, today.day));
    final isRestDay = _restDays.contains(dateStr);
    final isHomeDay = _monthHomeDays.contains(dateStr);
    final isSpecialDay = _specialDayDates.contains(dateStr);
    final isSunday = dow == 0;

    return GestureDetector(
      onTap: () => _selectDay(date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 72,
        margin: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          color: isSelected
            ? _accent.withValues(alpha: _dk ? 0.15 : 0.08)
            : isSpecialDay
              ? const Color(0xFF8B5CF6).withValues(alpha: _dk ? 0.2 : 0.12)
            : isHomeDay
              ? const Color(0xFF5B7ABF).withValues(alpha: _dk ? 0.15 : 0.10)
              : _dk ? Colors.white.withValues(alpha: 0.02) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
              ? _accent.withValues(alpha: 0.5)
              : isHomeDay
                ? const Color(0xFF5B7ABF).withValues(alpha: 0.4)
                : isToday
                  ? _accent.withValues(alpha: 0.3)
                  : _border.withValues(alpha: 0.1),
            width: isSelected ? 2 : isHomeDay ? 1.5 : isToday ? 1.5 : 0.5),
          boxShadow: isSelected ? [
            BoxShadow(color: _accent.withValues(alpha: 0.1), blurRadius: 8)
          ] : null,
        ),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상단: 날짜
              Row(children: [
                Text('$day', style: TextStyle(
                  fontSize: 11,
                  fontWeight: isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? _accent
                       : isToday ? _accent
                       : isRestDay ? _textMuted
                       : isSunday ? const Color(0xFFEF4444).withValues(alpha: isPast ? 0.4 : 0.8)
                       : dow == 6 ? const Color(0xFF3B82F6).withValues(alpha: isPast ? 0.4 : 0.8)
                       : isPast ? _textMuted.withValues(alpha: 0.5)
                       : _textMain,
                  decoration: isRestDay ? TextDecoration.lineThrough : null,
                )),
                if (isSpecialDay)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Text('🎉', style: TextStyle(fontSize: 8))),
              ]),
              const Spacer(),
              // 중앙
              if (isSpecialDay)
                Center(child: Text('🎮 놀이', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w800,
                  color: const Color(0xFF8B5CF6)),
                ))
              else if (isSunday && !isToday && isPast)
                Center(child: Text('OFF', style: TextStyle(
                  fontSize: 8, fontWeight: FontWeight.w600,
                  color: _textMuted.withValues(alpha: 0.4)))),
              const Spacer(),
              // 하단: Todo 완료율 인디케이터
              if (_monthTodoRates.containsKey(dateStr))
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _dot(_monthTodoRates[dateStr]! >= 0.8
                    ? const Color(0xFF10B981)
                    : _monthTodoRates[dateStr]! >= 0.5
                      ? const Color(0xFFF59E0B)
                      : const Color(0xFFEF4444)),
                ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(Color c) => Container(
    width: 5, height: 5,
    margin: const EdgeInsets.symmetric(horizontal: 1.5),
    decoration: BoxDecoration(shape: BoxShape.circle, color: c.withValues(alpha: 0.85)));

  // ══════════════════════════════════════════
  //  월간 요약
  // ══════════════════════════════════════════

  Widget _buildMonthSummary() {
    final month = _viewMonth.month;
    final restCount = _restDays.where((d) => d.startsWith(DateFormat('yyyy-MM').format(_viewMonth))).length;
    final homeDayCount = _monthHomeDays.length;
    final specialCount = _specialDayDates.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.03) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border.withValues(alpha: 0.15))),
      child: Row(children: [
        const Text('📅', style: TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Text('${month}월 요약', style: TextStyle(
          fontSize: 12, fontWeight: FontWeight.w700, color: _textMain)),
        const Spacer(),
        _summaryChip('$homeDayCount', '집콕'),
        const SizedBox(width: 12),
        _summaryChip('$restCount', '쉬는날'),
        if (specialCount > 0) ...[
          const SizedBox(width: 12),
          _summaryChip('$specialCount', '특별'),
        ],
      ]),
    );
  }

  Widget _summaryChip(String value, String label) {
    return Column(children: [
      Text(value, style: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w800, color: _accent)),
      const SizedBox(height: 2),
      Text(label, style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.w600, color: _textMuted)),
    ]);
  }

  // ══════════════════════════════════════════
  //  FAB — 일정/메모 추가
  // ══════════════════════════════════════════

  Widget? _buildFab() {
    return FloatingActionButton.small(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AddEventMemoSheet(
            selectedDate: _selectedDate,
            onAdded: () => _loadMonth(forceServer: true)),
        );
      },
      backgroundColor: _accent,
      child: const Icon(Icons.add_rounded, color: Colors.white),
    );
  }

}

