import 'dart:ui';

/// ═══════════════════════════════════════════════════════════
/// Roadmap Data Models v11 — 인생 로드맵
/// assets/roadmap/roadmap_data.json 로딩용
/// ═══════════════════════════════════════════════════════════

class RoadmapData {
  final RoadmapMeta meta;
  final List<TimelineRow> timeline;
  final List<HomeCard> homes;
  final List<Relationship> relationships;
  final List<InternetWoman> internetWomen;
  final DetailTransactions detailTransactions;
  final SexualData sexual;
  final PsychAnalysisData psychAnalysis;
  final ExamAnalysisData examAnalysis;
  final EconomyData economy;
  final List<GrowthQuote> growthQuotes;
  final NovelData novel;
  final TodoData todos;

  RoadmapData({
    required this.meta, required this.timeline,
    this.homes = const [], required this.relationships,
    this.internetWomen = const [],
    required this.detailTransactions,
    required this.sexual,
    required this.psychAnalysis, required this.examAnalysis,
    required this.economy,
    required this.growthQuotes, required this.novel,
    required this.todos,
  });

  factory RoadmapData.fromMap(Map<String, dynamic> m) => RoadmapData(
    meta: RoadmapMeta.fromMap(m['meta'] as Map<String, dynamic>),
    timeline: _parseList(m['timeline'], TimelineRow.fromMap),
    homes: _parseList(m['homes'], HomeCard.fromMap),
    relationships: _parseList(m['relationships'], Relationship.fromMap),
    internetWomen: _parseList(m['internetWomen'], InternetWoman.fromMap),
    detailTransactions: DetailTransactions.fromMap(
        Map<String, dynamic>.from((m['detailTransactions'] ?? {}) as Map)),
    sexual: SexualData.fromMap(Map<String, dynamic>.from((m['sexual'] ?? {}) as Map)),
    psychAnalysis: PsychAnalysisData.fromMap(Map<String, dynamic>.from((m['psychAnalysis'] ?? {}) as Map)),
    examAnalysis: ExamAnalysisData.fromMap(Map<String, dynamic>.from((m['examAnalysis'] ?? {}) as Map)),
    economy: EconomyData.fromMap(Map<String, dynamic>.from((m['economy'] ?? {}) as Map)),
    growthQuotes: _parseList(m['growthQuotes'], GrowthQuote.fromMap),
    novel: NovelData.fromMap(Map<String, dynamic>.from((m['novel'] ?? {}) as Map)),
    todos: TodoData.fromMap(Map<String, dynamic>.from((m['todos'] ?? {}) as Map)),
  );
}

List<T> _parseList<T>(dynamic list, T Function(Map<String, dynamic>) fromMap) {
  if (list == null) return [];
  return (list as List).map((e) => fromMap(Map<String, dynamic>.from(e as Map))).toList();
}

List<String> _strList(dynamic list) =>
    (list as List?)?.map((e) => e.toString()).toList() ?? [];

int _toInt(dynamic v) => v is int ? v : (v is double ? v.toInt() : int.tryParse('$v') ?? 0);

class RoadmapMeta {
  final String version;
  final String subtitle;
  final int totalTransactions;
  final String totalExpense;
  final int pcBangVisits;
  final String relationships;
  final String recordRange;
  final String lastModified;
  final String headerQuote;

  RoadmapMeta({
    required this.version, required this.subtitle,
    required this.totalTransactions, required this.totalExpense,
    required this.pcBangVisits, required this.relationships,
    required this.recordRange, required this.lastModified,
    this.headerQuote = '',
  });

  factory RoadmapMeta.fromMap(Map<String, dynamic> m) => RoadmapMeta(
    version: m['version'] ?? '',
    subtitle: m['subtitle'] ?? '',
    totalTransactions: _toInt(m['totalTransactions']),
    totalExpense: m['totalExpense'] ?? '',
    pcBangVisits: _toInt(m['pcBangVisits']),
    relationships: m['relationships'] ?? '',
    recordRange: m['recordRange'] ?? '',
    lastModified: m['lastModified'] ?? '',
    headerQuote: m['headerQuote'] ?? '',
  );
}

class TimelineRow {
  final String period;
  final String career;
  final String relationship;
  final String psychology;
  final List<String> tags;
  final String? tint;

  TimelineRow({required this.period, required this.career,
    required this.relationship, required this.psychology,
    required this.tags, this.tint});

