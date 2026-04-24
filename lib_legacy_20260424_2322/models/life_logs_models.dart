// ═══════════════════════════════════════════════════
// LIFE_LOGS — HB 가 Firestore 에 기입, 앱은 읽기만
// 경로: users/cheonhong/life_logs/{yyyy-MM-dd}
// 권위본: memory/project_app_integration.md (2026-04-24)
// ═══════════════════════════════════════════════════

class LifeLogEntry {
  final String time;
  final String? note;

  LifeLogEntry({required this.time, this.note});

  factory LifeLogEntry.fromMap(Map<String, dynamic> m) => LifeLogEntry(
        time: m['time']?.toString() ?? '',
        note: m['note']?.toString(),
      );
}

class MealEntry {
  final String time;
  final String menu;
  final String? note;

  MealEntry({required this.time, required this.menu, this.note});

  factory MealEntry.fromMap(Map<String, dynamic> m) => MealEntry(
        time: m['time']?.toString() ?? '',
        menu: m['menu']?.toString() ?? '',
        note: m['note']?.toString(),
      );
}

class BowelEntry {
  final String time;
  final String status;

  BowelEntry({required this.time, required this.status});

  factory BowelEntry.fromMap(Map<String, dynamic> m) => BowelEntry(
        time: m['time']?.toString() ?? '',
        status: m['status']?.toString() ?? '',
      );
}

class StudyEntry {
  final String time;
  final String subject;
  final int? problems;
  final String? note;

  StudyEntry({required this.time, required this.subject, this.problems, this.note});

  factory StudyEntry.fromMap(Map<String, dynamic> m) => StudyEntry(
        time: m['time']?.toString() ?? '',
        subject: m['subject']?.toString() ?? '',
        problems: m['problems'] is int ? m['problems'] as int : int.tryParse('${m['problems'] ?? ''}'),
        note: m['note']?.toString(),
      );
}

class PsychRecord {
  final String time;
  final String code;

  PsychRecord({required this.time, required this.code});

  factory PsychRecord.fromMap(Map<String, dynamic> m) => PsychRecord(
        time: m['time']?.toString() ?? '',
        code: m['code']?.toString() ?? '',
      );
}

class LifeLogPsych {
  final List<PsychRecord> masturbation;
  final List<PsychRecord> porn;
  final int? cravingLol;
  final String? mood;

  LifeLogPsych({
    this.masturbation = const [],
    this.porn = const [],
    this.cravingLol,
    this.mood,
  });

  factory LifeLogPsych.fromMap(Map<String, dynamic> m) {
    List<PsychRecord> parse(dynamic v) {
      if (v is! List) return const [];
      return v.whereType<Map>().map((e) => PsychRecord.fromMap(Map<String, dynamic>.from(e))).toList();
    }

    final cl = m['cravingLol'];
    return LifeLogPsych(
      masturbation: parse(m['masturbation']),
      porn: parse(m['porn']),
      cravingLol: cl is int ? cl : int.tryParse('${cl ?? ''}'),
      mood: m['mood']?.toString(),
    );
  }
}

class LifeLog {
  final String date;
  final LifeLogEntry? wake;
  final LifeLogEntry? sleep;
  final List<MealEntry> meals;
  final List<BowelEntry> bowel;
  final List<StudyEntry> study;
  final List<LifeLogEntry> outing;
  final List<LifeLogEntry> hydration;
  final LifeLogPsych psych;
  final Map<String, dynamic> raw;

  LifeLog({
    required this.date,
    this.wake,
    this.sleep,
    this.meals = const [],
    this.bowel = const [],
    this.study = const [],
    this.outing = const [],
    this.hydration = const [],
    LifeLogPsych? psych,
    this.raw = const {},
  }) : psych = psych ?? LifeLogPsych();

  factory LifeLog.fromMap(String date, Map<String, dynamic> m) {
    List<T> parseList<T>(dynamic v, T Function(Map<String, dynamic>) f) {
      if (v is! List) return const [];
      return v.whereType<Map>().map((e) => f(Map<String, dynamic>.from(e))).toList();
    }

    LifeLogEntry? parseEntry(dynamic v) {
      if (v is! Map) return null;
      return LifeLogEntry.fromMap(Map<String, dynamic>.from(v));
    }

    return LifeLog(
      date: date,
      wake: parseEntry(m['wake']),
      sleep: parseEntry(m['sleep']),
      meals: parseList(m['meals'], MealEntry.fromMap),
      bowel: parseList(m['bowel'], BowelEntry.fromMap),
      study: parseList(m['study'], StudyEntry.fromMap),
      outing: parseList(m['outing'], LifeLogEntry.fromMap),
      hydration: parseList(m['hydration'], LifeLogEntry.fromMap),
      psych: m['psych'] is Map
          ? LifeLogPsych.fromMap(Map<String, dynamic>.from(m['psych']))
          : LifeLogPsych(),
      raw: m,
    );
  }

  bool get isEmpty =>
      wake == null &&
      sleep == null &&
      meals.isEmpty &&
      bowel.isEmpty &&
      study.isEmpty &&
      outing.isEmpty &&
      hydration.isEmpty &&
      psych.masturbation.isEmpty &&
      psych.porn.isEmpty &&
      psych.cravingLol == null &&
      (psych.mood == null || psych.mood!.isEmpty);

  int get totalStudyProblems =>
      study.fold(0, (sum, e) => sum + (e.problems ?? 0));
}
