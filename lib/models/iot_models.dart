/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — IoT 데이터 모델
/// 도어 센서 및 향후 IoT 기기 모델
/// ═══════════════════════════════════════════════════════════

import 'package:cloud_firestore/cloud_firestore.dart';

// ─── 도어 상태 ───
enum DoorState {
  open,
  closed,
  unknown,
}

// ─── 도어 이벤트 ───
class DoorEvent {
  final DoorState type;
  final DateTime timestamp;
  final String sensorId;

  DoorEvent({
    required this.type,
    required this.timestamp,
    required this.sensorId,
  });

  factory DoorEvent.fromMap(Map<String, dynamic> map) {
    final stateStr = map['state'] as String? ?? 'unknown';
    final DoorState type;
    switch (stateStr) {
      case 'open':
        type = DoorState.open;
        break;
      case 'closed':
        type = DoorState.closed;
        break;
      default:
        type = DoorState.unknown;
    }

    DateTime ts;
    final raw = map['lastChanged'];
    if (raw is Timestamp) {
      ts = raw.toDate();
    } else if (raw is int) {
      ts = DateTime.fromMillisecondsSinceEpoch(raw);
    } else {
      ts = DateTime.now();
    }

    return DoorEvent(
      type: type,
      timestamp: ts,
      sensorId: map['sensorId'] as String? ?? 'unknown',
    );
  }

  Map<String, dynamic> toMap() => {
    'state': type.name,
    'lastChanged': Timestamp.fromDate(timestamp),
    'sensorId': sensorId,
  };

  @override
  String toString() => 'DoorEvent(${type.name}, $sensorId, $timestamp)';
}

// ─── IoT 기기 상태 (향후 확장용) ───
class IoTDeviceStatus {
  final String deviceId;
  final String deviceType; // 'door', 'motion', 'temperature' 등
  final bool online;
  final DateTime lastSeen;

  IoTDeviceStatus({
    required this.deviceId,
    required this.deviceType,
    required this.online,
    required this.lastSeen,
  });

  factory IoTDeviceStatus.fromMap(Map<String, dynamic> map) {
    DateTime lastSeen;
    final raw = map['lastSeen'];
    if (raw is Timestamp) {
      lastSeen = raw.toDate();
    } else if (raw is int) {
      lastSeen = DateTime.fromMillisecondsSinceEpoch(raw);
    } else {
      lastSeen = DateTime.now();
    }

    return IoTDeviceStatus(
      deviceId: map['deviceId'] as String? ?? '',
      deviceType: map['deviceType'] as String? ?? 'unknown',
      online: map['online'] as bool? ?? false,
      lastSeen: lastSeen,
    );
  }

  Map<String, dynamic> toMap() => {
    'deviceId': deviceId,
    'deviceType': deviceType,
    'online': online,
    'lastSeen': Timestamp.fromDate(lastSeen),
  };
}
