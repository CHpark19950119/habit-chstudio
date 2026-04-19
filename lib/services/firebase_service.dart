import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../utils/date_utils.dart';
import '../utils/map_utils.dart'; // ★ AUDIT FIX: P-03 — 통합 유틸
import 'local_cache_service.dart';
import 'write_queue_service.dart';
import '../app_init.dart';

part 'firebase_history_part.dart';
part 'firebase_data_part.dart';

// ═══════════════════════════════════════════════════════════
//  Library-private constants
// ═══════════════════════════════════════════════════════════

// Document paths
const String _studyDoc = kStudyDoc;
const String _todayDocPath = kTodayDoc;
const String _locationHistoryCol = 'users/$kUid/locationHistory';
const String _behaviorTimelineCol = 'users/$kUid/behaviorTimeline';
const String _memosCol = 'users/$kUid/memos';
const String _diaryCol = 'users/$kUid/dailyDiary';

// Field names in study doc
const String _timeRecordsField = 'timeRecords';
const String _restDaysField = 'restDays';
const _cacheTtl = Duration(minutes: 2);
const _archiveFields = ['timeRecords', 'todos'];
const _cfBaseUrl = 'https://us-central1-cheonhong-studio.cloudfunctions.net/checkDoorManual';
const _cfTimeout = Duration(seconds: 5);

