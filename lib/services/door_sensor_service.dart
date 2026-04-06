import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/iot_models.dart';

import '../constants.dart';
import 'day_service.dart';

/// ═══════════════════════════════════════════════════════════
///  DoorSensorService — IoT 도어 센서 연동
///  Firestore `users/{uid}/data/iot` 의 door 필드 감시
///  DayState FSM과 연동하여 외출/귀가 감지 보조
/// ═══════════════════════════════════════════════════════════
class DoorSensorService extends ChangeNotifier {
  static final DoorSensorService _instance = DoorSensorService._internal();
  factory DoorSensorService() => _instance;
  DoorSensorService._internal();

  // ═══ Firestore ═══
  static final String _iotDocPath = kIotDoc;

  // ═══ 상태 ═══
  bool _enabled = false;
  bool _initialized = false;
  int _debounceSeconds = 30;
  DoorState _lastDoorState = DoorState.unknown;
  DateTime? _lastEventTime;
  StreamSubscription<DocumentSnapshot>? _firestoreSub;

  // ═══ 이벤트 스트림 (외부 서비스 연동용) ═══
  final _eventController = StreamController<DoorEvent>.broadcast();

  // ═══ Getters ═══
  bool get enabled => _enabled;
  bool get initialized => _initialized;
  int get debounceSeconds => _debounceSeconds;
  DoorState get lastDoorState => _lastDoorState;
  DateTime? get lastEventTime => _lastEventTime;
  Stream<DoorEvent> get eventStream => _eventController.stream;

  // ═══ 로깅 ═══
  void _log(String msg) {
    debugPrint('[Door] $msg');
  }

  // ═══════════════════════════════════════════
  //  초기화
  // ═══════════════════════════════════════════

  Future<void> init() async {
    if (_initialized) return;
    _log('초기화 시작');

    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('door_sensor_enabled') ?? false;
      _debounceSeconds = prefs.getInt('door_debounce_seconds') ?? 30;

      if (_enabled) {
        _startListening();
      }

      _initialized = true;
      _log('초기화 완료 (enabled=$_enabled, debounce=${_debounceSeconds}s)');
    } catch (e) {
      _log('초기화 에러: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  활성화/비활성화
  // ═══════════════════════════════════════════

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('door_sensor_enabled', value);
    } catch (_) {}

    if (value) {
      _startListening();
      _log('활성화');
    } else {
      _stopListening();
      _log('비활성화');
    }
    notifyListeners();
  }

  Future<void> setDebounceSeconds(int seconds) async {
    _debounceSeconds = seconds.clamp(5, 300);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('door_debounce_seconds', _debounceSeconds);
    } catch (_) {}
    _log('디바운스 변경: ${_debounceSeconds}s');
    notifyListeners();
  }

  // ═══════════════════════════════════════════
  //  Firestore 리스너
  // ═══════════════════════════════════════════

  bool _firstSnapshot = true;

  void _startListening() {
    _stopListening();
    _firstSnapshot = true;
    _log('Firestore 리스너 시작: $_iotDocPath');

    _firestoreSub = FirebaseFirestore.instance
        .doc(_iotDocPath)
        .snapshots()
        .listen(
          _onSnapshot,
          onError: (e) {
            _log('스트림 에러: $e — 5초 후 재연결');
            Future.delayed(const Duration(seconds: 5), () {
              if (_enabled) _startListening();
            });
          },
        );
  }

  void _stopListening() {
    _firestoreSub?.cancel();
    _firestoreSub = null;
  }

  void _onSnapshot(DocumentSnapshot snapshot) {
    if (!snapshot.exists) {
      _log('iot 문서 없음 (센서 미연결)');
      return;
    }

    try {
      final data = Map<String, dynamic>.from(snapshot.data() as Map);
      final doorData = data['door'];
      if (doorData == null || doorData is! Map) {
        _log('door 필드 없음');
        return;
      }

      final doorMap = Map<String, dynamic>.from(doorData);
      final event = DoorEvent.fromMap(doorMap);

      _processEvent(event);
    } catch (e) {
      _log('스냅샷 파싱 에러: $e');
    }
  }

  // ═══════════════════════════════════════════
  //  이벤트 처리 (디바운스 + 상태 판단)
  // ═══════════════════════════════════════════

  void _processEvent(DoorEvent event) {
    // 첫 스냅샷은 현재 상태 동기화만 (이벤트 발행 안 함)
    if (_firstSnapshot) {
      _firstSnapshot = false;
      _lastDoorState = event.type;
      _lastEventTime = event.timestamp;
      _log('초기 상태 동기화: ${event.type.name}');
      return;
    }

    // 같은 상태 무시
    if (event.type == _lastDoorState && event.type != DoorState.unknown) {
      return;
    }

    // 디바운스: 이전 이벤트와 너무 가까우면 무시
    if (_lastEventTime != null) {
      final gap = event.timestamp.difference(_lastEventTime!);
      if (gap.inSeconds < _debounceSeconds) {
        _log('디바운스: ${gap.inSeconds}s < ${_debounceSeconds}s, 무시');
        return;
      }
    }

    final prev = _lastDoorState;
    _lastDoorState = event.type;
    _lastEventTime = event.timestamp;

    _log('상태 변경: ${prev.name} → ${event.type.name} (${event.sensorId})');

    // 스트림으로 이벤트 발행
    _eventController.add(event);



    // DayState 기반 텔레그램 알림
    _notifyByContext(event);
  }

  // ═══════════════════════════════════════════
  //  DayState 연동 알림
  // ═══════════════════════════════════════════

  void _notifyByContext(DoorEvent event) {
    // 방문 센서: 텔레그램 알림 비활성 (기상 감지는 SensorWakeDetector가 처리)
    final dayState = DayService().state;
    _log('문 ${event.type.name} — 알림 생략 (state=${dayState.name})');
  }



  // ═══════════════════════════════════════════
  //  수동 테스트용 (센서 없을 때 시뮬레이션)
  // ═══════════════════════════════════════════

  /// Firestore에 테스트 이벤트 기록 (센서 시뮬레이션)
  Future<void> simulateEvent(DoorState state, {String sensorId = 'front_door'}) async {
    _log('시뮬레이션: ${state.name}');
    try {
      await FirebaseFirestore.instance.doc(_iotDocPath).set({
        'door': {
          'state': state.name,
          'lastChanged': FieldValue.serverTimestamp(),
          'sensorId': sensorId,
        },
      }, SetOptions(merge: true));
    } catch (e) {
      _log('시뮬레이션 에러: $e');
    }
  }

  /// 테스트용: 디바운스/중복체크 우회하여 직접 이벤트 발행
  void emitTestEvent(DoorState state) {
    _log('테스트 직접 발행: ${state.name}');
    final event = DoorEvent(
      type: state,
      timestamp: DateTime.now(),
      sensorId: 'test',
    );
    _lastDoorState = state;
    _lastEventTime = event.timestamp;
    _eventController.add(event);
  }

  // ═══════════════════════════════════════════
  //  정리
  // ═══════════════════════════════════════════

  @override
  void dispose() {
    _stopListening();
    _eventController.close();
    super.dispose();
  }
}