  factory TimelineRow.fromMap(Map<String, dynamic> m) => TimelineRow(
    period: m['period'] ?? '',
    career: m['career'] ?? '',
    relationship: m['relationship'] ?? '',
    psychology: m['psychology'] ?? '',
    tags: _strList(m['tags']),
    tint: m['tint'],
  );
}

// ═══ V11 NEW: HomeCard (거주지 아카이브) ═══

class HomeCard {
  final String name;
  final String address;
  final String period;
  final String description;

  HomeCard({required this.name, this.address = '',
    required this.period, required this.description});

  factory HomeCard.fromMap(Map<String, dynamic> m) => HomeCard(
    name: m['name'] ?? '',
    address: m['address'] ?? '',
    period: m['period'] ?? '',
    description: m['description'] ?? '',
  );
}

// ═══ V11 NEW: InternetWoman (인터넷 여성들) ═══

class InternetWoman {
  final String name;
  final String subtitle;
  final String platform;
  final String nationality;
  final String period;
  final bool sexualContact;
  final String description;
  final String meaning;

  InternetWoman({required this.name, this.subtitle = '',
    this.platform = '', this.nationality = '',
    this.period = '', this.sexualContact = false,
    required this.description, this.meaning = ''});

  factory InternetWoman.fromMap(Map<String, dynamic> m) => InternetWoman(
    name: m['name'] ?? '',
    subtitle: m['subtitle'] ?? '',
    platform: m['platform'] ?? '',
    nationality: m['nationality'] ?? '',
    period: m['period'] ?? '',
    sexualContact: m['sexualContact'] ?? false,
    description: m['description'] ?? '',
    meaning: m['meaning'] ?? '',
  );
}

// ═══ V11 NEW: DetailTransactions (2017~18 전수) ═══

class DetailEntry {
  final String date;
  final String description;

  DetailEntry({required this.date, required this.description});

  factory DetailEntry.fromMap(Map<String, dynamic> m) => DetailEntry(
    date: m['date'] ?? '',
    description: m['description'] ?? '',
  );
}

class DetailTransactions {
  final List<DetailEntry> year2017;
  final List<DetailEntry> year2018;

  DetailTransactions({this.year2017 = const [], this.year2018 = const []});

  factory DetailTransactions.fromMap(Map<String, dynamic> m) => DetailTransactions(
    year2017: _parseList(m['year2017'], DetailEntry.fromMap),
    year2018: _parseList(m['year2018'], DetailEntry.fromMap),
  );
}

class Relationship {
  final int num;
  final String name;
  final Color color;
  final String init;
  final String period;
  final String subtitle;
  final List<String> details;

  Relationship({required this.num, required this.name, required this.color,
    required this.init, required this.period, required this.subtitle,
    required this.details});

  factory Relationship.fromMap(Map<String, dynamic> m) => Relationship(
    num: _toInt(m['num']),
    name: m['name'] ?? '',
    color: _parseColor(m['color']),
    init: m['init'] ?? '',
    period: m['period'] ?? '',
    subtitle: m['subtitle'] ?? '',
    details: _strList(m['details']),
  );
}

// ═══ Sexual Data (V9: simplified) ═══

class SexualPartnerRecord {
  final String partner;
  final String period;
  final String content;
  final Color? color;

  SexualPartnerRecord({required this.partner, this.period = '',
    required this.content, this.color});

  factory SexualPartnerRecord.fromMap(Map<String, dynamic> m) => SexualPartnerRecord(
    partner: m['partner'] ?? '',
    period: m['period'] ?? '',
    content: m['content'] ?? '',
    color: m['color'] != null ? _parseColor(m['color']) : null,
  );
}

class SexualPreference {
  final String label;
  final String body;

  SexualPreference({required this.label, required this.body});

  factory SexualPreference.fromMap(Map<String, dynamic> m) => SexualPreference(
    label: m['label'] ?? '',
    body: m['body'] ?? '',
  );
}

class SexualRecord {
  final String date;
  final String partner;
  final String place;
  final String detail;
  final String psych;

  SexualRecord({required this.date, required this.partner,
    required this.place, required this.detail, this.psych = ''});

  factory SexualRecord.fromMap(Map<String, dynamic> m) => SexualRecord(
    date: m['date'] ?? '',
    partner: m['partner'] ?? '',
    place: m['place'] ?? '',
    detail: m['detail'] ?? '',
    psych: m['psych'] ?? '',
  );
}

