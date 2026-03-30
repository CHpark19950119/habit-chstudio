import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../utils/study_date_utils.dart';
import 'firebase_service.dart';

/// ═══════════════════════════════════════════════════════════
/// DataAuditService — 앱 시작 시 데이터 무결성 검증 + 자동 복구
/// 1회/일 실행, 결과를 SharedPreferences에 저장
/// ═══════════════════════════════════════════════════════════
class DataAuditService {
  static final DataAuditService _i = DataAuditService._();
  factory DataAuditService() => _i;
  DataAuditService._();

  static void _log(String msg) => debugPrint('[DataAudit] $msg');

  /// 앱 시작 시 호출 — 1일 1회만 실행
  Future<void> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final lastAudit = prefs.getString('last_data_audit');
    final today = StudyDateUtils.todayKey();
    if (lastAudit == today) return;

    _log('감사 시작: $today');
    final results = <String>[];

    try {
      await _auditTimeRecords(results);
      await _auditDualDocSync(results);
      await _auditStaleData(results);
      await _auditOrderData(results);
    } catch (e) {
      _log('감사 에러: $e');
      results.add('ERROR: $e');
    }

    await prefs.setString('last_data_audit', today);
    await prefs.setString('last_audit_results', results.join('\n'));
    _log('감사 완료: ${results.length}건 발견');
    for (final r in results) { _log('  $r'); }
  }

  /// 강제 실행 (설정 화면에서)
  Future<List<String>> runForced() async {
    final results = <String>[];
    try {
      await _auditTimeRecords(results);
      await _auditDualDocSync(results);
      await _auditStaleData(results);
      await _auditOrderData(results);
    } catch (e) {
      results.add('ERROR: $e');
    }
    return results;
  }

  // ═══════════════════════════════════════════
  //  1. TimeRecord 검증 — 포맷/순서 이상 수정
  // ═══════════════════════════════════════════

  Future<void> _auditTimeRecords(List<String> results) async {
    try {
      final fb = FirebaseService();
      final records = await fb.getTimeRecords()
          .timeout(const Duration(seconds: 10));

      final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
      final keysToRemove = <String>[];
      final keysToFix = <String, TimeRecord>{};

      for (final entry in records.entries) {
        final date = entry.key;
        final tr = entry.value;

        // 1a. 잘못된 날짜 키 제거
        if (!dateRegex.hasMatch(date)) {
          keysToRemove.add(date);
          results.add('REMOVE: 잘못된 날짜 키 "$date"');
          continue;
        }

        // 1b. TimeRecord 검증
        final validation = TimeRecord.validate(tr);
        if (!validation.isValid) {
          final hasFormat = validation.errors.any((e) => e.contains('포맷'));
          if (hasFormat) {
            // 포맷 깨진 필드만 null로 교체
            final fixed = _fixBadFormats(tr);
            if (fixed != null) {
              keysToFix[date] = fixed;
              results.add('FIX: $date 포맷 수정 (${validation.errors.join(', ')})');
            }
          } else {
            results.add('WARN: $date 순서 이상 (${validation.errors.join(', ')})');
          }
        }

        // 1c. 빈 레코드 정리 (모든 필드 null)
        if (tr.wake == null && tr.study == null && tr.outing == null &&
            tr.bedTime == null && tr.meals.isEmpty) {
          keysToRemove.add(date);
          results.add('REMOVE: $date 빈 레코드');
        }
      }

      // 적용
      if (keysToRemove.isNotEmpty || keysToFix.isNotEmpty) {
        final updates = <String, dynamic>{};
        for (final key in keysToRemove) {
          updates['timeRecords.$key'] = FieldValue.delete();
        }
        for (final entry in keysToFix.entries) {
          updates['timeRecords.${entry.key}'] = entry.value.toMap();
        }
        if (updates.isNotEmpty) {
          await FirebaseFirestore.instance
              .doc('users/${fb.uid}/data/study')
              .update(updates)
              .timeout(const Duration(seconds: 10));
          fb.invalidateStudyCache();
          results.add('APPLIED: ${keysToRemove.length}건 삭제, ${keysToFix.length}건 수정');
        }
      }
    } catch (e) {
      results.add('timeRecords 감사 실패: $e');
    }
  }

  /// 포맷 깨진 필드 null로 교체
  TimeRecord? _fixBadFormats(TimeRecord tr) {
    final timeRe = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
    bool changed = false;

    String? fix(String? v) {
      if (v == null) return null;
      if (timeRe.hasMatch(v)) return v;
      changed = true;
      return null;
    }

    final fixed = TimeRecord(
      date: tr.date,
      wake: fix(tr.wake),
      study: fix(tr.study),
      studyEnd: fix(tr.studyEnd),
      outing: fix(tr.outing),
      returnHome: fix(tr.returnHome),
      arrival: tr.arrival,
      bedTime: fix(tr.bedTime),
      meals: tr.meals,
      noOuting: tr.noOuting,
    );
    return changed ? fixed : null;
  }

  // ═══════════════════════════════════════════
  //  2. 듀얼 문서 일관성 체크
  // ═══════════════════════════════════════════

  Future<void> _auditDualDocSync(List<String> results) async {
    try {
      final fb = FirebaseService();
      final todayKey = StudyDateUtils.todayKey();

      final studyData = await fb.getStudyData();
      final todayData = await fb.getTodayDoc();
      if (studyData == null || todayData == null) return;

      // today doc의 date 필드 확인
      final todayDate = todayData['date'] as String?;
      if (todayDate != null && todayDate != todayKey) {
        results.add('WARN: today doc date=$todayDate != todayKey=$todayKey (rollover 필요?)');
      }

      // timeRecords 비교
      final sTR = studyData['timeRecords'];
      final tTR = todayData['timeRecords'];
      if (sTR is Map && tTR is Map) {
        final sMap = sTR[todayKey];
        if (sMap is Map && tTR is Map) {
          final sFields = Map<String, dynamic>.from(sMap);
          final tFields = Map<String, dynamic>.from(tTR);

          for (final key in ['wake', 'study', 'studyEnd', 'outing', 'returnHome', 'bedTime']) {
            if (sFields[key] != tFields[key]) {
              results.add('SYNC: $key study=${sFields[key]} today=${tFields[key]}');

              // 최신 기준 동기화
              final sMod = studyData['lastModified'] as int? ?? 0;
              final tMod = todayData['lastModified'] as int? ?? 0;
              if (sMod >= tMod) {
                // ★ dot-notation으로 개별 필드만 동기화 (기존 필드 보존)
                for (final key in ['wake', 'study', 'studyEnd', 'outing', 'returnHome', 'bedTime']) {
                  if (sFields[key] != null) {
                    await fb.updateTodayField('timeRecords.$key', sFields[key]);
                  }
                }
                results.add('  → study doc 기준으로 today 동기화 (필드별)');
              } else {
                final tr = TimeRecord.fromMap(todayKey, tFields);
                await fb.updateTimeRecord(todayKey, tr);
                results.add('  → today doc 기준으로 study 동기화');
              }
              break; // 한번 동기화하면 전체 복사됨
            }
          }
        }
      }
    } catch (e) {
      results.add('듀얼 문서 감사 실패: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  3. 오래된 데이터 정리
  // ═══════════════════════════════════════════

  Future<void> _auditStaleData(List<String> results) async {
    try {
      final fb = FirebaseService();
      final data = await fb.getStudyData();
      if (data == null) return;

      final cutoff = DateTime.now().subtract(const Duration(days: 14));
      final updates = <String, dynamic>{};

      // timeRecords 14일 이상 → 삭제 (archive에서 읽어야 함)
      final tr = data['timeRecords'];
      if (tr is Map) {
        for (final key in tr.keys) {
          try {
            final d = DateTime.parse(key.toString());
            if (d.isBefore(cutoff)) {
              updates['timeRecords.$key'] = FieldValue.delete();
              results.add('CLEAN: timeRecords.$key (14일+)');
            }
          } catch (_) {}
        }
      }

      // studyTimeRecords 14일 이상
      final str = data['studyTimeRecords'];
      if (str is Map) {
        for (final key in str.keys) {
          try {
            final d = DateTime.parse(key.toString());
            if (d.isBefore(cutoff)) {
              updates['studyTimeRecords.$key'] = FieldValue.delete();
              results.add('CLEAN: studyTimeRecords.$key (14일+)');
            }
          } catch (_) {}
        }
      }

      if (updates.isNotEmpty) {
        // 먼저 archive 확인
        await FirebaseFirestore.instance
            .doc('users/${fb.uid}/data/study')
            .update(updates)
            .timeout(const Duration(seconds: 10));
        fb.invalidateStudyCache();
        results.add('CLEANED: ${updates.length}건 오래된 데이터 삭제');
      }
    } catch (e) {
      results.add('오래된 데이터 정리 실패: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  4. OrderData 무결성
  // ═══════════════════════════════════════════

  Future<void> _auditOrderData(List<String> results) async {
    try {
      final fb = FirebaseService();
      final data = await fb.getStudyData();
      if (data == null || data['orderData'] == null) return;

      final raw = data['orderData'];
      if (raw is! Map) {
        results.add('CRITICAL: orderData가 Map이 아님 (${raw.runtimeType})');
        return;
      }

      // 습관 중복 ID 체크
      final habits = raw['habits'];
      if (habits is List) {
        final ids = <String>{};
        int dupes = 0;
        for (final h in habits) {
          if (h is Map) {
            final id = h['id']?.toString() ?? '';
            if (ids.contains(id)) {
              dupes++;
            }
            ids.add(id);
          }
        }
        if (dupes > 0) {
          results.add('WARN: 습관 중복 ID ${dupes}건');
        }
      }

      // 목표 중복 ID 체크
      final goals = raw['goals'];
      if (goals is List) {
        final ids = <String>{};
        int dupes = 0;
        for (final g in goals) {
          if (g is Map) {
            final id = g['id']?.toString() ?? '';
            if (ids.contains(id)) {
              dupes++;
            }
            ids.add(id);
          }
        }
        if (dupes > 0) {
          results.add('WARN: 목표 중복 ID ${dupes}건');
        }
      }
    } catch (e) {
      results.add('orderData 감사 실패: $e');
    }
  }
}
