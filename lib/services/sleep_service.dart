import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_service.dart';
import '../models/models.dart';

/// SleepService — Samsung Health(Health Connect) 의 SleepSession 을 읽어
/// timeRecords.{date}.bedTime 으로 자동 기록한다.
///
/// 기존 _handleSleep 은 사용자 수동 트리거 (cheonhong://sleep) 전용으로 둔다.
/// 본 서비스는 백그라운드/주기 동기화로 "지난 밤 자동 기록" 만 담당.
///
/// 동작 모델:
/// - Samsung Health 가 폰 가속도·심박·screen state 로 sleep session 추론 → Health Connect 에 기록
/// - 본 서비스가 매 동기화마다 Health Connect 에 지난 24h sleep session 질의
/// - 가장 최근에 끝난 (그리고 아직 미기록) session 의 start 를 bedTime, end 를 wake 로 매핑
/// - 날짜 귀속: session 의 end 가 04:00 이전이면 전날, 이후면 당일
class SleepService {
  static final SleepService _instance = SleepService._internal();
  factory SleepService() => _instance;
  SleepService._internal();

  final Health _health = Health();
  bool _initialized = false;
  bool _enabled = false;
  Timer? _periodicSync;

  bool get enabled => _enabled;
  bool get initialized => _initialized;

  /// 초기화 — app_init 에서 호출. enable=false 가 기본값이라
  /// 사용자가 설정에서 켜기 전엔 health API 접근 안 함.
  Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool('sleep_health_enabled') ?? false;
    if (_enabled) {
      try {
        await _health.configure();
      } catch (e) {
        debugPrint('[SleepService] configure 실패: $e');
        _enabled = false;
      }
      _startPeriodicSync();
    }
    _initialized = true;
    debugPrint('[SleepService] init: enabled=$_enabled');
  }

  /// 사용자 설정에서 토글
  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sleep_health_enabled', value);
    _enabled = value;
    if (value) {
      try {
        await _health.configure();
        final ok = await requestAuthorization();
        if (!ok) {
          debugPrint('[SleepService] 권한 거부 → enabled 유지하되 sync 불가');
        }
        _startPeriodicSync();
      } catch (e) {
        debugPrint('[SleepService] enable 실패: $e');
      }
    } else {
      _periodicSync?.cancel();
      _periodicSync = null;
    }
  }

  /// Health Connect 권한 요청
  Future<bool> requestAuthorization() async {
    try {
      final types = [HealthDataType.SLEEP_SESSION];
      final granted = await _health.requestAuthorization(types);
      debugPrint('[SleepService] 권한 요청 결과: $granted');
      return granted;
    } catch (e) {
      debugPrint('[SleepService] requestAuthorization 실패: $e');
      return false;
    }
  }

  /// 권한 보유 여부 (요청 없이 조회만)
  Future<bool> hasPermissions() async {
    try {
      final result = await _health.hasPermissions([HealthDataType.SLEEP_SESSION]);
      return result == true;
    } catch (e) {
      return false;
    }
  }

  void _startPeriodicSync() {
    _periodicSync?.cancel();
    // 매 30분 한 번 sync — 기상 직후~점심 사이 자동 캐치업
    _periodicSync = Timer.periodic(const Duration(minutes: 30), (_) {
      syncRecentSleep();
    });
    // 즉시 한 번
    Future.delayed(const Duration(seconds: 5), syncRecentSleep);
  }

  /// 지난 24h sleep session 조회 → 미기록건 Firestore 반영
  Future<SleepSyncResult> syncRecentSleep() async {
    if (!_enabled) return SleepSyncResult.disabled();
    try {
      final hasPerm = await hasPermissions();
      if (!hasPerm) {
        return SleepSyncResult.noPermission();
      }
      final now = DateTime.now();
      final start = now.subtract(const Duration(hours: 30));
      final dataPoints = await _health.getHealthDataFromTypes(
        startTime: start,
        endTime: now,
        types: [HealthDataType.SLEEP_SESSION],
      );
      if (dataPoints.isEmpty) {
        return SleepSyncResult.noData();
      }
      // 가장 늦게 끝난 session 사용
      dataPoints.sort((a, b) => b.dateTo.compareTo(a.dateTo));
      final session = dataPoints.first;
      final bedTime = session.dateFrom;
      final wakeTime = session.dateTo;

      // 날짜 귀속: end 가 04:00 이전이면 전날
      final attributionDate = wakeTime.hour < 4
          ? wakeTime.subtract(const Duration(days: 1))
          : wakeTime;
      final dateStr = DateFormat('yyyy-MM-dd').format(attributionDate);
      final bedTimeStr = DateFormat('HH:mm').format(bedTime);

      // 이미 기록된 bedTime 이 있으면 skip
      final fb = FirebaseService();
      final records = await fb.getTimeRecords().timeout(const Duration(seconds: 5));
      final existing = records[dateStr];
      if (existing?.bedTime != null) {
        return SleepSyncResult.alreadyRecorded(dateStr, existing!.bedTime!);
      }
      // bedTime 만 보정 기입 — wake 는 도어센서 흐름이 기존 처리
      await fb.updateTimeRecord(
        dateStr,
        _withSleep(dateStr, existing, bedTimeStr),
      ).timeout(const Duration(seconds: 5));
      debugPrint('[SleepService] 자동 기록: $dateStr bedTime=$bedTimeStr (Health Connect)');
      return SleepSyncResult.recorded(dateStr, bedTimeStr);
    } catch (e) {
      debugPrint('[SleepService] sync 에러: $e');
      return SleepSyncResult.error(e.toString());
    }
  }

  /// bedTime 만 갱신, 다른 필드는 유지
  TimeRecord _withSleep(String dateStr, TimeRecord? prev, String bedTime) {
    return TimeRecord(
      date: dateStr,
      wake: prev?.wake,
      outing: prev?.outing,
      returnHome: prev?.returnHome,
      arrival: prev?.arrival,
      bedTime: bedTime,
      mealStart: prev?.mealStart,
      mealEnd: prev?.mealEnd,
      meals: prev?.meals,
      noOuting: prev?.noOuting ?? false,
    );
  }

  void dispose() {
    _periodicSync?.cancel();
    _periodicSync = null;
  }
}

class SleepSyncResult {
  final String status; // recorded | already | nodata | nopermission | disabled | error
  final String? date;
  final String? bedTime;
  final String? error;

  SleepSyncResult._(this.status, {this.date, this.bedTime, this.error});

  factory SleepSyncResult.recorded(String date, String bedTime) =>
      SleepSyncResult._('recorded', date: date, bedTime: bedTime);
  factory SleepSyncResult.alreadyRecorded(String date, String bedTime) =>
      SleepSyncResult._('already', date: date, bedTime: bedTime);
  factory SleepSyncResult.noData() => SleepSyncResult._('nodata');
  factory SleepSyncResult.noPermission() => SleepSyncResult._('nopermission');
  factory SleepSyncResult.disabled() => SleepSyncResult._('disabled');
  factory SleepSyncResult.error(String msg) => SleepSyncResult._('error', error: msg);

  @override
  String toString() {
    switch (status) {
      case 'recorded': return '기록됨 $date $bedTime';
      case 'already': return '이미 기록됨 $date $bedTime';
      case 'nodata': return 'Health Connect 에 sleep session 없음';
      case 'nopermission': return 'Health Connect 권한 없음';
      case 'disabled': return 'SleepService 비활성';
      case 'error': return '에러: $error';
      default: return status;
    }
  }
}
