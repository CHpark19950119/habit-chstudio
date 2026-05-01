import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../app/app.dart';

class RoutineStep {
  final String id;
  final String label;
  final String icon;
  final bool done;
  final String? doneAt;
  final String? note;

  const RoutineStep({
    required this.id,
    required this.label,
    this.icon = '',
    this.done = false,
    this.doneAt,
    this.note,
  });

  factory RoutineStep.fromMap(Map m) => RoutineStep(
        id: m['id']?.toString() ?? '',
        label: m['label']?.toString() ?? '',
        icon: m['icon']?.toString() ?? '',
        done: m['done'] == true,
        doneAt: m['doneAt']?.toString(),
        note: m['note']?.toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'label': label,
        if (icon.isNotEmpty) 'icon': icon,
        'done': done,
        if (doneAt != null) 'doneAt': doneAt,
        if (note != null) 'note': note,
      };

  RoutineStep copyWith({bool? done, String? doneAt, String? note}) => RoutineStep(
        id: id,
        label: label,
        icon: icon,
        done: done ?? this.done,
        doneAt: doneAt ?? this.doneAt,
        note: note ?? this.note,
      );
}

/// 블록 (시간대 그루핑) · 사용자 지시 "순서 개념 유지" (2026-04-25 00:19)
enum RoutineBlock { morning, afternoon, evening, night }

extension RoutineBlockX on RoutineBlock {
  String get label => switch (this) {
        RoutineBlock.morning => '아침',
        RoutineBlock.afternoon => '낮',
        RoutineBlock.evening => '저녁',
        RoutineBlock.night => '밤',
      };
  String get range => switch (this) {
        RoutineBlock.morning => '06~11시',
        RoutineBlock.afternoon => '11~17시',
        RoutineBlock.evening => '17~22시',
        RoutineBlock.night => '22시 이후',
      };
}

class RoutineStepWithBlock extends RoutineStep {
  final RoutineBlock block;
  const RoutineStepWithBlock({
    required super.id,
    required super.label,
    required this.block,
    super.icon = '',
    super.done = false,
    super.doneAt,
    super.note,
  });
}

/// 기본 일상 루틴 — 일상 단계 (공부 step 제거 · 사용자 명시 2026-05-01 14:32 도메인 분리)
/// 학업 routine = ST 앱 담당. DAILY = 수면·식사·산책·routine 만.
List<RoutineStep> defaultRoutine() => const [
      RoutineStepWithBlock(id: 'morning_routine', label: '기상 · 샤워 · 아침', icon: '🌅', block: RoutineBlock.morning),
      RoutineStepWithBlock(id: 'walk', label: '산책 · 광노출', icon: '🚶', block: RoutineBlock.morning),
      RoutineStepWithBlock(id: 'lunch', label: '점심', icon: '🍱', block: RoutineBlock.afternoon),
      RoutineStepWithBlock(id: 'afternoon_break', label: '오후 휴식', icon: '☕', block: RoutineBlock.afternoon),
      RoutineStepWithBlock(id: 'dinner', label: '저녁 식사', icon: '🍲', block: RoutineBlock.evening),
      RoutineStepWithBlock(id: 'evening_walk', label: '저녁 산책', icon: '🌆', block: RoutineBlock.evening),
      RoutineStepWithBlock(id: 'wind_down', label: '취침 준비 · 화면 OFF', icon: '🛏️', block: RoutineBlock.night),
    ];

/// 현재 시각 기준 활성 블록
RoutineBlock currentBlock() {
  final h = DateTime.now().hour;
  if (h >= 6 && h < 11) return RoutineBlock.morning;
  if (h >= 11 && h < 17) return RoutineBlock.afternoon;
  if (h >= 17 && h < 22) return RoutineBlock.evening;
  return RoutineBlock.night;
}

class RoutineService {
  RoutineService._();
  static final _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _ref(String date) =>
      _db.doc('users/$kUid/routine/$date');

  static String today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  static Stream<List<RoutineStep>> todayStream() {
    return _ref(today()).snapshots().map((snap) {
      final data = snap.data();
      if (data == null || data['steps'] is! List) {
        return defaultRoutine();
      }
      final raw = (data['steps'] as List).whereType<Map>().toList();
      if (raw.isEmpty) return defaultRoutine();
      // id 매칭으로 defaultRoutine 의 block 정보 보존 + Firestore done 상태 머지
      final defaults = defaultRoutine();
      return defaults.map((d) {
        final saved = raw.firstWhere((m) => m['id'] == d.id, orElse: () => <String, dynamic>{});
        if (saved.isEmpty) return d;
        return RoutineStepWithBlock(
          id: d.id,
          label: d.label,
          icon: d.icon,
          block: (d as RoutineStepWithBlock).block,
          done: saved['done'] == true,
          doneAt: saved['doneAt']?.toString(),
          note: saved['note']?.toString(),
        );
      }).toList();
    });
  }

  /// toggle — 현 상태 반전 + doneAt 기록
  static Future<void> toggle(String id, List<RoutineStep> current) async {
    final now = DateFormat('HH:mm').format(DateTime.now());
    final updated = current.map((s) {
      if (s.id != id) return s;
      final d = !s.done;
      return s.copyWith(done: d, doneAt: d ? now : null);
    }).toList();
    await _ref(today()).set(
      {'steps': updated.map((s) => s.toMap()).toList(), 'updatedAt': DateTime.now().toIso8601String()},
      SetOptions(merge: true),
    );
  }

  /// 단일 step done=true 마킹 (HB AutoRecordService 자동 체크용 · 2026-04-28 14:10).
  /// 이미 done 이면 skip.
  static Future<void> markDone(String stepId, {String? note}) async {
    final ref = _ref(today());
    final snap = await ref.get();
    final now = DateFormat('HH:mm').format(DateTime.now());

    List<RoutineStep> current;
    if (snap.exists && snap.data()?['steps'] is List) {
      current = (snap.data()!['steps'] as List)
          .whereType<Map>()
          .map((m) => RoutineStep.fromMap(m))
          .toList();
    } else {
      current = defaultRoutine();
    }

    bool changed = false;
    final updated = current.map((s) {
      if (s.id != stepId || s.done) return s;
      changed = true;
      return s.copyWith(done: true, doneAt: now, note: note);
    }).toList();

    if (!changed) return;
    await ref.set({
      'date': today(),
      'steps': updated.map((s) => s.toMap()).toList(),
      'updatedAt': DateTime.now().toIso8601String(),
    }, SetOptions(merge: true));
  }

  /// 최초 생성 · 기본 루틴 seed
  static Future<void> seedIfMissing() async {
    final doc = await _ref(today()).get();
    if (doc.exists && (doc.data()?['steps'] is List)) return;
    await _ref(today()).set({
      'date': today(),
      'steps': defaultRoutine().map((s) => s.toMap()).toList(),
      'createdAt': DateTime.now().toIso8601String(),
    });
  }
}
