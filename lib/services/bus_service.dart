import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'telegram_service.dart';

/// 버스 도착정보 서비스
/// 기상 → 5분 주기 텔레그램 전송 → 외출 시 중단
class BusService {
  static final BusService _instance = BusService._();
  factory BusService() => _instance;
  BusService._();

  static const _hardcodedKey =
      '437f2a7403f7b513b880e5d996044d5e1144695e65c4a9d1c11e26c13ea5384c';
  static const _prefsKeyStops = 'bus_stops';
  static const _pollInterval = Duration(minutes: 15);

  /// 기본 정류장 (하드코딩)
  static final List<BusStop> _defaultStops = [
    BusStop(
      stationId: '225000430',
      name: '금강4단지 (26411)',
      mobileNo: '26411',
    ),
    BusStop(
      stationId: '225000264',
      name: '송정마을 (26023)',
      mobileNo: '26023',
    ),
  ];

  Timer? _timer;
  bool _isPolling = false;

  // ═══ 정류장 설정 ═══
  Future<List<BusStop>> getStops() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKeyStops);
    if (raw == null) return _defaultStops;
    try {
      final list = jsonDecode(raw) as List;
      final stops =
          list.map((e) => BusStop.fromMap(e as Map<String, dynamic>)).toList();
      return stops.isEmpty ? _defaultStops : stops;
    } catch (_) {
      return _defaultStops;
    }
  }

  Future<void> setStops(List<BusStop> stops) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKeyStops, jsonEncode(stops.map((s) => s.toMap()).toList()));
  }

  // ═══ 폴링 시작/중단 ═══
  void startPolling() {
    // ★ 비활성화 — 배터리 최적화 (v10.14.7)
    print('[Bus] Polling disabled for battery optimization');
    return;
  }

  void stopPolling() {
    _timer?.cancel();
    _timer = null;
    _isPolling = false;
    print('[Bus] Polling stopped');
  }

  bool get isPolling => _isPolling;

  /// 수동 요청 — 즉시 버스 도착정보 Telegram 전송
  Future<void> fetchNow() => _fetchAndSend();

  // ═══ 방향 라벨 매핑 ═══
  static const _dirLabels = <String, String>{
    '대야미역': '🚉 대야미역(송정초) 방면',
    '군포시청': '📚 도서관(차고지) 방면',
    '산본역': '📚 도서관(차고지) 방면',
    '산본': '📚 도서관(차고지) 방면',
    '차고지': '📚 도서관(차고지) 방면',
    '구로디지털단지역': '🏙️ 서울 방면',
  };

  String _dirLabel(String destName) {
    for (final e in _dirLabels.entries) {
      if (destName.contains(e.key)) return e.value;
    }
    return '→$destName';
  }

  // ═══ API 호출 + 텔레그램 전송 ═══
  Future<void> _fetchAndSend() async {
    try {
      final stops = await getStops();
      if (stops.isEmpty) return;

      final buffer = StringBuffer();
      buffer.writeln('🚌 버스 도착 정보');
      buffer.writeln('━━━━━━━━━━━━');

      bool hasData = false;

      for (final stop in stops) {
        final arrivals = await _fetchArrivals(stop.stationId);
        final active = arrivals.where((a) => a.predictTime > 0).toList();
        if (active.isEmpty) continue;

        final filtered = stop.routes.isEmpty
            ? active
            : active.where((a) => stop.routes.contains(a.routeName)).toList();
        if (filtered.isEmpty) continue;

        hasData = true;
        buffer.writeln('📍 ${stop.name}');

        // 방향별 그룹핑
        final groups = <String, List<BusArrival>>{};
        for (final a in filtered) {
          final dir = _dirLabel(a.destName);
          (groups[dir] ??= []).add(a);
        }

        for (final entry in groups.entries) {
          buffer.writeln('  ${entry.key}');
          for (final a in entry.value.take(3)) {
            final loc = a.locationNo > 0 ? ' (${a.locationNo}정거장)' : '';
            final seats = a.remainSeatCnt >= 0 ? ' [${a.remainSeatCnt}석]' : '';
            buffer.writeln('    ${a.routeName}번 ${a.predictTime}분$loc$seats');
          }
        }
        buffer.writeln('');
      }

      if (hasData) {
        await TelegramService().sendToMe(buffer.toString().trim());
        print('[Bus] Sent to Telegram');
      } else {
        await TelegramService().sendToMe('🚌 현재 운행 중인 버스가 없습니다');
        print('[Bus] No active buses');
      }
    } catch (e) {
      print('[Bus] Error: $e');
    }
  }

  // ═══ 경기도 GBIS API v2 호출 ═══
  Future<List<BusArrival>> _fetchArrivals(String stationId) async {
    final url = Uri.parse(
      'https://apis.data.go.kr/6410000/busarrivalservice/v2'
      '/getBusArrivalListv2'
      '?serviceKey=$_hardcodedKey&stationId=$stationId&_type=json',
    );

    final response = await http.get(url).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return [];

    final data = jsonDecode(response.body);
    final header = data['response']?['msgHeader'];
    if (header == null || header['resultCode'] != 0) return [];

    final body = data['response']?['msgBody'];
    if (body == null) return [];

    final items = body['busArrivalList'];
    if (items == null) return [];

    final list = items is List ? items : [items];
    return list
        .map((e) => BusArrival.fromMap(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.predictTime.compareTo(b.predictTime));
  }
}

// ═══ 모델 ═══
class BusStop {
  final String stationId;
  final String name;
  final String mobileNo;
  final List<String> routes; // 빈 리스트 = 전체 노선

  BusStop({
    required this.stationId,
    required this.name,
    this.mobileNo = '',
    this.routes = const [],
  });

  Map<String, dynamic> toMap() => {
        'stationId': stationId,
        'name': name,
        'mobileNo': mobileNo,
        'routes': routes,
      };

  factory BusStop.fromMap(Map<String, dynamic> m) => BusStop(
        stationId: m['stationId'] ?? '',
        name: m['name'] ?? '',
        mobileNo: m['mobileNo'] ?? '',
        routes: List<String>.from(m['routes'] ?? []),
      );
}

class BusArrival {
  final String routeName;
  final String destName; // 종점 (방향)
  final int predictTime;
  final int locationNo;
  final int remainSeatCnt;

  BusArrival({
    required this.routeName,
    this.destName = '',
    required this.predictTime,
    this.locationNo = -1,
    this.remainSeatCnt = -1,
  });

  factory BusArrival.fromMap(Map<String, dynamic> m) => BusArrival(
        routeName: '${m['routeName'] ?? ''}',
        destName: '${m['routeDestName'] ?? ''}'.trim(),
        predictTime: _parseInt(m['predictTime1']),
        locationNo: _parseInt(m['locationNo1']),
        remainSeatCnt: _parseInt(m['remainSeatCnt1']),
      );

  static int _parseInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? -1;
    return -1;
  }
}
