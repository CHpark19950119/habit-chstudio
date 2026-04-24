/// CHEONHONG STUDIO — Firestore 데이터 모델

// ─── 시간 기록 (기상/외출/귀가/식사/취침) ───
class TimeRecord {
  final String date;
  final String? wake;
  final String? outing;       // 외출
  final String? returnHome;   // 귀가
  final String? arrival;      // GPS 도착 감지
  final String? bedTime;      // 수면시간
  final String? mealStart;   // [레거시] 단일 식사 — 하위호환용
  final String? mealEnd;     // [레거시] 단일 식사 — 하위호환용
  final List<MealEntry> meals; // 다회 식사 기록
  final bool noOuting; // 외출 안하는 날 (재택)

  TimeRecord({
    required this.date,
    this.wake,
    this.outing,
    this.returnHome,
    this.arrival,
    this.bedTime,
    this.mealStart,
    this.mealEnd,
    List<MealEntry>? meals,
    this.noOuting = false,
  }) : meals = meals ?? [];

  factory TimeRecord.fromMap(String date, Map<String, dynamic> map) {
    // 레거시 단일 필드 읽기
    final legacyStart = map['mealStart'] as String?;
    final legacyEnd = map['mealEnd'] as String?;

    // 다회 meals 배열 읽기
    List<MealEntry> mealList = [];
    if (map['meals'] is List) {
      mealList = (map['meals'] as List)
          .map((e) => MealEntry.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList();
    }

    // 레거시→신규 마이그레이션: meals가 비어있고 레거시 필드 있으면 변환
    if (mealList.isEmpty && legacyStart != null) {
      mealList = [MealEntry(start: legacyStart, end: legacyEnd)];
    }

    return TimeRecord(
      date: date,
      wake: map['wake'] as String?,
      outing: map['outing'] as String?,
      returnHome: map['returnHome'] as String?,
      arrival: map['arrival'] as String?,
      bedTime: map['bedTime'] as String?,
      mealStart: legacyStart,
      mealEnd: legacyEnd,
      meals: mealList,
      noOuting: map['noOuting'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{};
    if (wake != null) m['wake'] = wake;
    if (outing != null) m['outing'] = outing;
    if (returnHome != null) m['returnHome'] = returnHome;
    if (arrival != null) m['arrival'] = arrival;
    if (bedTime != null) m['bedTime'] = bedTime;
    if (mealStart != null) m['mealStart'] = mealStart;
    if (mealEnd != null) m['mealEnd'] = mealEnd;
    if (meals.isNotEmpty) {
      m['meals'] = meals.map((e) => e.toMap()).toList();
    }
    if (noOuting) m['noOuting'] = true;
    return m;
  }

  /// 첫 번째 식사의 시작/종료 (레거시 호환)
  String? get firstMealStart => meals.isNotEmpty ? meals.first.start : mealStart;
  String? get firstMealEnd => meals.isNotEmpty ? meals.first.end : mealEnd;

  /// 진행 중인 식사 (end가 null)
  MealEntry? get activeMeal {
    try { return meals.firstWhere((m) => m.end == null); } catch (_) { return null; }
  }

  /// 총 식사시간 (분)
  int get totalMealMinutes => meals.fold(0, (sum, m) => sum + (m.durationMin ?? 0));

  /// 식사시간 (분) — 레거시 호환
  int? get mealMinutes {
    if (meals.isNotEmpty) return totalMealMinutes > 0 ? totalMealMinutes : null;
    if (mealStart == null || mealEnd == null) return null;
    return _timeDiffMin(mealStart!, mealEnd!);
  }

  String? get mealFormatted {
    final m = mealMinutes;
    if (m == null) return null;
    if (m >= 60) return '${m ~/ 60}시간 ${m % 60}분';
    return '$m분';
  }

  /// meals 보존 복사 헬퍼
  TimeRecord copyWith({
    String? wake,
    String? outing, String? returnHome, String? arrival,
    String? bedTime, String? mealStart, String? mealEnd,
    List<MealEntry>? meals, bool? noOuting,
    bool clearWake = false,
    bool clearOuting = false, bool clearReturnHome = false,
    bool clearBedTime = false,
  }) {
    return TimeRecord(
      date: date,
      wake: clearWake ? null : (wake ?? this.wake),
      outing: clearOuting ? null : (outing ?? this.outing),
      returnHome: clearReturnHome ? null : (returnHome ?? this.returnHome),
      arrival: arrival ?? this.arrival,
      bedTime: clearBedTime ? null : (bedTime ?? this.bedTime),
      mealStart: mealStart ?? this.mealStart,
      mealEnd: mealEnd ?? this.mealEnd,
      meals: meals ?? this.meals,
      noOuting: noOuting ?? this.noOuting,
    );
  }

  // ═══════════════════════════════════════════
  //  TimeRecord.validate() — 데이터 무결성 검증
  // ═══════════════════════════════════════════

  /// HH:mm 포맷 검증
  static bool _isValidTime(String? t) {
    if (t == null) return true; // null은 OK
    final re = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$');
    return re.hasMatch(t);
  }

  /// HH:mm → 분 변환 (null-safe)
  static int? _toMinutes(String? t) {
    if (t == null) return null;
    if (!_isValidTime(t)) return null;
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  /// 유효성 검증 결과
  static TimeRecordValidation validate(TimeRecord tr) {
    final errors = <String>[];

    // 1. HH:mm 포맷 체크
    if (!_isValidTime(tr.wake)) errors.add('wake 포맷 이상: ${tr.wake}');
    if (!_isValidTime(tr.outing)) errors.add('outing 포맷 이상: ${tr.outing}');
    if (!_isValidTime(tr.returnHome)) errors.add('returnHome 포맷 이상: ${tr.returnHome}');
    if (!_isValidTime(tr.bedTime)) errors.add('bedTime 포맷 이상: ${tr.bedTime}');

    // 2. 논리 순서 체크 (자정 넘김 감안)
    final wakeM = _toMinutes(tr.wake);
    final bedTimeM = _toMinutes(tr.bedTime);
    final outingM = _toMinutes(tr.outing);
    final returnM = _toMinutes(tr.returnHome);

    if (outingM != null && returnM != null) {
      int diff = returnM - outingM;
      if (diff < 0) diff += 1440;
      if (diff > 720) errors.add('returnHome < outing');
    }
    if (wakeM != null && outingM != null) {
      int diff = outingM - wakeM;
      if (diff < 0) diff += 1440;
      if (diff > 720) errors.add('outing < wake');
    }
    if (wakeM != null && bedTimeM != null) {
      int diff = bedTimeM - wakeM;
      if (diff < 0) diff += 1440;
      if (diff > 720) errors.add('bedTime < wake');
    }

    return TimeRecordValidation(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }

  /// 총 외출시간 (분): 귀가 - 외출
  int? get outingMinutes {
    if (outing == null || returnHome == null) return null;
    return _timeDiffMin(outing!, returnHome!);
  }

  /// 외출시간 포맷 (예: "2h 30m")
  String? get outingFormatted {
    final min = outingMinutes;
    if (min == null || min <= 0) return null;
    final h = min ~/ 60;
    final m = min % 60;
    if (h > 0 && m > 0) return '${h}h ${m}m';
    if (h > 0) return '${h}h';
    return '${m}m';
  }

  static int? _timeDiffMin(String from, String to) {
    try {
      final fp = from.split(':');
      final tp = to.split(':');
      final fm = int.parse(fp[0]) * 60 + int.parse(fp[1]);
      final tm = int.parse(tp[0]) * 60 + int.parse(tp[1]);
      int diff = tm - fm;
      // ★ FIX: 자정 넘김 처리 (예: 23:00→00:30 = 90분)
      if (diff < 0) diff += 1440;
      // 12시간 이상이면 비정상 (역전된 기록)
      return diff <= 720 ? diff : null;
    } catch (_) {
      return null;
    }
  }
}

/// TimeRecord 유효성 검증 결과
class TimeRecordValidation {
  final bool isValid;
  final List<String> errors;
  const TimeRecordValidation({required this.isValid, required this.errors});
  @override
  String toString() => isValid ? 'OK' : 'INVALID: ${errors.join(', ')}';
}

// ─── 식사 기록 엔트리 (v9: 다회 식사) ───
class MealEntry {
  final String start;     // HH:mm
  final String? end;      // HH:mm (null이면 식사 중)
  final String? type;     // breakfast, lunch, dinner, snack

  MealEntry({required this.start, this.end, this.type});

  factory MealEntry.fromMap(Map<String, dynamic> m) => MealEntry(
    start: m['start'] ?? '',
    end: m['end'] as String?,
    type: m['type'] as String?,
  );

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{'start': start};
    if (end != null) m['end'] = end;
    if (type != null) m['type'] = type;
    return m;
  }

  int? get durationMin {
    if (end == null) return null;
    try {
      final sp = start.split(':');
      final ep = end!.split(':');
      final sm = int.parse(sp[0]) * 60 + int.parse(sp[1]);
      final em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
      int diff = em - sm;
      if (diff < 0) diff += 1440;
      return diff <= 720 ? diff : null;
    } catch (_) { return null; }
  }

  String? get durationFormatted {
    final m = durationMin;
    if (m == null) return null;
    if (m >= 60) return '${m ~/ 60}시간 ${m % 60}분';
    return '$m분';
  }

  MealEntry withEnd(String endTime) => MealEntry(start: start, end: endTime, type: type);
}

// ─── 위치 기록 ───
class LocationRecord {
  final String id;
  final String date;
  final String timestamp;
  final double latitude;
  final double longitude;
  final String? placeName;
  final String? placeId;
  final String? placeCategory;
  final String? wifiSsid;
  final int durationMinutes;

  LocationRecord({
    required this.id,
    required this.date,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.placeName,
    this.placeId,
    this.placeCategory,
    this.wifiSsid,
    this.durationMinutes = 0,
  });

  factory LocationRecord.fromMap(Map<String, dynamic> map) {
    return LocationRecord(
      id: map['id'] ?? '',
      date: map['date'] ?? '',
      timestamp: map['timestamp'] ?? '',
      latitude: (map['latitude'] ?? 0).toDouble(),
      longitude: (map['longitude'] ?? 0).toDouble(),
      placeName: map['placeName'],
      placeId: map['placeId'],
      placeCategory: map['placeCategory'],
      wifiSsid: map['wifiSsid'],
      durationMinutes: map['durationMinutes'] ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'timestamp': timestamp,
        'latitude': latitude,
        'longitude': longitude,
        'placeName': placeName,
        'placeId': placeId,
        'placeCategory': placeCategory,
        'wifiSsid': wifiSsid,
        'durationMinutes': durationMinutes,
      };
}

// ─── 행동 타임라인 ───
class BehaviorTimelineEntry {
  final String id;
  final String date;
  final String startTime;
  final String endTime;
  final String type;
  final String label;
  final String? emoji;
  final String? placeName;
  final int durationMinutes;
  final Map<String, dynamic>? meta;

  BehaviorTimelineEntry({
    required this.id,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.type,
    required this.label,
    this.emoji,
    this.placeName,
    required this.durationMinutes,
    this.meta,
  });

  factory BehaviorTimelineEntry.fromMap(Map<String, dynamic> map) {
    return BehaviorTimelineEntry(
      id: map['id'] ?? '',
      date: map['date'] ?? '',
      startTime: map['startTime'] ?? '',
      endTime: map['endTime'] ?? '',
      type: map['type'] ?? '',
      label: map['label'] ?? '',
      emoji: map['emoji'],
      placeName: map['placeName'],
      durationMinutes: map['durationMinutes'] ?? 0,
      meta: map['meta'] as Map<String, dynamic>?,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'date': date,
        'startTime': startTime,
        'endTime': endTime,
        'type': type,
        'label': label,
        'emoji': emoji,
        'placeName': placeName,
        'durationMinutes': durationMinutes,
        'meta': meta,
      };
}

// ══════════════════════════════════════════
//  액션 타입 (wake/outing/meal/sleep)
// ══════════════════════════════════════════

enum ActionType { wake, outing, sleep, meal }

// ══════════════════════════════════════════
//  날씨 데이터 (#44)
// ══════════════════════════════════════════

class WeatherData {
  final double temp;
  final double feelsLike;
  final double tempMin;
  final double tempMax;
  final int humidity;
  final String description;
  final String icon;
  final String main;
  final double windSpeed;
  final DateTime fetchedAt;

  WeatherData({
    required this.temp,
    required this.feelsLike,
    required this.tempMin,
    required this.tempMax,
    required this.humidity,
    required this.description,
    required this.icon,
    required this.main,
    required this.windSpeed,
    required this.fetchedAt,
  });

  factory WeatherData.fromJson(Map<String, dynamic> json) {
    final weather = (json['weather'] as List).first;
    final main = json['main'] as Map<String, dynamic>;
    final wind = json['wind'] as Map<String, dynamic>;
    return WeatherData(
      temp: (main['temp'] as num).toDouble(),
      feelsLike: (main['feels_like'] as num).toDouble(),
      tempMin: (main['temp_min'] as num).toDouble(),
      tempMax: (main['temp_max'] as num).toDouble(),
      humidity: main['humidity'] as int,
      description: weather['description'] as String,
      icon: weather['icon'] as String,
      main: weather['main'] as String,
      windSpeed: (wind['speed'] as num).toDouble(),
      fetchedAt: DateTime.now(),
    );
  }

  String get emoji {
    switch (main.toLowerCase()) {
      case 'clear': return '☀️';
      case 'clouds': return '☁️';
      case 'rain': case 'drizzle': return '🌧️';
      case 'thunderstorm': return '⛈️';
      case 'snow': return '❄️';
      case 'mist': case 'fog': case 'haze': return '🌫️';
      default: return '🌤️';
    }
  }

  String get briefingSummary {
    final t = temp.round();
    final fl = feelsLike.round();
    final hi = tempMax.round();
    final lo = tempMin.round();
    return '현재 $t도, 체감 $fl도. 최고 $hi도 최저 $lo도. $description. 습도 $humidity%.';
  }
}
// ═══════════════════════════════════════════════════════════
// F2: 메모 모델
// ═══════════════════════════════════════════════════════════

class Memo {
  final String id;
  final String content;
  final DateTime createdAt;
  final DateTime? reminderAt;
  final bool pinned;
  final bool completed;
  final String? category; // study, daily, important

  Memo({
    required this.id,
    required this.content,
    required this.createdAt,
    this.reminderAt,
    this.pinned = false,
    this.completed = false,
    this.category,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'content': content,
    'createdAt': createdAt.toIso8601String(),
    if (reminderAt != null) 'reminderAt': reminderAt!.toIso8601String(),
    'pinned': pinned,
    'completed': completed,
    if (category != null) 'category': category,
  };

  factory Memo.fromMap(Map<String, dynamic> m) => Memo(
    id: m['id'] ?? '',
    content: m['content'] ?? '',
    createdAt: DateTime.tryParse(m['createdAt'] ?? '') ?? DateTime.now(),
    reminderAt: m['reminderAt'] != null ? DateTime.tryParse(m['reminderAt']) : null,
    pinned: m['pinned'] ?? false,
    completed: m['completed'] ?? false,
    category: m['category'] as String?,
  );

  Memo copyWith({
    String? content,
    DateTime? reminderAt,
    bool? pinned,
    bool? completed,
    String? category,
    bool clearReminder = false,
  }) => Memo(
    id: id,
    content: content ?? this.content,
    createdAt: createdAt,
    reminderAt: clearReminder ? null : (reminderAt ?? this.reminderAt),
    pinned: pinned ?? this.pinned,
    completed: completed ?? this.completed,
    category: category ?? this.category,
  );

  static String categoryEmoji(String? cat) {
    switch (cat) {
      case 'study': return '📚';
      case 'important': return '⚡';
      case 'daily': return '📝';
      default: return '💡';
    }
  }

  static String categoryLabel(String? cat) {
    switch (cat) {
      case 'study': return '학습';
      case 'important': return '중요';
      case 'daily': return '일상';
      default: return '기타';
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Phase C 제거: ProgressGoal/ProgressLog/CompletionRecord → cheonhong_study 로 이관
// ═══════════════════════════════════════════════════════════

// ═══════════════════════════════════════════
//  데일리 일기 (DailyDiary)
// ═══════════════════════════════════════════

class DailyDiary {
  final String date;
  final String content;
  final String? mood;
  final String updatedAt;

  DailyDiary({
    required this.date,
    required this.content,
    this.mood,
    String? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().toIso8601String();

  factory DailyDiary.fromMap(Map<String, dynamic> m) => DailyDiary(
    date: m['date'] ?? '',
    content: m['content'] ?? '',
    mood: m['mood'] as String?,
    updatedAt: m['updatedAt'] ?? '',
  );

  Map<String, dynamic> toMap() => {
    'date': date,
    'content': content,
    if (mood != null) 'mood': mood,
    'updatedAt': updatedAt,
  };
}
