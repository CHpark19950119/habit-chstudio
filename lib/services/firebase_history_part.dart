part of 'firebase_service.dart';

/// ═══════════════════════════════════════════════════════════
/// FIREBASE — Today Doc + History + Archive + Rollover + RestDays
/// ═══════════════════════════════════════════════════════════
extension FirebaseHistoryOps on FirebaseService {

  // ── Today doc (Phase C) ──

  Future<Map<String, dynamic>?> getTodayDoc() async {
    if (_todayCache != null && _todayCacheTime != null &&
        DateTime.now().difference(_todayCacheTime!) < const Duration(minutes: 2)) {
      return _todayCache;
    }
    final result = await _cachedDocGet('today', _todayDocPath);
    if (result != null) {
      _todayCache = result;
      _todayCacheTime = DateTime.now();
    }
    return result;
  }

  /// 어제 bedTime 조회 (수면시간 계산용)
  Future<String?> getPrevBedTime(String yesterdayDate) async {
    try {
      // 1. study doc에서 어제 timeRecords 확인
      final data = await getStudyData();
      if (data != null) {
        final tr = data['timeRecords'] as Map<String, dynamic>?;
        if (tr != null && tr[yesterdayDate] != null) {
          final dayTr = Map<String, dynamic>.from(tr[yesterdayDate] as Map);
          if (dayTr['bedTime'] != null) return dayTr['bedTime'] as String;
        }
      }
      // 2. history doc fallback
      final parts = yesterdayDate.split('-');
      final monthKey = '${parts[0]}-${parts[1]}';
      final dayKey = parts[2];
      final histDoc = await _cachedDocGet('hist_$monthKey', 'users/$kUid/history/$monthKey');
      if (histDoc != null) {
        final days = histDoc['days'] as Map<String, dynamic>?;
        if (days != null && days[dayKey] != null) {
          final dayData = Map<String, dynamic>.from(days[dayKey] as Map);
          final tr = dayData['timeRecords'] as Map<String, dynamic>?;
          if (tr != null && tr['bedTime'] != null) return tr['bedTime'] as String;
        }
      }
    } catch (e) {
      debugPrint('[Firebase] getPrevBedTime: $e');
    }
    return null;
  }

  // ★ AUDIT FIX: B-01 — localDelta로 명시적 증감, FieldValue toString 파싱 제거
  Future<void> updateTodayField(String field, dynamic value, {num? localDelta}) async {
    LocalCacheService().markWrite();
    _todayCache ??= {};
    MapUtils.setNestedValue(_todayCache!, field, value, localDelta: localDelta);
    _todayCacheTime = DateTime.now();
    final localData = LocalCacheService().getGeneric('today') ?? {};
    MapUtils.setNestedValue(localData, field, value, localDelta: localDelta);
    await LocalCacheService().saveGeneric('today', localData);
    FirestoreWriteQueue().enqueue(_todayDocPath, {field: value});
  }

