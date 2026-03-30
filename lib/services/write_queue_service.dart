import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

/// ═══════════════════════════════════════════════════════════
/// FirestoreWriteQueue — 중앙 쓰기 큐
///
/// - 문서별 직렬화 (같은 문서 동시 쓰기 불가, 다른 문서 병렬)
/// - Pattern A 내장: update() 실패 → set(merge:true) 폴백
/// - 3회 재시도 + 지수 백오프 (1s → 2s → 4s)
/// - Hive 저널링 — 앱 죽어도 재시작 시 복구
/// ═══════════════════════════════════════════════════════════
class FirestoreWriteQueue {
  static final FirestoreWriteQueue _instance = FirestoreWriteQueue._();
  factory FirestoreWriteQueue() => _instance;
  FirestoreWriteQueue._();

  Box? _journalBox;
  Box? _errorBox;
  final _db = FirebaseFirestore.instance;

  // ── Stats ──
  int pending = 0;
  int succeeded = 0;
  int failed = 0;

  // ── Per-doc serialization ──
  final Map<String, List<_WriteTask>> _queues = {};
  final Set<String> _processing = {};

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _journalBox = await Hive.openBox('write_journal');
    _errorBox = await Hive.openBox('write_errors');
    _initialized = true;
    await _rehydrateFromJournal();
    debugPrint('[WriteQueue] init OK '
        '(journal: ${_journalBox!.length}, errors: ${_errorBox!.length})');
  }

  // ═══════════════════════════════════════════════════════════
  //  Public API
  // ═══════════════════════════════════════════════════════════

  /// 단일 문서 쓰기 (fire-and-forget)
  /// [fields]에 lastModified/lastDevice 자동 추가
  void enqueue(String docPath, Map<String, dynamic> fields) {
    final data = <String, dynamic>{
      ...fields,
      'lastModified': DateTime.now().millisecondsSinceEpoch,
      'lastDevice': 'android',
    };
    _addToQueue(_WriteTask(docPath: docPath, fields: data));
  }

  /// 듀얼 문서 쓰기 (study + today)
  void enqueueDualWrite(
    String docPath1, Map<String, dynamic> fields1,
    String docPath2, Map<String, dynamic> fields2,
  ) {
    enqueue(docPath1, fields1);
    enqueue(docPath2, fields2);
  }

  // ═══════════════════════════════════════════════════════════
  //  Queue internals
  // ═══════════════════════════════════════════════════════════

  void _addToQueue(_WriteTask task) {
    pending++;
    if (_initialized) {
      _journalBox?.put(task.id, task.toMap());
    }
    _queues.putIfAbsent(task.docPath, () => []).add(task);
    _processQueue(task.docPath);
  }

  Future<void> _processQueue(String docPath) async {
    if (_processing.contains(docPath)) return;
    _processing.add(docPath);

    try {
      while (_queues[docPath]?.isNotEmpty == true) {
        final task = _queues[docPath]!.removeAt(0);
        await _executeWithRetry(task);
      }
    } finally {
      _processing.remove(docPath);
      _queues.remove(docPath);
    }
  }

  Future<void> _executeWithRetry(_WriteTask task) async {
    const maxRetries = 3;
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await _executeWrite(task);
        pending--;
        succeeded++;
        if (_initialized) _journalBox?.delete(task.id);
        return;
      } catch (e) {
        debugPrint('[WriteQueue] attempt ${attempt + 1}/$maxRetries '
            'failed (${task.docPath.split('/').last}): $e');
        if (attempt < maxRetries - 1) {
          await Future.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }

    // All retries exhausted → journal + error log
    pending--;
    failed++;
    if (_initialized) {
      _journalBox?.delete(task.id);
      _errorBox?.put(DateTime.now().millisecondsSinceEpoch.toString(), {
        'docPath': task.docPath,
        'fields': task.fields.keys
            .where((k) => k != 'lastModified' && k != 'lastDevice')
            .toList(),
        'time': DateTime.now().toIso8601String(),
      });
    }
    debugPrint('[WriteQueue] FAILED after $maxRetries retries: ${task.docPath}');
  }

  /// Pattern A: update() → set(merge:true) 폴백
  Future<void> _executeWrite(_WriteTask task) async {
    // ★ __FIELD_DELETE__ 센티넬 → FieldValue.delete() 복원 (Hive 저널 복구 포함)
    final processed = _restoreSentinels(task.fields);

    try {
      await _db.doc(task.docPath)
          .update(processed)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      // update 실패 → set(merge:true) 폴백
      // FieldValue.delete()는 set에서 제외
      final setFields = Map.fromEntries(
          processed.entries.where((e) => e.value is! FieldValue));
      await _db.doc(task.docPath)
          .set(setFields, SetOptions(merge: true))
          .timeout(const Duration(seconds: 8));
    }
  }

  /// 센티넬 문자열 → FieldValue.delete() 재변환 (재귀, 중첩 맵 지원)
  static Map<String, dynamic> _restoreSentinels(Map<String, dynamic> fields) {
    final result = <String, dynamic>{};
    for (final entry in fields.entries) {
      result[entry.key] = _restoreValue(entry.value);
    }
    return result;
  }

  static dynamic _restoreValue(dynamic value) {
    if (value == '__FIELD_DELETE__' || value == '__DELETE__') {
      return FieldValue.delete();
    }
    if (value is Map) {
      return value.map((k, v) => MapEntry(k, _restoreValue(v)));
    }
    if (value is List) {
      return value.map(_restoreValue).toList();
    }
    return value;
  }

  // ═══════════════════════════════════════════════════════════
  //  Journal recovery
  // ═══════════════════════════════════════════════════════════

  Future<void> _rehydrateFromJournal() async {
    if (_journalBox == null || _journalBox!.isEmpty) return;
    final count = _journalBox!.length;
    debugPrint('[WriteQueue] rehydrating $count entries from journal');

    final keys = _journalBox!.keys.toList();
    for (final key in keys) {
      try {
        final raw = _journalBox!.get(key);
        if (raw is! Map) {
          _journalBox!.delete(key);
          continue;
        }
        final map = <String, dynamic>{};
        for (final e in (raw).entries) {
          map[e.key.toString()] = e.value;
        }
        final task = _WriteTask.fromMap(map);
        pending++;
        _queues.putIfAbsent(task.docPath, () => []).add(task);
      } catch (e) {
        debugPrint('[WriteQueue] rehydrate skip: $e');
        _journalBox!.delete(key);
      }
    }

    for (final docPath in _queues.keys.toList()) {
      _processQueue(docPath);
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Diagnostics (설정 화면용)
  // ═══════════════════════════════════════════════════════════

  Map<String, int> get stats => {
    'pending': pending,
    'succeeded': succeeded,
    'failed': failed,
  };

  List<Map<String, dynamic>> getRecentErrors({int limit = 20}) {
    if (!_initialized || _errorBox == null) return [];
    return _errorBox!.keys
        .toList()
        .reversed
        .take(limit)
        .map((key) {
          final raw = _errorBox!.get(key);
          if (raw is Map) return Map<String, dynamic>.from(raw);
          return <String, dynamic>{'error': 'invalid'};
        })
        .toList();
  }

  void clearErrors() {
    if (_initialized) _errorBox?.clear();
    failed = 0;
  }
}

// ═══════════════════════════════════════════════════════════
//  WriteTask — 큐 항목
// ═══════════════════════════════════════════════════════════

class _WriteTask {
  final String id;
  final String docPath;
  final Map<String, dynamic> fields;

  _WriteTask({required this.docPath, required this.fields})
      : id = '${docPath.hashCode}_${DateTime.now().microsecondsSinceEpoch}';

  _WriteTask._({required this.id, required this.docPath, required this.fields});

  Map<String, dynamic> toMap() => {
    'id': id,
    'docPath': docPath,
    'fields': _sanitizeForHive(fields),
  };

  factory _WriteTask.fromMap(Map<String, dynamic> map) {
    final rawFields = map['fields'];
    final fields = rawFields is Map
        ? Map<String, dynamic>.from(rawFields)
        : <String, dynamic>{};
    return _WriteTask._(
      id: map['id']?.toString() ??
          'recovered_${DateTime.now().microsecondsSinceEpoch}',
      docPath: map['docPath']?.toString() ?? '',
      fields: fields,
    );
  }

  /// Hive 저장용: FieldValue/Timestamp/DateTime → 직렬화 가능 값으로 변환
  /// ★ FieldValue.delete() → '__FIELD_DELETE__' 센티넬로 보존 (rehydrate 시 복원)
  static dynamic _sanitizeForHive(dynamic value) {
    if (value is FieldValue) {
      // FieldValue.delete()의 toString은 "FieldValue(delete)"
      if (value.toString().contains('delete')) return '__FIELD_DELETE__';
      return null; // arrayUnion 등 기타 FieldValue는 저널에서 복구 불가
    }
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitizeForHive(v)));
    }
    if (value is List) return value.map(_sanitizeForHive).toList();
    return value;
  }
}
