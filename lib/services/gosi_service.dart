import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 고시 공고 서비스 — CF gosiNotice 엔드포인트 경유
class GosiService {
  static final GosiService _instance = GosiService._internal();
  factory GosiService() => _instance;
  GosiService._internal();

  static const _cfBase =
      'https://us-central1-cheonhong-studio.cloudfunctions.net/gosiNotice';

  List<GosiNotice> _cached = [];
  DateTime? _lastFetch;

  List<GosiNotice> get notices => _cached;

  /// CF에서 새 공고 파싱 트리거 + 결과 반환
  Future<List<GosiNotice>> fetchNew() async {
    try {
      final uri = Uri.parse('$_cfBase?q=fetch');
      final resp = await http.get(uri).timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true && body['notices'] is List) {
          _cached = (body['notices'] as List)
              .map((e) => GosiNotice.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList();
          _lastFetch = DateTime.now();
        }
      }
    } catch (e) {
      debugPrint('[GosiService] fetch error: $e');
    }
    return _cached;
  }

  /// Firestore에 저장된 공고 목록 읽기 (캐시 5분)
  Future<List<GosiNotice>> getNotices({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cached.isNotEmpty &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!) < const Duration(minutes: 5)) {
      return _cached;
    }
    try {
      final uri = Uri.parse('$_cfBase?q=list');
      final resp = await http.get(uri).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final body = json.decode(resp.body) as Map<String, dynamic>;
        if (body['ok'] == true && body['notices'] is List) {
          _cached = (body['notices'] as List)
              .map((e) => GosiNotice.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList();
          _lastFetch = DateTime.now();
        }
      }
    } catch (e) {
      debugPrint('[GosiService] list error: $e');
    }
    return _cached;
  }
}

/// 고시 공고 모델
class GosiNotice {
  final String id;
  final int no;
  final String category;
  final String title;
  final String date;
  final String url;

  const GosiNotice({
    required this.id,
    required this.no,
    required this.category,
    required this.title,
    required this.date,
    required this.url,
  });

  factory GosiNotice.fromMap(Map<String, dynamic> m) => GosiNotice(
        id: m['id']?.toString() ?? '',
        no: (m['no'] as num?)?.toInt() ?? 0,
        category: m['category']?.toString() ?? '',
        title: m['title']?.toString() ?? '',
        date: m['date']?.toString() ?? '',
        url: m['url']?.toString() ?? '',
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'no': no,
        'category': category,
        'title': title,
        'date': date,
        'url': url,
      };
}
