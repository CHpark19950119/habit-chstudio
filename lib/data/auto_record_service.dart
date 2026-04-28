// AutoRecordService — life_logs 자동 기록.
// cheonhong:// deep link 또는 NotificationListener trigger 시 호출.
// 사용자 지시 (2026-04-28 10:54): "앱 전부 이관 · 자동 기록".
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../app/app.dart';
import 'routine_service.dart';

class AutoRecordService {
  AutoRecordService._();
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _ref(String date) =>
      _db.doc('users/$kUid/life_logs/$date');

  static String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());
  static String _hhmm() => DateFormat('HH:mm').format(DateTime.now());

  // ─── wake ───
  // 한 번 호출 = 그날 첫 기상 등재 (이미 있으면 덮지 않음). routine.morning_routine 자동 체크.
  static Future<void> recordWake({String? note}) async {
    final date = _today();
    final ref = _ref(date);
    final snap = await ref.get();
    final existing = (snap.data() ?? const {})['wake'];
    if (existing is Map && existing['time'] is String) return; // 이미 기록됨
    await ref.set({
      'wake': {'time': _hhmm(), if (note != null) 'note': note},
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    await RoutineService.markDone('morning_routine', note: 'wake');
  }

  // ─── sleep ───
  // 호출 시점 시각 = 취침 시각. 다시 호출하면 덮어씀 (실제 취침 정정 가능). routine.wind_down 자동 체크.
  static Future<void> recordSleep({String? note}) async {
    await _ref(_today()).set({
      'sleep': {'time': _hhmm(), if (note != null) 'note': note},
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
    await RoutineService.markDone('wind_down', note: 'sleep');
  }

  // ─── meal toggle ───
  // 마지막 meal entry 의 end 가 null 이면 = 식사 중, end 채움 (식사 종료).
  // 아니면 새 entry 시작. 17시 이후 시작 = routine.dinner_review 자동 체크.
  static Future<void> toggleMeal() async {
    final ref = _ref(_today());
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final meals = List<Map<String, dynamic>>.from(
        (data['meals'] as List?)?.cast<Map>().map((m) => Map<String, dynamic>.from(m)) ?? const []);

    final now = _hhmm();
    final isStart = !(meals.isNotEmpty && meals.last['end'] == null);
    if (meals.isNotEmpty && meals.last['end'] == null) {
      meals.last['end'] = now;
    } else {
      meals.add({'start': now});
    }
    await ref.set({
      'meals': meals,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    if (isStart) {
      final hour = DateTime.now().hour;
      if (hour >= 17 && hour < 22) {
        await RoutineService.markDone('dinner_review', note: 'meal');
      }
    }
  }

  // ─── outing toggle ───
  // 마지막 outing entry 의 returnHome 가 null 이면 = 외출 중, returnHome 채움 (귀가).
  // 아니면 새 entry (외출 시작). 06-12시 시작 = routine.walk 자동 체크.
  static Future<void> toggleOuting({String? destination, String? mode}) async {
    final ref = _ref(_today());
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final outing = List<Map<String, dynamic>>.from(
        (data['outing'] as List?)?.cast<Map>().map((m) => Map<String, dynamic>.from(m)) ?? const []);

    final now = _hhmm();
    final isStart = !(outing.isNotEmpty && outing.last['returnHome'] == null);
    if (outing.isNotEmpty && outing.last['returnHome'] == null) {
      outing.last['returnHome'] = now;
    } else {
      outing.add({
        'time': now,
        if (destination != null) 'destination': destination,
        if (mode != null) 'mode': mode,
      });
    }
    await ref.set({
      'outing': outing,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    if (isStart) {
      final hour = DateTime.now().hour;
      if (hour >= 6 && hour < 12) {
        await RoutineService.markDone('walk', note: 'outing');
      }
    }
  }

  // ─── focus / 이벤트 ───
  // 단순 events 배열에 append. tag=focus + 11-17시 = routine.workbook/study, 22 이후 = wind_down.
  static Future<void> appendEvent({required String tag, String? note}) async {
    final ref = _ref(_today());
    final snap = await ref.get();
    final data = snap.data() ?? {};
    final events = List<Map<String, dynamic>>.from(
        (data['events'] as List?)?.cast<Map>().map((m) => Map<String, dynamic>.from(m)) ?? const []);
    events.add({'time': _hhmm(), 'tag': tag, if (note != null) 'note': note});
    await ref.set({
      'events': events,
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));

    final hour = DateTime.now().hour;
    if (tag == 'focus' || tag == 'study_start') {
      if (hour >= 11 && hour < 17) {
        await RoutineService.markDone('study', note: 'focus');
      }
    }
  }

  // ─── sleep + wind_down ───
  static Future<void> markWindDown() async {
    final hour = DateTime.now().hour;
    if (hour >= 22 || hour < 4) {
      await RoutineService.markDone('wind_down', note: 'pre-sleep');
    }
  }

  // ─── 앱 실행 자동 wake 후보 ───
  // 07-15시 사이 앱 첫 실행 시 wake 자동 등재 (이미 기록되어있으면 skip).
  static Future<void> autoWakeCandidate() async {
    final hour = DateTime.now().hour;
    if (hour < 7 || hour >= 15) return;
    await recordWake(note: '앱 실행 자동 후보');
  }
}
