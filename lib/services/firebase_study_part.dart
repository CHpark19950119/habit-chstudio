part of 'firebase_service.dart';

/// ═══════════════════════════════════════════════════════════
/// FIREBASE — Study Doc CRUD (timeRecords, studyTime, focusCycles, liveFocus, customTasks)
/// Phase D: today doc = single source of truth. study doc = read-only legacy.
/// ═══════════════════════════════════════════════════════════
extension FirebaseStudyOps on FirebaseService {

  // ── timeRecords ──

  Future<Map<String, TimeRecord>> getTimeRecords() async {
    // Phase D: today doc first, study doc legacy fallback (read-only)
    final todayData = await getTodayDoc();
    if (todayData != null && todayData['timeRecords'] is Map) {
      final todayTr = Map<String, dynamic>.from(todayData['timeRecords'] as Map);
      final todayDate = todayData['date'] as String?;
      if (todayDate != null && todayTr.isNotEmpty) {
        final result = <String, TimeRecord>{};
        try {
          result[todayDate] = TimeRecord.fromMap(todayDate, todayTr);
        } catch (_) {}
        // study doc legacy read for past dates
        final studyData = await getStudyData();
        if (studyData != null && studyData[_timeRecordsField] is Map) {
          final raw = Map<String, dynamic>.from(studyData[_timeRecordsField] as Map);
          for (final e in raw.entries) {
            if (e.key != todayDate && e.value is Map) {
              try {
                result[e.key] = TimeRecord.fromMap(e.key, Map<String, dynamic>.from(e.value as Map));
              } catch (_) {}
            }
          }
        }
        return result;
      }
    }
    // fallback: study doc (legacy)
    final data = await getStudyData();
    if (data == null || data[_timeRecordsField] == null) return {};
    final raw = Map<String, dynamic>.from(data[_timeRecordsField] as Map);
    final result = <String, TimeRecord>{};
    for (final e in raw.entries) {
      if (e.value is Map) {
        try {
          result[e.key] = TimeRecord.fromMap(e.key, Map<String, dynamic>.from(e.value as Map));
        } catch (_) {}
      }
    }
    return result;
  }

  Future<void> updateTimeRecord(String date, TimeRecord record) async {
    final validation = TimeRecord.validate(record);
    if (!validation.isValid) {
      debugPrint('[FB] updateTimeRecord BLOCKED: $validation');
      final hasFormatError = validation.errors.any((e) => e.contains('포맷'));
      if (hasFormatError) return;
      debugPrint('[FB] updateTimeRecord WARNING: 순서 이상 감지, 쓰기 진행');
    }

    final recordMap = record.toMap();
    debugPrint('[FB] updateTimeRecord: $date');
    LocalCacheService().markWrite();

    // Phase D: today doc only (single source of truth)
    if (date == StudyDateUtils.todayKey()) {
      final todayFields = <String, dynamic>{};
      for (final e in recordMap.entries) {
        todayFields['timeRecords.${e.key}'] = e.value;
      }
      _todayCache ??= {};
      final trCache = Map<String, dynamic>.from(
          (_todayCache!['timeRecords'] as Map?) ?? {});
      trCache.addAll(recordMap);
      _todayCache!['timeRecords'] = trCache;
      _todayCacheTime = DateTime.now();
      LocalCacheService().saveGeneric('today', _todayCache!);
      FirestoreWriteQueue().enqueue(_todayDocPath, todayFields);
    } else {
      debugPrint('[FB] updateTimeRecord: past date $date -> history');
      await appendDayToHistory(date, {'timeRecords': recordMap});
    }
  }

  // ── studyTimeRecords ──

  Future<Map<String, StudyTimeRecord>> getStudyTimeRecords() async {
    // Phase D: study doc legacy read (past data access)
    final data = await getStudyData();
    if (data == null || data[_studyTimeRecordsField] == null) return {};
    final raw = Map<String, dynamic>.from(data[_studyTimeRecordsField] as Map);
    final result = <String, StudyTimeRecord>{};
    for (final e in raw.entries) {
      if (e.value is Map) {
        try {
          result[e.key] = StudyTimeRecord.fromMap(e.key, Map<String, dynamic>.from(e.value as Map));
        } catch (_) {}
      }
    }
    return result;
  }

  /// [effectiveDelta] -- delta minutes. Uses FieldValue.increment when provided.
  Future<void> updateStudyTimeRecord(String date, StudyTimeRecord record,
      {int? effectiveDelta}) async {
    if (record.effectiveMinutes == 0 && record.totalMinutes == 0) return;
    LocalCacheService().markWrite();

    // Phase D: today doc only
    if (date == StudyDateUtils.todayKey()) {
      final todayValue = effectiveDelta != null
          ? FieldValue.increment(effectiveDelta)
          : record.effectiveMinutes;
      _todayCache ??= {};
      if (effectiveDelta != null) {
        MapUtils.setNestedValue(_todayCache!, 'studyTime.total', null, localDelta: effectiveDelta);
      } else {
        MapUtils.setNestedValue(_todayCache!, 'studyTime.total', record.effectiveMinutes);
      }
      _todayCacheTime = DateTime.now();
      LocalCacheService().saveGeneric('today', _todayCache!);
      FirestoreWriteQueue().enqueue(_todayDocPath, {'studyTime.total': todayValue});
    }
    // past dates: ignored (already in history or rollover handles it)
  }

  // ── focusCycles (legacy read — ObjectBox is primary now) ──

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
    // Phase D: study doc still used for focusCycles (not in today doc)
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
        FirestoreWriteQueue().enqueue(_studyDoc, keysToDelete);
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

  // ── customStudyTasks (still in study doc — low-frequency data) ──

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