  Future<void> _setTodayDoc(Map<String, dynamic> data) async {
    LocalCacheService().markWrite();
    _todayCache = data;
    _todayCacheTime = DateTime.now();
    await LocalCacheService().saveGeneric('today', data);
    // ★ CF HTTP 경유 쓰기 (각 필드별) + SDK fallback
    try {
      final uri = Uri.parse('https://us-central1-cheonhong-studio.cloudfunctions.net/checkDoorManual')
          .replace(queryParameters: {'q': 'write', 'doc': 'today', 'field': '__SET__', 'value': json.encode(data)});
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        debugPrint('[FB] setTodayDoc via CF OK');
        return;
      }
    } catch (e) {
      debugPrint('[FB] setTodayDoc CF fail: $e — SDK fallback');
    }
    try {
      await _db.doc(_todayDocPath).set(data).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[FB] setTodayDoc SDK fail: $e');
    }
  }

  // ★ AUDIT FIX: P-03, B-01 — MapUtils.setNestedValue로 통합 (import는 part-of이므로 firebase_service.dart에서 처리)

  // ── History (monthly) ──

  Future<Map<String, dynamic>?> getMonthHistory(String month) async {
    return _cachedDocGet('history_$month', 'users/$kUid/history/$month');
  }

  Future<void> appendDayToHistory(String date, Map<String, dynamic> dayData) async {
    final month = date.substring(0, 7);
    final day = date.substring(8, 10);
    try {
      await _db.doc('users/$kUid/history/$month').set({
        'month': month,
        'days': {day: dayData},
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
      await LocalCacheService().removeGeneric('history_$month');
      debugPrint('[FB] appendDayToHistory: $date OK');
    } catch (e) {
      debugPrint('[FB] appendDayToHistory fail: $e');
    }
  }

  Future<void> appendFocusSessionToHistory(String date, Map<String, dynamic> session) async {
    final month = date.substring(0, 7);
    final day = date.substring(8, 10);
    try {
      await _db.doc('users/$kUid/history/$month').set({
        'month': month,
        'days': {day: {'focusSessions': FieldValue.arrayUnion([session])}},
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
      await LocalCacheService().removeGeneric('history_$month');
    } catch (e) {
      debugPrint('[FB] appendFocusSession fail: $e');
    }
  }

  Future<void> _recalculateMonthSummary(String month) async {
    try {
      final history = await _db.doc('users/$kUid/history/$month')
          .get().timeout(const Duration(seconds: 10));
      if (!history.exists || history.data() == null) return;
      final data = history.data()!;
      final days = data['days'] as Map<String, dynamic>? ?? {};
      final summary = _calculateMonthlySummary(days);
      await _db.doc('users/$kUid/history/$month').update({
        'summary': summary,
        'lastUpdated': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 10));
      debugPrint('[FB] recalculateMonthSummary: $month OK');
    } catch (e) {
      debugPrint('[FB] recalculateMonthSummary fail: $e');
    }
  }

  Map<String, dynamic> _calculateMonthlySummary(Map<String, dynamic> days) {
    int totalMinutes = 0;
    Map<String, int> subjectTotals = {};
    int todosCompleted = 0;
    int todosTotal = 0;
    int activeDays = 0;
    int bestMinutes = 0;
    String bestDay = '';

    for (final entry in days.entries) {
      final day = entry.key;
      if (entry.value is! Map) continue;
      final data = Map<String, dynamic>.from(entry.value as Map);

      final st = data['studyTime'];
      if (st is Map && st['total'] is num) {
        final mins = (st['total'] as num).toInt();
        totalMinutes += mins;
        activeDays++;
        if (mins > bestMinutes) { bestMinutes = mins; bestDay = day; }
        final subjects = st['subjects'];
        if (subjects is Map) {
          for (final s in subjects.entries) {
            subjectTotals[s.key.toString()] = (subjectTotals[s.key.toString()] ?? 0) + (s.value as num).toInt();
          }
        }
      }

      final str = data['studyTimeRecords'];
      if (st == null && str is Map) {
        final mins = (str['effectiveMinutes'] as num?)?.toInt() ?? 0;
        if (mins > 0) {
          totalMinutes += mins;
          activeDays++;
          if (mins > bestMinutes) { bestMinutes = mins; bestDay = day; }
        }
      }

      final t = data['todos'];
      if (t is List) {
        todosTotal += t.length;
        todosCompleted += t.where((i) => i is Map && i['done'] == true).length;
      }
    }

    return {
      'totalStudyMinutes': totalMinutes,
      'avgDailyMinutes': activeDays > 0 ? (totalMinutes / activeDays).round() : 0,
      'subjectTotals': subjectTotals,
      'bestDay': {'date': bestDay, 'minutes': bestMinutes},
      'todosCompletionRate': todosTotal > 0 ? (todosCompleted / todosTotal) : 0.0,
      'activeDays': activeDays,
    };
  }

  // ── Archive ──

  Future<void> autoArchive() async {
    final prefs = await SharedPreferences.getInstance();
    final today = StudyDateUtils.todayKey();
    final lastArchive = prefs.getString('last_archive_date');
    if (lastArchive == today) return;

    debugPrint('[Archive] starting...');
    final data = await getStudyData();
    if (data == null) return;

    final cutoffDt = DateTime.now().subtract(const Duration(days: 7));
    final cutoff = DateFormat('yyyy-MM-dd').format(cutoffDt);

    final archiveByMonth = <String, Map<String, dynamic>>{};
    final removals = <String, List<String>>{};
    int totalMoved = 0;

    for (final field in _archiveFields) {
      final raw = data[field];
      if (raw is! Map) continue;
      for (final dateKey in Map<String, dynamic>.from(raw).keys) {
        if (dateKey.compareTo(cutoff) < 0) {
          final month = dateKey.length >= 7 ? dateKey.substring(0, 7) : null;
          if (month == null) continue;
          archiveByMonth.putIfAbsent(month, () => {});
          archiveByMonth[month]!.putIfAbsent(field, () => <String, dynamic>{});
          (archiveByMonth[month]![field] as Map<String, dynamic>)[dateKey] = raw[dateKey];
          removals.putIfAbsent(field, () => []).add(dateKey);
          totalMoved++;
        }
      }
    }

    if (archiveByMonth.isEmpty) {
      await prefs.setString('last_archive_date', today);
      debugPrint('[Archive] nothing to move');
      return;
    }

    try {
      for (final entry in archiveByMonth.entries) {
        final month = entry.key;
        await _db.doc('users/$kUid/archive/$month')
            .set(entry.value, SetOptions(merge: true))
            .timeout(const Duration(seconds: 10));
        final historyDays = <String, Map<String, dynamic>>{};
        final archiveData = entry.value;
        final trMap = archiveData['timeRecords'] as Map?;
        final strMap = archiveData['studyTimeRecords'] as Map?;
        final fcMap = archiveData['focusCycles'] as Map?;
        final todosMap = archiveData['todos'] as Map?;
        for (final dateKey in {...?trMap?.keys, ...?strMap?.keys, ...?fcMap?.keys, ...?todosMap?.keys}) {
          if (dateKey.toString().length < 10) continue;
          final day = dateKey.toString().substring(8, 10);
          historyDays.putIfAbsent(day, () => {});
          if (trMap?[dateKey] != null) historyDays[day]!['timeRecords'] = trMap![dateKey];
          if (strMap?[dateKey] != null) {
            historyDays[day]!['studyTimeRecords'] = strMap![dateKey];
            final str = strMap[dateKey];
            if (str is Map) {
              final effMin = (str['effectiveMinutes'] as num?)?.toInt() ?? 0;
              historyDays[day]!['studyTime'] = {'total': effMin, 'subjects': {}};
            }
          }
          if (fcMap?[dateKey] != null) historyDays[day]!['focusSessions'] = fcMap![dateKey];
          if (todosMap?[dateKey] != null) {
            final td = todosMap![dateKey];
            if (td is Map) historyDays[day]!['todos'] = td['items'] ?? [];
          }
        }
        if (historyDays.isNotEmpty) {
          await _db.doc('users/$kUid/history/$month').set({
            'month': month,
            'days': historyDays,
            'lastUpdated': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
          await LocalCacheService().removeGeneric('history_$month');
        }
        debugPrint('[Archive] $month saved OK (archive + history)');
      }
    } catch (e) {
      debugPrint('[Archive] save failed: $e');
      return;
    }

    try {
      final updates = <String, dynamic>{};
      for (final entry in removals.entries) {
        for (final dateKey in entry.value) {
          updates['${entry.key}.$dateKey'] = FieldValue.delete();
        }
      }
      updates['lastModified'] = DateTime.now().millisecondsSinceEpoch;
      updates['lastDevice'] = 'android';
      await _db.doc(_studyDoc).update(updates)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[Archive] study cleanup failed: $e');
      return;
    }

    for (final entry in removals.entries) {
      final field = _studyCache?[entry.key];
      if (field is Map) {
        for (final key in entry.value) {
          field.remove(key);
        }
      }
    }
    _studyCacheTime = DateTime.now();
    if (_studyCache != null) {
      await LocalCacheService().saveStudyData(_studyCache!);
    }

    await prefs.setString('last_archive_date', today);
    debugPrint('[Archive] done: $totalMoved dates moved');
  }

  Future<Map<String, dynamic>?> getArchive(String yearMonth) async {
    final cached = LocalCacheService().getGeneric('archive_$yearMonth');
    if (cached != null && cached.isNotEmpty) return cached;
    // ★ AUDIT FIX: B-08 — Source.cache 읽기 제거 (persistenceEnabled: false이므로 항상 실패)
    try {
      final doc = await _db.doc('users/$kUid/archive/$yearMonth')
          .get().timeout(const Duration(seconds: 10));
      if (doc.exists && doc.data() != null) {
        LocalCacheService().saveGeneric('archive_$yearMonth', doc.data()!);
        return doc.data();
      }
    } catch (e) {
      debugPrint('[FB] getArchive fail: $e');
    }
    return null;
  }

  // ── Rest days ──

  Future<List<String>> getRestDays() async {
    final data = await getStudyData();
    if (data == null || data[_restDaysField] == null) return [];
    final raw = data[_restDaysField] as List<dynamic>;
    return raw.map((e) => e.toString()).toList();
  }

  Future<bool> toggleRestDay(String date) async {
    final days = await getRestDays();
    final isRest = days.contains(date);
    if (isRest) {
      days.remove(date);
    } else {
      days.add(date);
    }
    LocalCacheService().markWrite();
    _studyCache ??= {};
    _studyCache![_restDaysField] = days;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField(_restDaysField, days);
    FirestoreWriteQueue().enqueue(_studyDoc, {_restDaysField: days});
    return !isRest;
  }

  // ── 4AM Rollover (Phase D: simplified, verified archiving) ──

  static bool _rollingOver = false;
  static DateTime? _rolloverStartTime;

  Future<void> checkDayRollover() async {
    if (_rollingOver) {
      // 10-minute timeout for stuck rollover
      if (_rolloverStartTime != null &&
          DateTime.now().difference(_rolloverStartTime!) > const Duration(minutes: 10)) {
        debugPrint('[Rollover] stuck > 10min, force-releasing');
        _rollingOver = false;
      } else {
        debugPrint('[Rollover] already running, skip');
        return;
      }
    }
    _rollingOver = true;
    _rolloverStartTime = DateTime.now();
    try {
      // Clear stuck _rolloverInProgress flag
      try {
        final data = await _cfRead('today');
        if (data != null && data['_rolloverInProgress'] == true) {
          debugPrint('[Rollover] stuck flag found, clearing');
          await http.get(Uri.parse('$_cfBaseUrl?q=write&doc=today&field=_rolloverInProgress&value=__DELETE__'))
              .timeout(const Duration(seconds: 5));
          _todayCache = null;
          _todayCacheTime = null;
        }
      } catch (e) {
        debugPrint('[Rollover] stuck flag check error: $e');
      }

      // Fresh read from server (bypass cache)
      invalidateTodayCache();
      final todayData = await getTodayDoc();
      if (todayData == null) return;

      final savedDate = todayData['date'] as String?;
      final currentDate = StudyDateUtils.todayKey();

      if (savedDate == null || savedDate == currentDate) return;

      debugPrint('[Rollover] $savedDate -> $currentDate archiving...');

      // Set rollover flag (date NOT changed yet)
      await _db.doc(_todayDocPath).update({
        '_rolloverInProgress': true,
      }).timeout(const Duration(seconds: 5));

      try {
        // 1. Prepare archive data (remove internal fields)
        final archiveData = Map<String, dynamic>.from(todayData);
        archiveData.remove('_rolloverInProgress');
        archiveData.remove('date');
        archiveData.remove('lastModified');
        archiveData.remove('lastDevice');

        // 2. Archive to history
        await appendDayToHistory(savedDate, archiveData);

        // 3. Verify archiving succeeded before resetting
        final month = savedDate.substring(0, 7);
        final day = savedDate.substring(8, 10);
        final histDoc = await _db.doc('users/$kUid/history/$month')
            .get().timeout(const Duration(seconds: 10));
        final histData = histDoc.data();
        final archived = (histData?['days'] as Map<String, dynamic>?)?[day];
        if (archived == null) {
          debugPrint('[Rollover] ABORT: archive verification failed, history/$month.days.$day is null');
          return; // DO NOT reset today doc
        }
        debugPrint('[Rollover] archive verified: history/$month.days.$day exists');

        // 4. Recalculate month summary (fire-and-forget)
        _recalculateMonthSummary(month);

        // 5. Reset today doc for new day
        final newToday = <String, dynamic>{
          'date': currentDate,
          'timeRecords': <String, dynamic>{},
          'studyTime': {'total': 0, 'subjects': <String, dynamic>{}},
          'todos': <Map<String, dynamic>>[],
          'orderData': todayData['orderData'] ?? {},
          'lastModified': DateTime.now().millisecondsSinceEpoch,
          'lastDevice': 'android',
        };
        await _setTodayDoc(newToday);
        debugPrint('[Rollover] archiving done');
      } finally {
        // Always clear rollover flag
        try {
          await _db.doc(_todayDocPath).update({
            '_rolloverInProgress': FieldValue.delete(),
          }).timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[Rollover] error: $e');
    } finally {
      _rollingOver = false;
      _rolloverStartTime = null;
    }
  }
}