class SexualComparison {
  final String partner;
  final String period;
  final String dominance;
  final String oral;
  final String ejac;
  final String cohabitation;
  final String breakup;
  final String expense;
  final Color color;

  SexualComparison({required this.partner, required this.period,
    required this.dominance, required this.oral, required this.ejac,
    required this.cohabitation, required this.breakup, required this.expense,
    required this.color});

  factory SexualComparison.fromMap(Map<String, dynamic> m) => SexualComparison(
    partner: m['partner'] ?? '',
    period: m['period'] ?? '',
    dominance: m['dominance'] ?? '',
    oral: m['oral'] ?? '',
    ejac: m['ejac'] ?? '',
    cohabitation: m['cohabitation'] ?? '',
    breakup: m['breakup'] ?? '',
    expense: m['expense'] ?? '',
    color: _parseColor(m['color']),
  );
}

class PcCorrelationRow {
  final String period;
  final String trigger;
  final String pcBang;
  final String hub;
  final String recovery;

  PcCorrelationRow({required this.period, required this.trigger,
    required this.pcBang, required this.hub, required this.recovery});

  factory PcCorrelationRow.fromMap(Map<String, dynamic> m) => PcCorrelationRow(
    period: m['period'] ?? '',
    trigger: m['trigger'] ?? '',
    pcBang: m['pcBang'] ?? '',
    hub: m['hub'] ?? '',
    recovery: m['recovery'] ?? '',
  );
}

class SexualData {
  final List<SexualPartnerRecord> partnerRecords;
  final String preferences;
  // backward compat
  final List<SexualPreference> preferenceList;
  final List<SexualRecord> records;
  final List<SexualComparison> comparisons;
  final List<PsychPattern> patterns;
  final List<PcCorrelationRow> pcCorrelation;

  SexualData({
    this.partnerRecords = const [],
    this.preferences = '',
    this.preferenceList = const [],
    this.records = const [],
    this.comparisons = const [],
    this.patterns = const [],
    this.pcCorrelation = const [],
  });

  factory SexualData.fromMap(Map<String, dynamic> m) => SexualData(
    partnerRecords: _parseList(m['partnerRecords'], SexualPartnerRecord.fromMap),
    preferences: m['preferences'] is String ? m['preferences'] as String : '',
    preferenceList: m['preferences'] is List
        ? _parseList(m['preferences'], SexualPreference.fromMap)
        : [],
    records: _parseList(m['records'], SexualRecord.fromMap),
    comparisons: _parseList(m['comparisons'], SexualComparison.fromMap),
    patterns: _parseList(m['patterns'], PsychPattern.fromMap),
    pcCorrelation: _parseList(m['pcCorrelation'], PcCorrelationRow.fromMap),
  );
}

// ═══ Psych Pattern ═══

class PsychPattern {
  final String title;
  final Color color;
  final String body;
  final List<Map<String, String>>? data;

  PsychPattern({required this.title, required this.color, required this.body,
    this.data});

  factory PsychPattern.fromMap(Map<String, dynamic> m) => PsychPattern(
    title: m['title'] ?? '',
    color: _parseColor(m['color']),
    body: m['body'] ?? '',
    data: (m['data'] as List?)?.map((e) =>
        (e as Map).map((k, v) => MapEntry(k.toString(), v.toString())).cast<String, String>()).toList(),
  );
}

// ═══ Psych Analysis (심리 분석) — V9 expanded ═══

class PsychRoot {
  final int num;
  final String title;
  final String body;
  final Color color;

  PsychRoot({required this.num, required this.title, required this.body, required this.color});

  factory PsychRoot.fromMap(Map<String, dynamic> m) => PsychRoot(
    num: _toInt(m['num']),
    title: m['title'] ?? '',
    body: m['body'] ?? '',
    color: _parseColor(m['color']),
  );
}

class PermissionCeiling {
  final String title;
  final String body;
  final Color color;

  PermissionCeiling({required this.title, required this.body, required this.color});

  factory PermissionCeiling.fromMap(Map<String, dynamic> m) => PermissionCeiling(
    title: m['title'] ?? '',
    body: m['body'] ?? '',
    color: _parseColor(m['color']),
  );
}

class TitledSection {
  final String title;
  final String body;
  final Color? color;

