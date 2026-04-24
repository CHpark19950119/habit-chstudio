import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/life_logs_models.dart';

/// LIFE_LOGS 읽기 전용 서비스
/// - HB 세션이 Firestore 에 기입, 앱은 조회만
/// - 경로: users/cheonhong/life_logs/{yyyy-MM-dd}
class LifeLogsService {
  static const String _uid = 'cheonhong';

  static CollectionReference<Map<String, dynamic>> _coll() =>
      FirebaseFirestore.instance.collection('users').doc(_uid).collection('life_logs');

  /// 특정 날짜의 LifeLog 스트림
  static Stream<LifeLog> streamByDate(String yyyymmdd) {
    return _coll().doc(yyyymmdd).snapshots().map((snap) {
      final data = snap.data() ?? <String, dynamic>{};
      return LifeLog.fromMap(yyyymmdd, data);
    });
  }

  /// 한 번 조회
  static Future<LifeLog> fetchByDate(String yyyymmdd) async {
    final snap = await _coll().doc(yyyymmdd).get();
    final data = snap.data() ?? <String, dynamic>{};
    return LifeLog.fromMap(yyyymmdd, data);
  }

  /// 최근 N일 (오늘 포함) 조회
  static Future<List<LifeLog>> fetchRecent(int days) async {
    final today = DateTime.now();
    final dates = List.generate(days, (i) {
      final d = today.subtract(Duration(days: i));
      return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    });
    final results = await Future.wait(dates.map(fetchByDate));
    return results;
  }
}