// ═══════════════════════════════════════════════════════════
//  FirebaseService — Core (singleton + cache + study doc)
// ═══════════════════════════════════════════════════════════

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  FirebaseFirestore get _db => firestore;

  String get uid => kUid;

  // ═══ CF HTTP read (Firestore SDK bypass) ═══
  // gRPC 연결 불안정 → CF HTTP 엔드포인트로 서버 읽기 대체
  // 지원 doc: today, study, iot (CF allowed 목록)
  static const _cfDocNames = {'today', 'study', 'iot'};

  /// CF HTTP로 Firestore doc 읽기. [doc]은 'today'|'study'|'iot'.
  /// 성공 시 Map 반환, 실패 시 null.
  Future<Map<String, dynamic>?> _cfRead(String doc, [String? field]) async {
    try {
      final uri = Uri.parse(_cfBaseUrl).replace(queryParameters: {
        'q': 'read',
        'doc': doc,
        if (field != null) 'field': field,
      });
      final resp = await http.get(uri).timeout(_cfTimeout);
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body);
        if (body is Map<String, dynamic>) {
          debugPrint('[CF] read $doc OK (${resp.body.length} bytes)');
          return body;
        }
      }
      debugPrint('[CF] read $doc: HTTP ${resp.statusCode}');
    } catch (e) {
      debugPrint('[CF] read $doc fail: $e');
    }
    return null;
  }

  /// docPath → CF doc name 매핑. 매핑 불가 시 null.
  String? _docPathToCfName(String docPath) {
    // 'users/xxx/data/today' → 'today'
    final parts = docPath.split('/');
    if (parts.length >= 4 && parts[2] == 'data') {
      final name = parts[3];
      return _cfDocNames.contains(name) ? name : null;
    }
    // 'users/xxx/history/2026-04' → 'history/2026-04'
    if (parts.length >= 4 && parts[2] == 'history') {
      return 'history/${parts[3]}';
    }
    return null;
  }

  // ═══ Study doc cache ═══
  Map<String, dynamic>? _studyCache;
  DateTime? _studyCacheTime;
  bool _refreshingStudy = false;

  /// 캐시 무효화 (외부 서비스용) — 인메모리 + 로컬 캐시 전부 삭제
  void invalidateStudyCache() {
    _studyCache = null;
    _studyCacheTime = null;
    LocalCacheService().clearStudyCache();
  }

  /// today doc 캐시 무효화
  void invalidateTodayCache() {
    _todayCache = null;
    _todayCacheTime = null;
    LocalCacheService().clearGeneric('today');
  }

  /// 전체 캐시 무효화 (강제 서버 리프레시)
  void invalidateAllCaches() {
    invalidateStudyCache();
    invalidateTodayCache();
  }

  // ═══ Today doc cache ═══
  Map<String, dynamic>? _todayCache;
  DateTime? _todayCacheTime;

  // ═══════════════════════════════════════════════════════════
  //  getStudyData — local-first hybrid + in-flight dedup
  //  1) in-memory → 2) SharedPrefs → 3) Firestore cache → 4) server
  //  ★ Completer dedup: 동시 호출 시 하나만 Firestore 읽기 실행
  // ═══════════════════════════════════════════════════════════
  Completer<Map<String, dynamic>?>? _studyLoadCompleter;

  Future<Map<String, dynamic>?> getStudyData({bool forceServer = false}) async {
    // forceServer: 캐시 무시하고 서버에서 직접 읽기 (캘린더 새로고침 등)
    if (forceServer) {
      invalidateStudyCache();
      final localCache = LocalCacheService();
      try {
        final result = await _getStudyDataFromFirestore(localCache);
        return result;
      } catch (_) {
        return null;
      }
    }

    // 1) in-memory (5min TTL)
    if (_studyCache != null && _studyCacheTime != null &&
        DateTime.now().difference(_studyCacheTime!) < _cacheTtl) {
      return _studyCache;
    }

    // 2) SharedPrefs local cache
    final localCache = LocalCacheService();
    final localData = localCache.getStudyData();
    if (localData != null) {
      _studyCache = localData;
      _studyCacheTime = DateTime.now();
      debugPrint('[FB] study: SharedPrefs hit (${localData.length} fields)');
      _refreshStudyInBackground();
      return localData;
    }

    // ★ in-flight dedup: 이미 Firestore 읽기 진행 중이면 같은 Future 재사용
    if (_studyLoadCompleter != null) {
      debugPrint('[FB] study: in-flight dedup — waiting');
      return _studyLoadCompleter!.future;
    }
    _studyLoadCompleter = Completer<Map<String, dynamic>?>();

    try {
      final result = await _getStudyDataFromFirestore(localCache);
      _studyLoadCompleter!.complete(result);
      return result;
    } catch (e) {
      _studyLoadCompleter!.complete(null);
      return null;
    } finally {
      _studyLoadCompleter = null;
    }
  }

  Future<Map<String, dynamic>?> _getStudyDataFromFirestore(LocalCacheService localCache) async {
    // 3) stale in-memory (persistence 비활성화로 Firestore cache 단계 제거)
    if (_studyCache != null) {
      debugPrint('[FB] study: stale cache (${_studyCache!.length} fields)');
      _refreshStudyInBackground();
      return _studyCache;
    }

    // 5) server fallback — CF HTTP (gRPC bypass)
    try {
      final data = await _cfRead('study');
      if (data != null && data.isNotEmpty) {
        _studyCache = data; _studyCacheTime = DateTime.now();
        await localCache.saveStudyData(data);
        debugPrint('[FB] study: CF HTTP OK (${data.length} fields)');
        AppInit.resetFirestoreTimeout();
        return data;
      }
    } catch (e) {
      debugPrint('[FB] study CF fail: $e');
    }
    // SDK fallback (CF 장애 시)
    try {
      final doc = await _db.doc(_studyDoc).get()
          .timeout(const Duration(seconds: 10));
      final data = doc.data();
      if (data != null) {
        _studyCache = data; _studyCacheTime = DateTime.now();
        await localCache.saveStudyData(data);
        debugPrint('[FB] study: SDK fallback OK (${data.length} fields)');
        AppInit.resetFirestoreTimeout();
      }
      return data;
    } catch (e) {
      debugPrint('[FB] study SDK fallback fail: $e');
      AppInit.recordFirestoreTimeout();
      return null;
    }
  }

  void _refreshStudyInBackground() {
    if (_refreshingStudy) return;
    _refreshingStudy = true;
    Future(() async {
      try {
        if (LocalCacheService().isWriteProtected()) {
          debugPrint('[FB] bg refresh skip: write-protected');
          _refreshingStudy = false;
          return;
        }
        final data = await _cfRead('study');
        if (data != null && data.isNotEmpty) {
          if (LocalCacheService().isWriteProtected()) {
            debugPrint('[FB] bg refresh skip after fetch: write-protected');
            return;
          }
          _studyCache = data;
          _studyCacheTime = DateTime.now();
          await LocalCacheService().saveStudyData(data);
          debugPrint('[FB] background refresh OK via CF (${data.length} fields)');
        }
      } catch (e) {
        debugPrint('[FB] background refresh fail: $e');
      } finally {
        _refreshingStudy = false;
      }
    });
  }

  // ═══ Used delegates ═══
  Future<Map<String, dynamic>?> getTodosData() => getStudyData();
  Future<Map<String, dynamic>?> getPlanData() => getStudyData();

  // ═══ Stream cache sync ═══

  void updateCacheFromStream(Map<String, dynamic> data) {
    _studyCache = data;
    _studyCacheTime = DateTime.now();
    LocalCacheService().saveStudyData(data);
  }

  void updateTodosCache(String date, Map<String, dynamic> todoMap) {
    LocalCacheService().markWrite();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent('todos', () => {}) as Map)[date] = todoMap;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('todos.$date', todoMap);
  }

  // ═══ Generic cached doc helper ═══

  // ★ in-flight dedup: doc path → Completer
  final Map<String, Completer<Map<String, dynamic>?>> _docLoadCompleters = {};
  final Set<String> _bgRefreshInFlight = {};

  Future<Map<String, dynamic>?> _cachedDocGet(String cacheKey, String docPath) async {
    // 1) local cache
    final cached = LocalCacheService().getGeneric(cacheKey);
    if (cached != null) {
      _bgRefreshDoc(cacheKey, docPath);
      return cached;
    }

    // ★ in-flight dedup
    if (_docLoadCompleters.containsKey(docPath)) {
      debugPrint('[FB] $cacheKey: in-flight dedup');
      return _docLoadCompleters[docPath]!.future;
    }
    final completer = Completer<Map<String, dynamic>?>();
    _docLoadCompleters[docPath] = completer;

    try {
      final result = await _cachedDocGetInner(cacheKey, docPath);
      completer.complete(result);
      return result;
    } catch (e) {
      completer.complete(null);
      return null;
    } finally {
      _docLoadCompleters.remove(docPath);
    }
  }

  Future<Map<String, dynamic>?> _cachedDocGetInner(String cacheKey, String docPath) async {
    // CF HTTP first (지원 doc만)
    final cfName = _docPathToCfName(docPath);
    if (cfName != null) {
      final data = await _cfRead(cfName);
      if (data != null && data.isNotEmpty) {
        LocalCacheService().saveGeneric(cacheKey, data);
        return data;
      }
    }
    // SDK fallback (CF 미지원 doc 또는 CF 실패)
    try {
      final doc = await _db.doc(docPath).get().timeout(const Duration(seconds: 10));
      if (doc.exists && doc.data() != null) {
        LocalCacheService().saveGeneric(cacheKey, doc.data()!);
        return doc.data();
      }
    } catch (_) {}
    return null;
  }

  void _bgRefreshDoc(String cacheKey, String docPath) {
    // ★ 동일 doc 백그라운드 리프레시 중복 방지
    if (_bgRefreshInFlight.contains(docPath)) return;
    _bgRefreshInFlight.add(docPath);
    Future(() async {
      try {
        if (LocalCacheService().isWriteProtected()) return;
        // CF HTTP first (지원 doc만)
        final cfName = _docPathToCfName(docPath);
        Map<String, dynamic>? data;
        if (cfName != null) {
          data = await _cfRead(cfName);
        }
        // SDK fallback
        if (data == null || data.isEmpty) {
          final doc = await _db.doc(docPath).get().timeout(const Duration(seconds: 10));
          if (doc.exists && doc.data() != null) data = doc.data();
        }
        if (data != null && data.isNotEmpty) {
          if (LocalCacheService().isWriteProtected()) return;
          LocalCacheService().saveGeneric(cacheKey, data);
        }
      } catch (_) {}
      _bgRefreshInFlight.remove(docPath);
    });
  }

  // ═══ Study doc stream ═══

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchStudyData() {
    return _db.doc(_studyDoc).snapshots().map((snap) {
      if (snap.exists && snap.data() != null) {
        if (LocalCacheService().isWriteProtected()) {
          debugPrint('[Stream] write-protected, skip cache update (snap still passed)');
          return snap;
        }
        _studyCache = snap.data();
        _studyCacheTime = DateTime.now();
        LocalCacheService().saveStudyData(snap.data()!);
      }
      return snap;
    });
  }

  // ═══ Today doc stream ═══

  Stream<DocumentSnapshot<Map<String, dynamic>>> watchTodayData() {
    return _db.doc(_todayDocPath).snapshots().map((snap) {
      if (snap.exists && snap.data() != null) {
        if (LocalCacheService().isWriteProtected()) {
          debugPrint('[Stream:today] write-protected, skip cache update');
          return snap;
        }
        _todayCache = snap.data();
        _todayCacheTime = DateTime.now();
        LocalCacheService().saveGeneric('today', snap.data()!);
      }
      return snap;
    });
  }

  // ═══ Field update (today doc = single source of truth) ═══

  Future<void> updateField(String field, dynamic value) async {
    LocalCacheService().markWrite();
    // Phase D: today doc is the single source of truth
    _todayCache ??= {};
    MapUtils.setNestedValue(_todayCache!, field, value);
    _todayCacheTime = DateTime.now();
    LocalCacheService().saveGeneric('today', _todayCache!);
    FirestoreWriteQueue().enqueue(_todayDocPath, {field: value});
  }

  // ═══ TimeRecords (daily-life: wake/outing/meal/sleep) ═══

  Future<Map<String, TimeRecord>> getTimeRecords() async {
    final data = await getStudyData();
    if (data == null || data[_timeRecordsField] == null) return {};
    final raw = data[_timeRecordsField] as Map<String, dynamic>;
    final result = <String, TimeRecord>{};
    for (final entry in raw.entries) {
      if (entry.value is Map) {
        result[entry.key] = TimeRecord.fromMap(
            entry.key, Map<String, dynamic>.from(entry.value as Map));
      }
    }
    return result;
  }

  Future<void> updateTimeRecord(String date, TimeRecord record) async {
    LocalCacheService().markWrite();
    final map = record.toMap();
    _studyCache ??= {};
    (_studyCache!.putIfAbsent(_timeRecordsField, () => <String, dynamic>{})
        as Map)[date] = map;
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField('$_timeRecordsField.$date', map);
    FirestoreWriteQueue().enqueue(_studyDoc, {'$_timeRecordsField.$date': map});
    // Dual-write to today doc
    final todayKey = StudyDateUtils.todayKey();
    if (date == todayKey) {
      _todayCache ??= {};
      (_todayCache!.putIfAbsent('timeRecords', () => <String, dynamic>{})
          as Map).addAll(map);
      _todayCacheTime = DateTime.now();
      LocalCacheService().saveGeneric('today', _todayCache!);
      FirestoreWriteQueue().enqueue(_todayDocPath, {'timeRecords': map});
    }
  }

}
