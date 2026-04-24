import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../utils/map_utils.dart'; // ★ AUDIT FIX: P-03

/// ═══════════════════════════════════════════════════════════
/// 로컬 퍼스트 캐시 — Hive 기반
/// 앱 시작 시 즉시 읽기 (0ms), Firebase는 백그라운드 갱신
/// ★ AUDIT FIX: P-04 — TODO: 장기적으로 Hive를 제거하고 ObjectBox + SharedPreferences로 통합
/// ═══════════════════════════════════════════════════════════
class LocalCacheService {
  static final LocalCacheService _instance = LocalCacheService._();
  factory LocalCacheService() => _instance;
  LocalCacheService._();

  Box? _box;
  static const _boxName = 'chstudio_cache';

  Future<void> init() async {
    _box = await Hive.openBox(_boxName);
    debugPrint('[LocalCache] Hive init OK (${_box!.length} keys)');
    await _migrateFromSharedPrefs();
  }

  /// SharedPreferences → Hive 1회 마이그레이션
  Future<void> _migrateFromSharedPrefs() async {
    if (_box?.get('_migrated_from_sp') == true) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final keys = sp.getKeys().where((k) => k.startsWith('cache_')).toList();
      if (keys.isEmpty) {
        await _box?.put('_migrated_from_sp', true);
        return;
      }
      int count = 0;
      for (final key in keys) {
        final raw = sp.getString(key);
        if (raw == null) continue;
        try {
          final decoded = jsonDecode(raw);
          await _box?.put(key, decoded);
          count++;
        } catch (_) {
          await _box?.put(key, raw);
          count++;
        }
      }
      // 마이그레이션 완료 후 SP 캐시 삭제
      for (final key in keys) {
        await sp.remove(key);
      }
      await _box?.put('_migrated_from_sp', true);
      debugPrint('[LocalCache] SP→Hive 마이그레이션 완료: $count keys');
    } catch (e) {
      debugPrint('[LocalCache] SP 마이그레이션 실패 (무시): $e');
      await _box?.put('_migrated_from_sp', true);
    }
  }

  // === Hive 비호환 타입 변환 (Timestamp 등) ===
  dynamic _sanitize(dynamic value) {
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is Map) {
      return Map<String, dynamic>.fromEntries(
        value.entries.map((e) => MapEntry(e.key.toString(), _sanitize(e.value))),
      );
    }
    if (value is List) return value.map(_sanitize).toList();
    return value;
  }

  // === 저장 ===
  Future<void> saveStudyData(Map<String, dynamic> data) async {
    try {
      await _box?.put('cache_study', _sanitize(data));
      await _box?.put('cache_study_time', DateTime.now().toIso8601String());
      debugPrint('[LocalCache] study 저장 OK');
    } catch (e) {
      debugPrint('[LocalCache] study 저장 실패: $e');
    }
  }

  Future<void> saveGeneric(String key, Map<String, dynamic> data) async {
    try {
      await _box?.put('cache_$key', _sanitize(data));
    } catch (e) {
      debugPrint('[LocalCache] $key 저장 실패: $e');
    }
  }

  Future<void> removeGeneric(String key) async {
    await _box?.delete('cache_$key');
  }

  /// study 캐시 삭제
  void clearStudyCache() {
    _box?.delete('cache_study');
  }

  /// generic 캐시 삭제
  void clearGeneric(String key) {
    _box?.delete('cache_$key');
  }

  // === 읽기 ===
  Map<String, dynamic>? getStudyData() => _getMap('cache_study');
  Map<String, dynamic>? getGeneric(String key) => _getMap('cache_$key');

  Map<String, dynamic>? _getMap(String key) {
    try {
      final raw = _box?.get(key);
      if (raw == null) return null;
      if (raw is Map) return _deepCast(raw);
      if (raw is String) return _deepCast(jsonDecode(raw) as Map);
      return null;
    } catch (e) {
      debugPrint('[LocalCache] $key 읽기 실패: $e');
      return null;
    }
  }

  /// Hive 반환값의 nested Map/List를 재귀적으로 Map<String, dynamic>로 변환
  Map<String, dynamic> _deepCast(Map m) {
    return m.map((k, v) => MapEntry(k.toString(), _deepCastValue(v)));
  }

  dynamic _deepCastValue(dynamic v) {
    if (v is Map) return _deepCast(v);
    if (v is List) return v.map(_deepCastValue).toList();
    return v;
  }

  // ★ AUDIT FIX: P-03, B-01 — MapUtils.setNestedValue로 통합, FieldValue.increment 파싱 제거
  Future<void> updateStudyField(String field, dynamic value) async {
    final data = getStudyData() ?? {};
    MapUtils.setNestedValue(data, field, value);
    await saveStudyData(data);
  }

  // === 캐시 나이 확인 ===
  Duration? getStudyCacheAge() {
    final timeStr = _box?.get('cache_study_time');
    if (timeStr == null || timeStr is! String) return null;
    try {
      return DateTime.now().difference(DateTime.parse(timeStr));
    } catch (_) {
      return null;
    }
  }

  bool get hasValidStudyCache {
    final age = getStudyCacheAge();
    return age != null && age.inMinutes < 30;
  }

  // === Write protection: block stream/background refresh after write ===
  int _lastWriteTime = 0;

  void markWrite() {
    _lastWriteTime = DateTime.now().millisecondsSinceEpoch;
    debugPrint('[LocalCache] markWrite at $_lastWriteTime');
  }

  bool isWriteProtected() {
    // Phase D: reduced from 10s to 5s (single source of truth = fewer races)
    return DateTime.now().millisecondsSinceEpoch - _lastWriteTime < 5000;
  }

  // === Order / Todos 전용 캐시 ===
  Future<void> saveOrderData(Map<String, dynamic> data) => saveGeneric('order', data);
  Map<String, dynamic>? getOrderData() => getGeneric('order');

  Future<void> saveTodosData(Map<String, dynamic> data) => saveGeneric('todos', data);
  Map<String, dynamic>? getTodosData() => getGeneric('todos');

  // === 행동 타임라인 인메모리 캐시 (per-date, 앱 재시작 시 초기화) ===
  final Map<String, List<Map<String, dynamic>>> _timelineCache = {};

  void saveTimeline(String date, List<Map<String, dynamic>> entries) {
    _timelineCache[date] = List.from(entries);
    debugPrint('[LocalCache] timeline 저장: $date (${entries.length}개)');
  }

  List<Map<String, dynamic>>? getTimeline(String date) => _timelineCache[date];

  void appendTimelineEntry(String date, Map<String, dynamic> entry) {
    _timelineCache.putIfAbsent(date, () => []).add(entry);
  }
}