  TitledSection({required this.title, required this.body, this.color});

  factory TitledSection.fromMap(Map<String, dynamic> m) => TitledSection(
    title: m['title'] ?? '',
    body: m['body'] ?? '',
    color: m['color'] != null ? _parseColor(m['color']) : null,
  );
}

class ConfirmationLoss {
  final TitledSection before;
  final TitledSection after;
  final String analysis;

  ConfirmationLoss({required this.before, required this.after, required this.analysis});

  factory ConfirmationLoss.fromMap(Map<String, dynamic> m) => ConfirmationLoss(
    before: TitledSection.fromMap(Map<String, dynamic>.from((m['before'] ?? {}) as Map)),
    after: TitledSection.fromMap(Map<String, dynamic>.from((m['after'] ?? {}) as Map)),
    analysis: m['analysis'] ?? '',
  );
}

// V11 NEW: Discovery13 heal pattern
class Discovery13Section {
  final String title;
  final List<TitledSection> sections;

  Discovery13Section({required this.title, this.sections = const []});

  factory Discovery13Section.fromMap(Map<String, dynamic> m) => Discovery13Section(
    title: m['title'] ?? '',
    sections: _parseList(m['sections'], TitledSection.fromMap),
  );
}

// V11 NEW: Civil service motivation
class CivilServiceMotivation {
  final String title;
  final List<TitledSection> points;
  final String conclusion;

  CivilServiceMotivation({required this.title, this.points = const [],
    this.conclusion = ''});

  factory CivilServiceMotivation.fromMap(Map<String, dynamic> m) => CivilServiceMotivation(
    title: m['title'] ?? '',
    points: _parseList(m['points'], TitledSection.fromMap),
    conclusion: m['conclusion'] ?? '',
  );
}

class PsychAnalysisData {
  final List<PsychRoot> roots;
  final PermissionCeiling? permissionCeiling;
  final String deepeningFlow;
  final List<TitledSection> deepeningSections;
  final ConfirmationLoss? confirmationLoss;
  final List<TitledSection> sexCoexistenceList;
  final Map<String, dynamic>? sexCoexistenceMap;
  final List<String> coreQuotes;
  final List<PsychPattern> patterns;
  // V11 additions
  final Discovery13Section? discovery13HealPattern;
  final CivilServiceMotivation? civilServiceMotivation;

  PsychAnalysisData({
    required this.roots, this.permissionCeiling,
    this.deepeningFlow = '',
    this.deepeningSections = const [],
    this.confirmationLoss,
    this.sexCoexistenceList = const [],
    this.sexCoexistenceMap,
    required this.coreQuotes, required this.patterns,
    this.discovery13HealPattern, this.civilServiceMotivation,
  });

  factory PsychAnalysisData.fromMap(Map<String, dynamic> m) {
    final sexCo = m['sexCoexistence'];
    return PsychAnalysisData(
      roots: _parseList(m['roots'], PsychRoot.fromMap),
      permissionCeiling: m['permissionCeiling'] != null
          ? PermissionCeiling.fromMap(Map<String, dynamic>.from(m['permissionCeiling'] as Map))
          : null,
      deepeningFlow: m['deepeningFlow'] ?? '',
      deepeningSections: _parseList(m['deepeningSections'], TitledSection.fromMap),
      confirmationLoss: m['confirmationLoss'] != null
          ? ConfirmationLoss.fromMap(Map<String, dynamic>.from(m['confirmationLoss'] as Map))
          : null,
      sexCoexistenceList: sexCo is List ? _parseList(sexCo, TitledSection.fromMap) : [],
      sexCoexistenceMap: sexCo is Map ? Map<String, dynamic>.from(sexCo) : null,
      coreQuotes: _strList(m['coreQuotes']),
      patterns: _parseList(m['patterns'], PsychPattern.fromMap),
      discovery13HealPattern: m['discovery13_healPattern'] != null
          ? Discovery13Section.fromMap(Map<String, dynamic>.from(m['discovery13_healPattern'] as Map))
          : null,
      civilServiceMotivation: m['civilServiceMotivation'] != null
          ? CivilServiceMotivation.fromMap(Map<String, dynamic>.from(m['civilServiceMotivation'] as Map))
          : null,
    );
  }
}

// ═══ Exam Analysis (공시 분석) — V9 expanded ═══

