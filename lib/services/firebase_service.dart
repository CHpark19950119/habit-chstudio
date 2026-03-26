import 'package:cloud_firestore/cloud_firestore.dart';
import '../constants.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/models.dart';
import '../utils/study_date_utils.dart';
import 'local_cache_service.dart';
import 'write_queue_service.dart';

part 'firebase_study_part.dart';
part 'firebase_history_part.dart';
part 'firebase_data_part.dart';

// ═══════════════════════════════════════════════════════════
//  Library-private constants
// ═══════════════════════════════════════════════════════════

// Document paths
const String _studyDoc = kStudyDoc;
const String _liveFocusDoc = kLiveFocusDoc;
const String _todayDoc2 = kTodayDoc;
const String _locationHistoryCol = 'users/$kUid/locationHistory';
const String _behaviorTimelineCol = 'users/$kUid/behaviorTimeline';
const String _nfcTagsDoc = 'users/$kUid/settings/nfcTags';
const String _nfcEventsCol = 'users/$kUid/nfcEvents';
const String _memosCol = 'users/$kUid/memos';
const String _diaryCol = 'users/$kUid/dailyDiary';

// Field names in study doc
const String _timeRecordsField = 'timeRecords';
const String _studyTimeRecordsField = 'studyTimeRecords';
const String _focusCyclesField = 'focusCycles';
const String _progressGoalsField = 'progressGoals';
const String _restDaysField = 'restDays';
const String _customTasksField = 'customStudyTasks';
const _cacheTtl = Duration(minutes: 5);
const _archiveFields = ['timeRecords', 'studyTimeRecords', 'focusCycles', 'todos'];

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
    _todayCache2 = null;
    _todayCacheTime2 = null;
    LocalCacheService().clearGeneric('today');
  }

  /// 전체 캐시 무효화 (강제 서버 리프레시)
  void invalidateAllCaches() {
    invalidateStudyCache();
    invalidateTodayCache();
  }

  // ═══ Today doc cache ═══
  Map<String, dynamic>? _todayCache2;
  DateTime? _todayCacheTime2;

  // ═══════════════════════════════════════════════════════════
  //  getStudyData — local-first hybrid
  //  1) in-memory → 2) SharedPrefs → 3) Firestore cache → 4) server
  // ═══════════════════════════════════════════════════════════

  Future<Map<String, dynamic>?> getStudyData() async {
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

    // 3) Firestore local cache
    try {
      final localDoc = await _db.doc(_studyDoc)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (localDoc.exists && localDoc.data() != null) {
        final data = localDoc.data()!;
        _studyCache = data; _studyCacheTime = DateTime.now();
        debugPrint('[FB] study: Firestore cache hit (${data.length} fields)');
        localCache.saveStudyData(data);
        _refreshStudyInBackground();
        return data;
      }
    } catch (e) {
      debugPrint('[FB] study Firestore cache miss: $e');
    }

    // 4) stale in-memory
    if (_studyCache != null) {
      debugPrint('[FB] study: stale cache (${_studyCache!.length} fields)');
      _refreshStudyInBackground();
      return _studyCache;
    }

    // 5) server fallback
    try {
      final doc = await _db.doc(_studyDoc).get()
          .timeout(const Duration(seconds: 15));
      final data = doc.data();
      if (data != null) {
        _studyCache = data; _studyCacheTime = DateTime.now();
        await localCache.saveStudyData(data);
        debugPrint('[FB] study: server OK (${data.length} fields)');
      }
      return data;
    } catch (e) {
      debugPrint('[FB] study server fail: $e');
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
        final doc = await _db.doc(_studyDoc).get()
            .timeout(const Duration(seconds: 15));
        if (doc.exists && doc.data() != null) {
          if (LocalCacheService().isWriteProtected()) {
            debugPrint('[FB] bg refresh skip after fetch: write-protected');
            return;
          }
          final data = doc.data()!;
          _studyCache = data;
          _studyCacheTime = DateTime.now();
          await LocalCacheService().saveStudyData(data);
          debugPrint('[FB] background refresh OK (${data.length} fields)');
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

  Future<Map<String, dynamic>?> _cachedDocGet(String cacheKey, String docPath) async {
    // 1) local cache
    final cached = LocalCacheService().getGeneric(cacheKey);
    if (cached != null) {
      _bgRefreshDoc(cacheKey, docPath);
      return cached;
    }
    // 2) Firestore cache (3s)
    try {
      final doc = await _db.doc(docPath)
          .get(const GetOptions(source: Source.cache))
          .timeout(const Duration(seconds: 3));
      if (doc.exists && doc.data() != null) {
        LocalCacheService().saveGeneric(cacheKey, doc.data()!);
        _bgRefreshDoc(cacheKey, docPath);
        return doc.data();
      }
    } catch (_) {}
    // 3) server (10s)
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
    Future(() async {
      try {
        if (LocalCacheService().isWriteProtected()) return;
        final doc = await _db.doc(docPath).get().timeout(const Duration(seconds: 10));
        if (doc.exists && doc.data() != null) {
          if (LocalCacheService().isWriteProtected()) return;
          LocalCacheService().saveGeneric(cacheKey, doc.data()!);
        }
      } catch (_) {}
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
    return _db.doc(_todayDoc2).snapshots().map((snap) {
      if (snap.exists && snap.data() != null) {
        if (LocalCacheService().isWriteProtected()) {
          debugPrint('[Stream:today] write-protected, skip cache update');
          return snap;
        }
        _todayCache2 = snap.data();
        _todayCacheTime2 = DateTime.now();
        LocalCacheService().saveGeneric('today', snap.data()!);
      }
      return snap;
    });
  }

  // ═══ Field update (study doc) ═══

  Future<void> updateField(String field, dynamic value) async {
    LocalCacheService().markWrite();
    _studyCache ??= {};
    final parts = field.split('.');
    if (parts.length == 1) {
      _studyCache![field] = value;
    } else {
      Map<String, dynamic> current = _studyCache!;
      for (int i = 0; i < parts.length - 1; i++) {
        if (current[parts[i]] == null || current[parts[i]] is! Map) {
          current[parts[i]] = <String, dynamic>{};
        }
        current = current[parts[i]] as Map<String, dynamic>;
      }
      current[parts.last] = value;
    }
    _studyCacheTime = DateTime.now();
    LocalCacheService().updateStudyField(field, value);
    FirestoreWriteQueue().enqueue(_studyDoc, {field: value});
    if (field.startsWith('orderData')) {
      updateTodayField(field, value);
    }
  }
}
