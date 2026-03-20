import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'location_service.dart';

/// GeofenceService — 집 위치 기반 자동 외출/귀가 감지
/// 순수 Dart 구현: 3분마다 GPS 체크 → 거리 기반 판단
class GeofenceService extends ChangeNotifier {
  static final GeofenceService _instance = GeofenceService._internal();
  factory GeofenceService() => _instance;
  GeofenceService._internal();

  static const double _radiusMeters = 150.0;  // 150m 반경
  static const int _confirmCount = 2;          // 2회 연속 확인 후 전환
  static const Duration _checkInterval = Duration(minutes: 10);

  double? _homeLat;
  double? _homeLng;
  bool _enabled = false;
  bool _isHome = true;
  Timer? _timer;
  int _exitCount = 0;   // 연속 외출 감지 횟수
  int _enterCount = 0;  // 연속 귀가 감지 횟수

  bool get enabled => _enabled;
  bool get isHome => _isHome;
  double? get homeLat => _homeLat;
  double? get homeLng => _homeLng;
  bool get hasHome => _homeLat != null && _homeLng != null;

  final _controller = StreamController<bool>.broadcast();
  /// true = 귀가(ENTER), false = 외출(EXIT)
  Stream<bool> get homeStream => _controller.stream;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('geofence_enabled') ?? false;
      _homeLat = prefs.getDouble('geofence_home_lat');
      _homeLng = prefs.getDouble('geofence_home_lng');
      _isHome = prefs.getBool('geofence_is_home') ?? true;
      debugPrint('[Geofence] init: enabled=$_enabled, home=$_homeLat,$_homeLng, isHome=$_isHome');

      if (_enabled && hasHome) _startTimer();
    } catch (e) {
      debugPrint('[Geofence] init error: $e');
    }
  }

  /// 집 위치 수동 등록
  Future<void> setHomeLocation(double lat, double lng) async {
    _homeLat = lat;
    _homeLng = lng;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('geofence_home_lat', lat);
    await prefs.setDouble('geofence_home_lng', lng);
    debugPrint('[Geofence] home set: $lat, $lng');
    if (_enabled) _startTimer();
    notifyListeners();
  }

  /// 현재 GPS로 집 위치 설정
  Future<bool> setHomeFromCurrentLocation() async {
    try {
      final pos = await LocationService().getCurrentPosition();
      if (pos != null) {
        await setHomeLocation(pos.latitude, pos.longitude);
        return true;
      }
    } catch (e) {
      debugPrint('[Geofence] setHomeFromCurrent error: $e');
    }
    return false;
  }

  Future<void> setEnabled(bool v) async {
    _enabled = v;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('geofence_enabled', v);
    if (v && hasHome) {
      _startTimer();
    } else {
      _stopTimer();
    }
    notifyListeners();
  }

  void _startTimer() {
    _stopTimer();
    // ★ 집에 있으면 GPS 폴링 안 함 — 외출 시에만 작동 (v10.14.7)
    if (_isHome) {
      debugPrint('[Geofence] Home — GPS polling paused');
      return;
    }
    _timer = Timer.periodic(_checkInterval, (_) => _checkLocation());
    _checkLocation();
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
    _exitCount = 0;
    _enterCount = 0;
  }

  Future<void> _checkLocation() async {
    if (!hasHome || !_enabled) return;
    try {
      final pos = await LocationService().getCurrentPosition();
      if (pos == null) return;

      final dist = Geolocator.distanceBetween(
        _homeLat!, _homeLng!, pos.latitude, pos.longitude,
      );

      debugPrint('[Geofence] dist=${dist.toInt()}m, isHome=$_isHome, exit=$_exitCount, enter=$_enterCount');

      if (dist > _radiusMeters) {
        // 집 밖
        _enterCount = 0;
        _exitCount++;
        if (_isHome && _exitCount >= _confirmCount) {
          _isHome = false;
          _exitCount = 0;
          _saveIsHome(false);
          _controller.add(false); // EXIT
          debugPrint('[Geofence] ▶ EXIT (외출) dist=${dist.toInt()}m');
        }
      } else {
        // 집 안
        _exitCount = 0;
        _enterCount++;
        if (!_isHome && _enterCount >= _confirmCount) {
          _isHome = true;
          _enterCount = 0;
          _saveIsHome(true);
          _controller.add(true); // ENTER
          _stopTimer(); // ★ 귀가 → GPS 폴링 즉시 중단
          debugPrint('[Geofence] ▶ ENTER (귀가) dist=${dist.toInt()}m — GPS stopped');
        }
      }
    } catch (e) {
      debugPrint('[Geofence] check error: $e');
    }
  }

  Future<void> _saveIsHome(bool v) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('geofence_is_home', v);
    } catch (_) {}
  }

  @override
  void dispose() {
    _stopTimer();
    _controller.close();
    super.dispose();
  }
}