class ExamScore {
  final String category;
  final double score;
  final double cutoff;
  final double gap;
  final String note;

  ExamScore({required this.category, required this.score, required this.cutoff,
    required this.gap, required this.note});

  factory ExamScore.fromMap(Map<String, dynamic> m) => ExamScore(
    category: m['category'] ?? '',
    score: (m['score'] as num?)?.toDouble() ?? 0,
    cutoff: (m['cutoff'] as num?)?.toDouble() ?? 0,
    gap: (m['gap'] as num?)?.toDouble() ?? 0,
    note: m['note'] ?? '',
  );
}

class ExamYearEntry {
  final String year;
  final List<String> events;

  ExamYearEntry({required this.year, required this.events});

  factory ExamYearEntry.fromMap(Map<String, dynamic> m) => ExamYearEntry(
    year: m['year'] ?? '',
    events: _strList(m['events']),
  );
}

class DiagnosisSide {
  final String title;
  final List<String> points;

  DiagnosisSide({required this.title, required this.points});

  factory DiagnosisSide.fromMap(Map<String, dynamic> m) => DiagnosisSide(
    title: m['title'] ?? '',
    points: _strList(m['points']),
  );
}

class ExamPath {
  final String title;
  final String premise;
  final String evidence;
  final String period;
  final String risk;

  ExamPath({required this.title, required this.premise, required this.evidence,
    required this.period, this.risk = ''});

  factory ExamPath.fromMap(Map<String, dynamic> m) => ExamPath(
    title: m['title'] ?? '',
    premise: m['premise'] ?? '',
    evidence: m['evidence'] ?? '',
    period: m['period'] ?? '',
    risk: m['risk'] ?? '',
  );
}

class TransferConditions {
  final List<String> had;
  final List<String> missing;
  final List<String> have;
  final String coreQuestion;

  TransferConditions({required this.had, required this.missing,
    required this.have, required this.coreQuestion});

  factory TransferConditions.fromMap(Map<String, dynamic> m) => TransferConditions(
    had: _strList(m['had']),
    missing: _strList(m['missing']),
    have: _strList(m['have']),
    coreQuestion: m['coreQuestion'] ?? '',
  );
}

class ExamAnalysisData {
  final List<ExamScore> scores;
  final DiagnosisSide? methodDiagnosis;
  final DiagnosisSide? permissionDiagnosis;
  final List<ExamYearEntry> history;
  final ExamPath? pathA;
  final ExamPath? pathB;
  final TransferConditions? transferConditions;
  final List<String> coldAssessment;
  final List<String> evidence;

  ExamAnalysisData({required this.scores, this.methodDiagnosis,
    this.permissionDiagnosis, required this.history,
    this.pathA, this.pathB, this.transferConditions,
    required this.coldAssessment, required this.evidence});

  factory ExamAnalysisData.fromMap(Map<String, dynamic> m) => ExamAnalysisData(
    scores: _parseList(m['scores'], ExamScore.fromMap),
    methodDiagnosis: m['methodDiagnosis'] != null
        ? DiagnosisSide.fromMap(Map<String, dynamic>.from(m['methodDiagnosis'] as Map))
        : null,
    permissionDiagnosis: m['permissionDiagnosis'] != null
        ? DiagnosisSide.fromMap(Map<String, dynamic>.from(m['permissionDiagnosis'] as Map))
        : null,
    history: _parseList(m['history'], ExamYearEntry.fromMap),
    pathA: m['pathA'] != null
        ? ExamPath.fromMap(Map<String, dynamic>.from(m['pathA'] as Map))
        : null,
    pathB: m['pathB'] != null
        ? ExamPath.fromMap(Map<String, dynamic>.from(m['pathB'] as Map))
        : null,
    transferConditions: m['transferConditions'] != null
        ? TransferConditions.fromMap(Map<String, dynamic>.from(m['transferConditions'] as Map))
        : null,
    coldAssessment: _strList(m['coldAssessment']),
    evidence: _strList(m['evidence']),
  );
}

// ═══ Compare (그들과 나) — V9 NEW ═══

class PasserScoreChip {
  final String label;
  final String value;

  PasserScoreChip({required this.label, required this.value});

  factory PasserScoreChip.fromMap(Map<String, dynamic> m) => PasserScoreChip(
    label: m['label'] ?? '',
    value: m['value'] ?? '',
  );
}

