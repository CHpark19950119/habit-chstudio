part of 'firebase_service.dart';

/// ═══════════════════════════════════════════════════════════
/// FIREBASE — Study Doc CRUD (timeRecords, studyTime, focusCycles, liveFocus, customTasks)
/// ═══════════════════════════════════════════════════════════
extension FirebaseStudyOps on FirebaseService {

  // ── timeRecords ──

  Future<Map<String, TimeRecord>> getTimeRecords() async {
    final data = await getStudyData();
    if (data == null || data[_timeRecordsField] == null) return {};
    final raw = Map<String, dynamic>.from(data[_timeRecordsField] as Map);
    return raw.map((date, value) => MapEntry(
          date, TimeRecord.fromMap(date, Map<String, dynamic>.from(value as Map))));
  }

  Future<void> updateTimeRecord(String date, TimeRecord record) async {
    // ── B1: TimeRecord 유효성 검증 ──
    final validation = TimeRecord.validate(record);
    if (!validation.isValid) {
      debugPrint('[FB] updateTimeRecord BLOCKED: $validation');
      // 경고만 — 포맷 에러는 차단, 순서 이상은 경고 후 진행
      final hasFormatError = validation.errors.any((e) => e.contains('포맷'));
      if (hasFormatError) return; // 포맷 에러 → 쓰기 차단
      debugPrint('[FB] updateTimeRecord WARNING: 순서 이상 감지, 쓰기 진행');
    }

    final recordMap = record.toMap();
    debugPrint('[FB] updateTimeRecord: $date');
    LocalCacheService().markWrite();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_timeRecordsField, () => {}) as Map)[date] = recordMap;
    _studyCacheTime = DateTime.now();
    await LocalCacheService().updateStudyField('$_timeRecordsField.$date', recordMap);
    if (date == StudyDateUtils.todayKey()) {
      // ★ dot-notation으로 개별 필드만 업데이트 (기존 필드 보존)
      final todayFields = <String, dynamic>{};
      for (final e in recordMap.entries) {
        todayFields['timeRecords.${e.key}'] = e.value;
      }
      FirestoreWriteQueue().enqueueDualWrite(
        _studyDoc, {'$_timeRecordsField.$date': recordMap},
        _todayDoc2, todayFields,
      );
    } else {
      FirestoreWriteQueue().enqueue(_studyDoc, {
        '$_timeRecordsField.$date': recordMap,
      });
    }
  }

  // ── studyTimeRecords ──

  Future<Map<String, StudyTimeRecord>> getStudyTimeRecords() async {
    final data = await getStudyData();
    if (data == null || data[_studyTimeRecordsField] == null) return {};
    final raw = Map<String, dynamic>.from(data[_studyTimeRecordsField] as Map);
    return raw.map((date, value) => MapEntry(
          date, StudyTimeRecord.fromMap(date, Map<String, dynamic>.from(value as Map))));
  }

  /// [effectiveDelta] — 이번에 추가/차감된 순공 분(분). 전달 시 today doc에
  /// FieldValue.increment 사용 (race-condition 방지). null이면 절대값 덮어쓰기.
  Future<void> updateStudyTimeRecord(String date, StudyTimeRecord record,
      {int? effectiveDelta}) async {
    if (record.effectiveMinutes == 0 && record.totalMinutes == 0) return;
    final recordMap = record.toMap();
    LocalCacheService().markWrite();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_studyTimeRecordsField, () => {}) as Map)[date] = recordMap;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_studyTimeRecordsField.$date', recordMap);
    if (date == StudyDateUtils.todayKey()) {
      final todayValue = effectiveDelta != null
          ? FieldValue.increment(effectiveDelta)
          : record.effectiveMinutes;
      FirestoreWriteQueue().enqueueDualWrite(
        _studyDoc, {'$_studyTimeRecordsField.$date': recordMap},
        _todayDoc2, {'studyTime.total': todayValue},
      );
    } else {
      FirestoreWriteQueue().enqueue(_studyDoc, {
        '$_studyTimeRecordsField.$date': recordMap,
      });
    }
  }

  // ── focusCycles ──

  Future<List<FocusCycle>> getFocusCycles(String date) async {
    final data = await getStudyData();
    if (data == null || data[_focusCyclesField] == null) return [];
    final raw = Map<String, dynamic>.from(data[_focusCyclesField] as Map);
    if (raw[date] == null) return [];
    final dayData = raw[date] as List<dynamic>;
    return dayData
        .map((c) => FocusCycle.fromMap(Map<String, dynamic>.from(c as Map)))
        .toList();
  }

  Future<void> saveFocusCycle(String date, FocusCycle cycle) async {
    final cycles = await getFocusCycles(date);
    final idx = cycles.indexWhere((c) => c.id == cycle.id);
    if (idx >= 0) {
      cycles[idx] = cycle;
    } else {
      cycles.add(cycle);
    }
    final cyclesList = cycles.map((c) => c.toMap()).toList();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_focusCyclesField, () => {}) as Map)[date] = cyclesList;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_focusCyclesField.$date', cyclesList);
    FirestoreWriteQueue().enqueue(_studyDoc, {
      '$_focusCyclesField.$date': cyclesList,
    });
    _cleanOldFocusCycles();
  }

  Future<void> overwriteFocusCycles(String date, List<FocusCycle> cycles) async {
    final cyclesList = cycles.map((c) => c.toMap()).toList();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_focusCyclesField, () => {}) as Map)[date] = cyclesList;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_focusCyclesField.$date', cyclesList);
    FirestoreWriteQueue().enqueue(_studyDoc, {
      '$_focusCyclesField.$date': cyclesList,
    });
  }

  Future<void> _cleanOldFocusCycles() async {
    try {
      final data = _studyCache ?? await getStudyData();
      if (data == null) return;
      final raw = data[_focusCyclesField];
      if (raw == null || raw is! Map) return;

      final cutoff = DateTime.now().subtract(const Duration(days: 7));
      final keysToDelete = <String, dynamic>{};
      for (final key in (raw as Map<String, dynamic>).keys) {
        try {
          if (DateTime.parse(key).isBefore(cutoff)) {
            keysToDelete['$_focusCyclesField.$key'] = FieldValue.delete();
          }
        } catch (_) {}
      }
      if (keysToDelete.isNotEmpty) {
        await _db.doc(_studyDoc).update(keysToDelete).timeout(const Duration(seconds: 5));
        final cached = _studyCache?[_focusCyclesField];
        if (cached is Map) {
          for (final key in keysToDelete.keys) {
            final dateKey = key.replaceFirst('$_focusCyclesField.', '');
            cached.remove(dateKey);
          }
        }
        debugPrint('[FocusClean] ${keysToDelete.length} old dates deleted');
      }
    } catch (e) {
      debugPrint('[FocusClean] cleanup failed (ignored): $e');
    }
  }

  // ── liveFocus (separate doc) ──

  Future<void> updateLiveFocus(String date, Map<String, dynamic> data) async {
    try {
      await _db.doc(_liveFocusDoc).set({
        ...data,
        'date': date,
        'lastModified': DateTime.now().millisecondsSinceEpoch,
      }).timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[FB] updateLiveFocus fail: $e');
    }
  }

  Future<void> clearLiveFocus(String date) async {
    try {
      await _db.doc(_liveFocusDoc).delete().timeout(const Duration(seconds: 3));
    } catch (e) {
      debugPrint('[FB] clearLiveFocus fail: $e');
    }
  }

  // ── customStudyTasks ──

  Future<List<String>> getCustomStudyTasks(String date) async {
    final data = await getStudyData();
    if (data == null || data[_customTasksField] == null) return [];
    final all = Map<String, dynamic>.from(data[_customTasksField] as Map);
    final dayTasks = all[date];
    if (dayTasks == null) return [];
    return (dayTasks as List<dynamic>).map((e) => e.toString()).toList();
  }

  Future<void> addCustomStudyTask(String date, String task) async {
    final tasks = await getCustomStudyTasks(date);
    tasks.add(task);
    await _saveCustomStudyTasks(date, tasks);
  }

  Future<void> editCustomStudyTask(String date, int index, String newTask) async {
    final tasks = await getCustomStudyTasks(date);
    if (index < 0 || index >= tasks.length) return;
    tasks[index] = newTask;
    await _saveCustomStudyTasks(date, tasks);
  }

  Future<void> deleteCustomStudyTask(String date, int index) async {
    final tasks = await getCustomStudyTasks(date);
    if (index < 0 || index >= tasks.length) return;
    tasks.removeAt(index);
    await _saveCustomStudyTasks(date, tasks);
  }

  Future<void> _saveCustomStudyTasks(String date, List<String> tasks) async {
    LocalCacheService().markWrite();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_customTasksField, () => {}) as Map)[date] = tasks;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_customTasksField.$date', tasks);
    FirestoreWriteQueue().enqueue(_studyDoc, {
      '$_customTasksField.$date': tasks,
    });
  }
}
