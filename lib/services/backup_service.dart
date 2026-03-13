import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/study_date_utils.dart';
import 'firebase_service.dart';
import 'telegram_service.dart';

// ═══════════════════════════════════════════════════════════
//  BackupService — Firestore 자동/수동 로컬 백업
// ═══════════════════════════════════════════════════════════

/// 로컬 백업 메타데이터
class BackupInfo {
  final String path;
  final String fileName;
  final DateTime date;
  final int sizeBytes;

  const BackupInfo({
    required this.path,
    required this.fileName,
    required this.date,
    required this.sizeBytes,
  });

  String get sizeLabel {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}

class BackupService {
  static final BackupService _instance = BackupService._internal();
  factory BackupService() => _instance;
  BackupService._internal();

  static const _prefLastBackup = 'last_backup_date';
  static const _prefBackupEnabled = 'backup_enabled';
  static const _maxAutoBackups = 7;

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String _uid = FirebaseService().uid;

  // ═══════════════════════════════════════════════════════════
  //  설정
  // ═══════════════════════════════════════════════════════════

  /// 자동 백업 활성화 여부
  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefBackupEnabled) ?? true; // 기본 활성화
  }

  Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefBackupEnabled, enabled);
    debugPrint('[Backup] enabled=$enabled');
  }

  // ═══════════════════════════════════════════════════════════
  //  autoBackup — 취침 시/앱 백그라운드 전환 시 호출
  // ═══════════════════════════════════════════════════════════

  /// 자동 백업 실행. 오늘 이미 백업했으면 스킵.
  Future<void> autoBackup() async {
    try {
      // 활성화 체크
      if (!await isEnabled()) {
        debugPrint('[Backup] disabled, skip');
        return;
      }

      // 오늘 이미 백업했는지 체크
      final prefs = await SharedPreferences.getInstance();
      final today = StudyDateUtils.todayKey();
      final lastBackup = prefs.getString(_prefLastBackup);
      if (lastBackup == today) {
        debugPrint('[Backup] already done today ($today), skip');
        return;
      }

      debugPrint('[Backup] auto backup starting...');

      // 핵심 문서 수집
      final docs = await _fetchCoreDocs();
      if (docs.isEmpty) {
        debugPrint('[Backup] no data to backup');
        return;
      }

      // 메타데이터 생성
      final now = DateTime.now();
      final backup = <String, dynamic>{
        '_meta': {
          'date': DateFormat('yyyy-MM-dd HH:mm:ss').format(now),
          'version': 'v10.4.0',
          'docCount': docs.length,
          'type': 'auto',
        },
        'docs': docs,
      };

      // JSON 인코딩
      final jsonStr = _safeEncode(backup);
      final sizeKb = (jsonStr.length / 1024).toStringAsFixed(1);

      // 파일 저장
      final file = await _saveToFile(jsonStr, now);
      debugPrint('[Backup] saved: ${file.path} (${sizeKb}KB)');

      // 오래된 백업 정리
      await _cleanOldBackups();

      // 마지막 백업 날짜 기록
      await prefs.setString(_prefLastBackup, today);

      // 텔레그램 알림
      TelegramService().sendToMe(
        '\u{1F4E6} 자동 백업 완료 (${docs.length}개 문서, ${sizeKb}KB)',
      );

      debugPrint('[Backup] auto backup complete');
    } catch (e, st) {
      debugPrint('[Backup] auto backup failed: $e');
      debugPrint('[Backup] $st');
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  exportAll — 수동 전체 내보내기 (최근 3개월 히스토리 포함)
  // ═══════════════════════════════════════════════════════════

  /// 전체 데이터 JSON 문자열 반환 (수동 내보내기용)
  Future<String> exportAll() async {
    debugPrint('[Backup] full export starting...');

    // 핵심 문서
    final docs = await _fetchCoreDocs();

    // 최근 3개월 히스토리 추가
    final now = DateTime.now();
    for (int i = 0; i < 3; i++) {
      final dt = DateTime(now.year, now.month - i, 1);
      final monthKey = DateFormat('yyyy-MM').format(dt);
      final docPath = 'users/$_uid/history/$monthKey';
      final data = await _fetchDoc(docPath);
      if (data != null) {
        docs['history_$monthKey'] = data;
      }
    }

    // NFC 이벤트 (최근 7일)
    for (int i = 0; i < 7; i++) {
      final dt = now.subtract(Duration(days: i));
      final dateKey = DateFormat('yyyy-MM-dd').format(dt);
      final docPath = 'users/$_uid/nfcEvents/$dateKey';
      final data = await _fetchDoc(docPath);
      if (data != null) {
        docs['nfcEvents_$dateKey'] = data;
      }
    }

    final backup = <String, dynamic>{
      '_meta': {
        'date': DateFormat('yyyy-MM-dd HH:mm:ss').format(now),
        'version': 'v10.4.0',
        'docCount': docs.length,
        'type': 'manual_full',
      },
      'docs': docs,
    };

    final jsonStr = _safeEncode(backup);
    final sizeKb = (jsonStr.length / 1024).toStringAsFixed(1);

    // 수동 백업도 파일로 저장
    await _saveToFile(jsonStr, now);
    await _cleanOldBackups();

    debugPrint('[Backup] full export done: ${docs.length} docs, ${sizeKb}KB');
    return jsonStr;
  }

  // ═══════════════════════════════════════════════════════════
  //  getBackupList — 로컬 백업 목록 조회
  // ═══════════════════════════════════════════════════════════

  /// 로컬에 저장된 백업 파일 목록 반환 (최신순)
  Future<List<BackupInfo>> getBackupList() async {
    try {
      final dir = await _backupDir();
      if (!await dir.exists()) return [];

      final files = await dir
          .list()
          .where((e) => e is File && e.path.endsWith('.json'))
          .cast<File>()
          .toList();

      final infos = <BackupInfo>[];
      for (final file in files) {
        final stat = await file.stat();
        final fileName = file.path.split(Platform.pathSeparator).last;

        // 파일명에서 날짜 파싱: backup_yyyy-MM-dd_HHmm.json
        DateTime date;
        try {
          final match = RegExp(r'backup_(\d{4}-\d{2}-\d{2}_\d{4})\.json').firstMatch(fileName);
          if (match != null) {
            date = DateFormat('yyyy-MM-dd_HHmm').parse(match.group(1)!);
          } else {
            date = stat.modified;
          }
        } catch (_) {
          date = stat.modified;
        }

        infos.add(BackupInfo(
          path: file.path,
          fileName: fileName,
          date: date,
          sizeBytes: stat.size,
        ));
      }

      // 최신순 정렬
      infos.sort((a, b) => b.date.compareTo(a.date));
      return infos;
    } catch (e) {
      debugPrint('[Backup] getBackupList failed: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  restoreFromBackup — 로컬 백업에서 복원
  // ═══════════════════════════════════════════════════════════

  /// 지정된 백업 파일에서 Firestore로 복원
  Future<bool> restoreFromBackup(String path) async {
    try {
      debugPrint('[Backup] restore starting from: $path');

      final file = File(path);
      if (!await file.exists()) {
        debugPrint('[Backup] restore failed: file not found');
        return false;
      }

      final jsonStr = await file.readAsString();
      final backup = jsonDecode(jsonStr) as Map<String, dynamic>;

      final meta = backup['_meta'] as Map<String, dynamic>?;
      final docs = backup['docs'] as Map<String, dynamic>?;

      if (docs == null || docs.isEmpty) {
        debugPrint('[Backup] restore failed: no docs in backup');
        return false;
      }

      debugPrint('[Backup] restoring ${docs.length} docs (backup: ${meta?['date']})...');

      int restored = 0;

      for (final entry in docs.entries) {
        final docPath = _resolveDocPath(entry.key);
        if (docPath == null) continue;

        final data = Map<String, dynamic>.from(entry.value as Map);
        // Timestamp 필드 제거 (복원 시 서버 타임스탬프 사용)
        data.remove('_updatedAt');
        data['lastModified'] = DateTime.now().millisecondsSinceEpoch;
        data['lastDevice'] = 'android';
        data['_restoredAt'] = DateTime.now().millisecondsSinceEpoch;

        try {
          await _db.doc(docPath)
              .set(data, SetOptions(merge: true))
              .timeout(const Duration(seconds: 10));
          restored++;
          debugPrint('[Backup] restored: $docPath');
        } catch (e) {
          debugPrint('[Backup] restore doc failed ($docPath): $e');
        }
      }

      debugPrint('[Backup] restore complete: $restored/${docs.length} docs');

      TelegramService().sendToMe(
        '\u{1F504} 백업 복원 완료 ($restored/${docs.length}개 문서)\n'
        '원본: ${meta?['date'] ?? 'unknown'}',
      );

      return restored > 0;
    } catch (e, st) {
      debugPrint('[Backup] restore failed: $e');
      debugPrint('[Backup] $st');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  Private helpers
  // ═══════════════════════════════════════════════════════════

  /// 백업 디렉토리 반환
  Future<Directory> _backupDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${appDir.path}${Platform.pathSeparator}backups');
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    return backupDir;
  }

  /// 핵심 Firestore 문서들 수집 (today, study, creature, 이번 달 history)
  Future<Map<String, dynamic>> _fetchCoreDocs() async {
    final docs = <String, dynamic>{};
    final now = DateTime.now();
    final currentMonth = DateFormat('yyyy-MM').format(now);

    // 병렬 수집
    final results = await Future.wait([
      _fetchDoc('users/$_uid/data/today'),
      _fetchDoc('users/$_uid/data/study'),
      _fetchDoc('users/$_uid/data/liveFocus'),
      _fetchDoc('users/$_uid/history/$currentMonth'),
      _fetchDoc('users/$_uid/settings/nfcTags'),
    ].map((f) => f.timeout(const Duration(seconds: 15), onTimeout: () => null)));

    final keys = ['today', 'study', 'liveFocus', 'history_$currentMonth', 'nfcTags'];
    for (int i = 0; i < keys.length; i++) {
      if (results[i] != null) {
        docs[keys[i]] = results[i];
      }
    }

    // 메모 컬렉션 (별도 처리)
    try {
      final memoSnap = await _db.collection('users/$_uid/memos')
          .get()
          .timeout(const Duration(seconds: 10));
      if (memoSnap.docs.isNotEmpty) {
        final memos = <String, dynamic>{};
        for (final doc in memoSnap.docs) {
          memos[doc.id] = doc.data();
        }
        docs['memos'] = memos;
      }
    } catch (e) {
      debugPrint('[Backup] memos fetch failed: $e');
    }

    return docs;
  }

  /// 단일 Firestore 문서 가져오기 (서버 우선, 캐시 fallback)
  Future<Map<String, dynamic>?> _fetchDoc(String docPath) async {
    try {
      final doc = await _db.doc(docPath)
          .get()
          .timeout(const Duration(seconds: 10));
      if (doc.exists && doc.data() != null) {
        return doc.data();
      }
    } catch (e) {
      // 서버 실패 시 캐시 시도
      try {
        final cacheDoc = await _db.doc(docPath)
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(seconds: 3));
        if (cacheDoc.exists && cacheDoc.data() != null) {
          debugPrint('[Backup] $docPath: cache fallback');
          return cacheDoc.data();
        }
      } catch (_) {}
      debugPrint('[Backup] fetch failed: $docPath ($e)');
    }
    return null;
  }

  /// JSON 파일로 저장
  Future<File> _saveToFile(String jsonStr, DateTime now) async {
    final dir = await _backupDir();
    final fileName = 'backup_${DateFormat('yyyy-MM-dd_HHmm').format(now)}.json';
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    await file.writeAsString(jsonStr, flush: true);
    return file;
  }

  /// 오래된 백업 정리 (최근 _maxAutoBackups개만 유지)
  Future<void> _cleanOldBackups() async {
    try {
      final backups = await getBackupList();
      if (backups.length <= _maxAutoBackups) return;

      // 최신순 정렬된 상태에서 초과분 삭제
      final toDelete = backups.sublist(_maxAutoBackups);
      for (final info in toDelete) {
        try {
          await File(info.path).delete();
          debugPrint('[Backup] deleted old: ${info.fileName}');
        } catch (e) {
          debugPrint('[Backup] delete failed: ${info.fileName} ($e)');
        }
      }
    } catch (e) {
      debugPrint('[Backup] cleanup failed: $e');
    }
  }

  /// 백업 키를 Firestore 문서 경로로 변환
  String? _resolveDocPath(String key) {
    // 핵심 문서
    switch (key) {
      case 'today':
        return 'users/$_uid/data/today';
      case 'study':
        return 'users/$_uid/data/study';
      case 'liveFocus':
        return 'users/$_uid/data/liveFocus';
      case 'nfcTags':
        return 'users/$_uid/settings/nfcTags';
    }

    // history_yyyy-MM
    if (key.startsWith('history_')) {
      final month = key.substring(8); // 'history_'.length == 8
      return 'users/$_uid/history/$month';
    }

    // nfcEvents_yyyy-MM-dd
    if (key.startsWith('nfcEvents_')) {
      final date = key.substring(10); // 'nfcEvents_'.length == 10
      return 'users/$_uid/nfcEvents/$date';
    }

    // memos는 컬렉션이라 별도 처리 필요 → 단일 doc 복원 안 함
    if (key == 'memos') return null;

    debugPrint('[Backup] unknown doc key: $key');
    return null;
  }

  /// Firestore Timestamp를 JSON-safe 값으로 재귀 변환
  String _safeEncode(dynamic data) {
    return const JsonEncoder.withIndent('  ').convert(_sanitize(data));
  }

  /// Timestamp, DateTime 등 JSON 미지원 타입 재귀 변환
  dynamic _sanitize(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.millisecondsSinceEpoch;
    if (value is DateTime) return value.millisecondsSinceEpoch;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), _sanitize(v)));
    }
    if (value is List) {
      return value.map(_sanitize).toList();
    }
    // num, String, bool 등 기본 타입은 그대로
    if (value is num || value is String || value is bool) return value;
    // FieldValue 등 직렬화 불가 타입 → 문자열로
    return value.toString();
  }

  /// 백업에서 memos 컬렉션 복원 (별도 메서드)
  Future<int> restoreMemosFromBackup(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return 0;

      final jsonStr = await file.readAsString();
      final backup = jsonDecode(jsonStr) as Map<String, dynamic>;
      final docs = backup['docs'] as Map<String, dynamic>?;
      if (docs == null) return 0;

      final memos = docs['memos'] as Map<String, dynamic>?;
      if (memos == null || memos.isEmpty) return 0;

      int restored = 0;
      for (final entry in memos.entries) {
        try {
          final data = Map<String, dynamic>.from(entry.value as Map);
          data.remove('_updatedAt');
          await _db.collection('users/$_uid/memos')
              .doc(entry.key)
              .set(data, SetOptions(merge: true))
              .timeout(const Duration(seconds: 5));
          restored++;
        } catch (e) {
          debugPrint('[Backup] restore memo ${entry.key} failed: $e');
        }
      }

      debugPrint('[Backup] restored $restored memos');
      return restored;
    } catch (e) {
      debugPrint('[Backup] restoreMemosFromBackup failed: $e');
      return 0;
    }
  }
}