class PasserCard {
  final String name;
  final String info;
  final String summary;
  final List<PasserScoreChip> scores;
  final String weakness;
  final String takeaway;

  PasserCard({required this.name, required this.info, required this.summary,
    this.scores = const [], required this.weakness, required this.takeaway});

  factory PasserCard.fromMap(Map<String, dynamic> m) => PasserCard(
    name: m['name'] ?? '',
    info: m['info'] ?? '',
    summary: m['summary'] ?? '',
    scores: _parseList(m['scores'], PasserScoreChip.fromMap),
    weakness: m['weakness'] ?? '',
    takeaway: m['takeaway'] ?? '',
  );
}

class CompareTableRow {
  final String name;
  final List<String> cells;
  final bool isMe;

  CompareTableRow({required this.name, this.cells = const [], this.isMe = false});

  factory CompareTableRow.fromMap(Map<String, dynamic> m) => CompareTableRow(
    name: m['name'] ?? '',
    cells: _strList(m['cells']),
    isMe: m['isMe'] ?? false,
  );
}

class GapAnalysisRow {
  final String category;
  final String passerMethod;
  final String current;
  final String gapLevel;

  GapAnalysisRow({required this.category, required this.passerMethod,
    required this.current, required this.gapLevel});

  factory GapAnalysisRow.fromMap(Map<String, dynamic> m) => GapAnalysisRow(
    category: m['category'] ?? '',
    passerMethod: m['passerMethod'] ?? '',
    current: m['current'] ?? '',
    gapLevel: m['gapLevel'] ?? '',
  );
}

class CompareData {
  final String intro;
  final List<PasserCard> passers;
  final List<String> summaryHeaders;
  final List<CompareTableRow> summaryTable;
  final List<String> transitionHeaders;
  final List<CompareTableRow> transitionTable;
  final List<GapAnalysisRow> gapAnalysis;
  final String verdict;
  final String cheonhongQuote;

  CompareData({
    this.intro = '', this.passers = const [],
    this.summaryHeaders = const [], this.summaryTable = const [],
    this.transitionHeaders = const [], this.transitionTable = const [],
    this.gapAnalysis = const [], this.verdict = '',
    this.cheonhongQuote = '',
  });

  factory CompareData.fromMap(Map<String, dynamic> m) => CompareData(
    intro: m['intro'] ?? '',
    passers: _parseList(m['passers'], PasserCard.fromMap),
    summaryHeaders: _strList(m['summaryHeaders']),
    summaryTable: _parseList(m['summaryTable'], CompareTableRow.fromMap),
    transitionHeaders: _strList(m['transitionHeaders']),
    transitionTable: _parseList(m['transitionTable'], CompareTableRow.fromMap),
    gapAnalysis: _parseList(m['gapAnalysis'], GapAnalysisRow.fromMap),
    verdict: m['verdict'] ?? '',
    cheonhongQuote: m['cheonhongQuote'] ?? '',
  );
}

// ═══ Economy ═══

class EconomyStat {
  final String label;
  final String value;
  final String sub;
  final Color? color;

  EconomyStat({required this.label, required this.value, required this.sub,
    this.color});

  factory EconomyStat.fromMap(Map<String, dynamic> m) => EconomyStat(
    label: m['label'] ?? '',
    value: m['value'] ?? '',
    sub: m['sub'] ?? '',
    color: m['color'] != null ? _parseColor(m['color']) : null,
  );
}

class IncomeBar {
  final String label;
  final int widthPercent;
  final String color;
  final String value;

  IncomeBar({required this.label, required this.widthPercent,
    required this.color, required this.value});

  factory IncomeBar.fromMap(Map<String, dynamic> m) => IncomeBar(
    label: m['label'] ?? '',
    widthPercent: _toInt(m['widthPercent']),
    color: m['color'] ?? 'accent',
    value: m['value'] ?? '',
  );
}

class EconomyData {
  final List<EconomyStat> stats;
  final List<IncomeBar> incomeBars;
  final List<IncomeBar> categoryBars;
  final List<String> fakeTags;
  final String places;
  final String pcBangSummary;
  final String consumptionPattern;
  // V11 additions
  final List<TitledSection> incomeHistory;
  final Map<String, dynamic>? dayoungBypass;
  final Map<String, dynamic>? pcBang;

  EconomyData({required this.stats, this.incomeBars = const [],
    this.categoryBars = const [], this.fakeTags = const [],
    this.places = '',
    this.pcBangSummary = '', this.consumptionPattern = '',
    this.incomeHistory = const [], this.dayoungBypass, this.pcBang});

  factory EconomyData.fromMap(Map<String, dynamic> m) => EconomyData(
    stats: _parseList(m['stats'], EconomyStat.fromMap),
    incomeBars: _parseList(m['incomeBars'], IncomeBar.fromMap),
    categoryBars: _parseList(m['categoryBars'], IncomeBar.fromMap),
    fakeTags: _strList(m['fakeTags']),
    places: m['places'] ?? '',
    pcBangSummary: m['pcBangSummary'] ?? '',
    consumptionPattern: m['consumptionPattern'] ?? '',
    incomeHistory: _parseList(m['incomeHistory'], TitledSection.fromMap),
    dayoungBypass: m['dayoungBypass'] != null
        ? Map<String, dynamic>.from(m['dayoungBypass'] as Map) : null,
    pcBang: m['pcBang'] != null
        ? Map<String, dynamic>.from(m['pcBang'] as Map) : null,
  );
}

// ═══ Growth Quote (육성 기록) ═══

class GrowthQuote {
  final String text;
  final String context;

  GrowthQuote({required this.text, required this.context});

  factory GrowthQuote.fromMap(Map<String, dynamic> m) => GrowthQuote(
    text: m['text'] ?? '',
    context: m['context'] ?? '',
  );
}

// ═══ Novel (소설 콘티) — V9 NEW ═══

class NovelChapter {
  final int num;
  final String title;
  final int pages;
  final String description;

  NovelChapter({required this.num, required this.title, required this.pages,
    required this.description});

  factory NovelChapter.fromMap(Map<String, dynamic> m) => NovelChapter(
    num: _toInt(m['num']),
    title: m['title'] ?? '',
    pages: _toInt(m['pages']),
    description: m['description'] ?? '',
  );
}

class NovelPart {
  final int num;
  final String title;
  final String period;
  final int pages;
  final Color color;
  final List<NovelChapter> chapters;

  NovelPart({required this.num, required this.title, required this.period,
    required this.pages, required this.color, required this.chapters});

  factory NovelPart.fromMap(Map<String, dynamic> m) => NovelPart(
    num: _toInt(m['num']),
    title: m['title'] ?? '',
    period: m['period'] ?? '',
    pages: _toInt(m['pages']),
    color: _parseColor(m['color']),
    chapters: _parseList(m['chapters'], NovelChapter.fromMap),
  );
}

class NovelData {
  final String title;
  final String subtitle;
  final String quote;
  final List<NovelPart> parts;
  final List<String> stylePrinciples;
  final String status;

  NovelData({this.title = '', this.subtitle = '', this.quote = '',
    this.parts = const [], this.stylePrinciples = const [],
    this.status = ''});

  factory NovelData.fromMap(Map<String, dynamic> m) => NovelData(
    title: m['title'] ?? '',
    subtitle: m['subtitle'] ?? '',
    quote: m['quote'] ?? '',
    parts: _parseList(m['parts'], NovelPart.fromMap),
    stylePrinciples: _strList(m['stylePrinciples']),
    status: m['status'] ?? '',
  );
}

// ═══ Todo (V9 restructured) ═══

class TodoData {
  final List<String> done;
  final List<String> high;
  final List<String> medium;
  final List<String> events;
  // V9 additions
  final List<String> priority;
  final List<String> novelTasks;
  final List<String> interviews;
  final List<String> unconfirmed;

  TodoData({required this.done, required this.high, this.medium = const [],
    required this.events, this.priority = const [],
    this.novelTasks = const [], this.interviews = const [],
    this.unconfirmed = const []});

  factory TodoData.fromMap(Map<String, dynamic> m) => TodoData(
    done: _strList(m['done']),
    high: _strList(m['high']),
    medium: _strList(m['medium']),
    events: _strList(m['events']),
    priority: _strList(m['priority']),
    novelTasks: _strList(m['novelTasks']),
    interviews: _strList(m['interviews']),
    unconfirmed: _strList(m['unconfirmed']),
  );
}

/// Hex color parser
Color _parseColor(dynamic hex) {
  if (hex == null) return const Color(0xFF5b8cff);
  final s = hex.toString().replaceFirst('#', '');
  return Color(int.parse('FF$s', radix: 16));
}
