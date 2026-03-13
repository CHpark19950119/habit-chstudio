import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/roadmap_models.dart';
import 'novel_viewer_screen.dart';

/// ═══════════════════════════════════════════════════════════
/// 인생 로드맵 v11 — 12탭 (거주지/인터넷여성/2017~18전수 신규)
/// ═══════════════════════════════════════════════════════════
class OrderLifeTab extends StatefulWidget {
  const OrderLifeTab({super.key});
  @override
  State<OrderLifeTab> createState() => _OrderLifeTabState();
}

class _OrderLifeTabState extends State<OrderLifeTab>
    with SingleTickerProviderStateMixin {
  RoadmapData? _data;
  String? _error;
  late TabController _tabCtrl;

  static const _tabs = [
    '통합 타임라인', '거주지', '연애사', '인터넷 여성', '2017~18 전수',
    '심리 분석', '공시 분석', '경제활동', '성적 기록', '육성 기록',
    '소설 콘티', '미완료 과제',
  ];

  static const _ac  = Color(0xFF8b2500);
  static const _ac2 = Color(0xFF2d5a7b);
  static const _gn  = Color(0xFF2d6b3f);
  static const _gd  = Color(0xFF8b6914);
  static const _pk  = Color(0xFF8b3a5e);
  static const _rd  = Color(0xFF9b1b1b);
  static const _cy  = Color(0xFF1a6b6b);
  static const _bg  = Color(0xFFF5F0E8);
  static const _sf  = Color(0xFFECE6D9);
  static const _sf2 = Color(0xFFE2DBD0);
  static const _bd  = Color(0xFFC4B9A8);
  static const _tx  = Color(0xFF1A1611);
  static const _tx2 = Color(0xFF5A5347);
  static const _dm  = Color(0xFF8A8177);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _loadData();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    try {
      final raw = await rootBundle.loadString('assets/roadmap/roadmap_data.json');
      final map = json.decode(raw) as Map<String, dynamic>;
      if (mounted) setState(() => _data = RoadmapData.fromMap(map));
    } catch (e) {
      debugPrint('[Roadmap] Load error: $e');
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, size: 48, color: _dm),
          const SizedBox(height: 12),
          const Text('데이터 로딩 실패', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _tx)),
          const SizedBox(height: 6),
          Text(_error!, style: const TextStyle(fontSize: 13, color: _dm), textAlign: TextAlign.center),
        ]),
      ));
    }
    if (_data == null) {
      return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: _ac)),
        SizedBox(height: 14),
        Text('로드맵 로딩 중...', style: TextStyle(fontSize: 14, color: _dm)),
      ]));
    }
    return Container(color: _bg, child: Column(children: [
      _buildHero(),
      _buildTabBar(),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [
        _lv(_buildTimeline), _lv(_buildHomes), _lv(_buildRelationships),
        _lv(_buildInternetWomen), _lv(_buildDetail),
        _lv(_buildPsychAnalysis), _lv(_buildExamAnalysis), _lv(_buildEconomy),
        _lv(_buildSexual), _lv(_buildGrowthQuotes), _lv(_buildNovel),
        _lv(_buildTodos),
      ])),
    ]));
  }

  Widget _lv(List<Widget> Function() b) =>
      ListView(padding: const EdgeInsets.fromLTRB(14, 20, 14, 60), children: b());

  // ═══════════════════════════════════════
  //  HEADER
  // ═══════════════════════════════════════

  Widget _buildHero() {
    final m = _data!.meta;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [_bg, Color(0xFFede4d4), Color(0xFFe8ddc8)]),
        border: Border(bottom: BorderSide(color: _ac, width: 2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
          const Text('박천홍 ', style: TextStyle(fontFamily: 'NotoSerifKR', fontSize: 20, fontWeight: FontWeight.w900, color: _tx)),
          const Text('인생 로드맵', style: TextStyle(fontFamily: 'NotoSerifKR', fontSize: 20, fontWeight: FontWeight.w900, color: _ac)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), color: _ac,
            child: Text(m.version, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 1.5))),
        ]),
        const SizedBox(height: 6),
        Text(m.subtitle, style: const TextStyle(fontSize: 11, color: _tx2, fontFamily: 'monospace')),
        if (m.headerQuote.isNotEmpty) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _ac.withOpacity(0.03),
              border: const Border(left: BorderSide(color: _ac, width: 2)),
            ),
            child: Text(m.headerQuote, style: const TextStyle(fontFamily: 'NotoSerifKR', fontSize: 12, color: _tx2, height: 1.8)),
          ),
        ),
      ]),
    );
  }

  Widget _buildTabBar() => Container(
    height: 44,
    decoration: const BoxDecoration(color: _sf, border: Border(bottom: BorderSide(color: _bd))),
    child: TabBar(
      controller: _tabCtrl, isScrollable: true, tabAlignment: TabAlignment.start,
      padding: EdgeInsets.zero, labelPadding: const EdgeInsets.symmetric(horizontal: 14),
      indicatorColor: _ac, indicatorWeight: 2, dividerColor: Colors.transparent,
      labelColor: _ac, unselectedLabelColor: _dm,
      labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      tabs: _tabs.map((t) => Tab(text: t)).toList(),
    ),
  );

  // ═══════════════════════════════════════
  //  SHARED WIDGETS
  // ═══════════════════════════════════════

  Widget _st(String title, {String? small, double top = 0}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 18),
    child: Container(
      padding: const EdgeInsets.only(bottom: 10),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _bd))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontFamily: 'NotoSerifKR', fontSize: 21, fontWeight: FontWeight.w700, color: _tx, letterSpacing: -0.5)),
        if (small != null) Padding(padding: const EdgeInsets.only(top: 4),
          child: Text(small, style: const TextStyle(fontSize: 13, color: _dm))),
      ]),
    ),
  );

  Widget _subSt(String title, {double top = 20}) => Padding(
    padding: EdgeInsets.only(top: top, bottom: 14),
    child: Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: _bd))),
      child: Text(title, style: const TextStyle(fontFamily: 'NotoSerifKR', fontSize: 17, fontWeight: FontWeight.w700, color: _tx)),
    ),
  );

  Widget _cd(List<Widget> children, {Color leftColor = _ac}) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.fromLTRB(14, 16, 12, 14),
    decoration: BoxDecoration(
      color: _sf,
      border: Border(
        top: const BorderSide(color: _bd),
        right: const BorderSide(color: _bd),
        bottom: const BorderSide(color: _bd),
        left: BorderSide(color: leftColor, width: 3),
      ),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
  );

  Widget _h3(String t) => Padding(padding: const EdgeInsets.only(bottom: 6),
    child: Text(t, style: const TextStyle(fontFamily: 'NotoSerifKR', fontSize: 16, fontWeight: FontWeight.w700, color: _tx)));

  Widget _sub(String t) => Padding(padding: const EdgeInsets.only(bottom: 8),
    child: Text(t, style: const TextStyle(fontSize: 12, color: _dm, fontFamily: 'monospace')));

  Widget _p(String t) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _rich(t));

  Widget _rich(String text) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\*\*(.*?)\*\*');
    int i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700, color: _tx)));
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    if (spans.isEmpty) spans.add(TextSpan(text: text));
    return RichText(text: TextSpan(style: const TextStyle(fontSize: 14, color: _tx2, height: 1.75), children: spans));
  }

  Widget _bq(String text, {String? attr}) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(color: _sf, border: Border(left: BorderSide(color: _ac, width: 3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(text, style: const TextStyle(fontFamily: 'NotoSerifKR', fontSize: 15, color: _tx, height: 1.8)),
      if (attr != null) Padding(padding: const EdgeInsets.only(top: 8),
        child: Text(attr, style: const TextStyle(fontSize: 11, color: _dm, fontFamily: 'monospace'))),
    ]),
  );

  Widget _row(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _dm)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontSize: 14, color: _tx2, height: 1.6)),
    ]),
  );

  Widget _cmpRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 56, child: Text(label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _dm))),
      Expanded(child: Text(value,
        style: const TextStyle(fontSize: 13, color: _tx2, height: 1.5))),
    ]),
  );

  Widget _chip(String text, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: c.withOpacity(0.1),
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: c.withOpacity(0.3)),
    ),
    child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c)),
  );

  Color _tagColor(String tag) {
    final t = tag.toLowerCase();
    if (t.contains('수연') || t.contains('예지') || t.contains('민지') || t.contains('olive') ||
        t.contains('sohui') || t.contains('다영') || t.contains('프랑스') || t.contains('종교') ||
        t.contains('반동거')) return _pk;
    if (t.contains('해병') || t.contains('외대') || t.contains('알바') || t.contains('시네마')) return _ac2;
    if (t.contains('편입') || t.contains('전환') || t.contains('합격') || t.contains('gpa') ||
        t.contains('jlpt') || t.contains('행동')) return _gn;
    if (t.contains('pc') || t.contains('이문동') || t.contains('자취') || t.contains('군포')) return _gd;
    return _rd;
  }

  Widget _tag(String t, Color c) => Container(
    margin: const EdgeInsets.only(right: 5, bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    color: c,
    child: Text(t, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
  );

  Color _hex(String c) {
    switch (c) {
      case 'accent': return _ac; case 'accent2': return _ac2; case 'green': return _gn;
      case 'gold': return _gd; case 'pink': return _pk; case 'red': return _rd;
      default:
        if (c.startsWith('#')) return Color(int.parse('FF${c.substring(1)}', radix: 16));
        return _dm;
    }
  }

  /// Verdict black box
  Widget _verdict(String text) => Container(
    margin: const EdgeInsets.symmetric(vertical: 20),
    padding: const EdgeInsets.all(20),
    color: _tx,
    child: _richLight(text),
  );

  Widget _richLight(String text) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\*\*(.*?)\*\*');
    int i = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > i) spans.add(TextSpan(text: text.substring(i, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFe8c87a))));
      i = m.end;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    if (spans.isEmpty) spans.add(TextSpan(text: text));
    return RichText(text: TextSpan(style: const TextStyle(fontFamily: 'NotoSerifKR', fontSize: 14, color: _bg, height: 2.0), children: spans));
  }

  /// Flow chart (horizontal arrows)
  Widget _flowChart(String flow) => Container(
    margin: const EdgeInsets.only(bottom: 20),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _sf, border: Border.all(color: _bd)),
    child: Text(flow, textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: _tx2, height: 2.2)),
  );

  /// VS comparison box
  Widget _vsBox(TitledSection left, TitledSection right) => Column(children: [
    _sideBox(left, _gn),
    const Padding(padding: EdgeInsets.symmetric(vertical: 8),
      child: Text('→', textAlign: TextAlign.center,
        style: TextStyle(fontFamily: 'NotoSerifKR', fontSize: 24, fontWeight: FontWeight.w900, color: _ac))),
    _sideBox(right, _rd),
    const SizedBox(height: 16),
  ]);

  Widget _sideBox(TitledSection s, Color c) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _sf,
      border: Border(
        top: const BorderSide(color: _bd),
        right: const BorderSide(color: _bd),
        bottom: const BorderSide(color: _bd),
        left: BorderSide(color: c, width: 3),
      ),
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(s.title, style: TextStyle(fontFamily: 'NotoSerifKR', fontSize: 14, fontWeight: FontWeight.w700, color: c)),
      const SizedBox(height: 8),
      _rich(s.body),
    ]),
  );

  // ═══════════════════════════════════════
  //  1. 통합 타임라인
  // ═══════════════════════════════════════

  List<Widget> _buildTimeline() {
    final rows = _data!.timeline;
    return [
      _st('통합 타임라인', small: '${rows.length}개 시기 — 공적 위치 / 연애 / 심리'),
      ...rows.asMap().entries.map((e) {
        final i = e.key;
        final r = e.value;
        final tint = (r.tint != null && r.tint!.startsWith('#'))
            ? Color(int.parse('FF${r.tint!.substring(1)}', radix: 16)) : null;
        return Container(
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: i.isOdd ? _sf : _bg,
            border: Border(
              bottom: const BorderSide(color: _bd),
              left: BorderSide(color: tint ?? Colors.transparent, width: tint != null ? 3 : 0),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              color: _ac.withOpacity(0.07),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.period, style: const TextStyle(fontFamily: 'monospace', fontSize: 15, fontWeight: FontWeight.w700, color: _ac)),
                if (r.tags.isNotEmpty) Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Wrap(children: r.tags.map((t) => _tag(t, _tagColor(t))).toList()),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (r.career.isNotEmpty && r.career != '—') _row('공적 위치', r.career),
                if (r.relationship.isNotEmpty && r.relationship != '—') _row('연애 관계', r.relationship),
                if (r.psychology.isNotEmpty && r.psychology != '—') _row('심리 상태', r.psychology),
              ]),
            ),
          ]),
        );
      }),
    ];
  }

  // ═══════════════════════════════════════
  //  2. 연애사
  // ═══════════════════════════════════════

  List<Widget> _buildRelationships() => [
    _st('연애사 — ${_data!.relationships.length}명', small: '정수연부터 정다영까지'),
    ..._data!.relationships.map((r) => Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: _sf,
        border: Border(
          top: const BorderSide(color: _bd), right: const BorderSide(color: _bd),
          bottom: const BorderSide(color: _bd), left: BorderSide(color: r.color, width: 4),
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 12),
          decoration: BoxDecoration(
            color: r.color.withOpacity(0.06),
            border: const Border(bottom: BorderSide(color: _bd)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 28, height: 28,
                decoration: BoxDecoration(color: r.color, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: Text('${r.num}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white))),
              const SizedBox(width: 10),
              Expanded(child: Text(r.name,
                style: TextStyle(fontFamily: 'NotoSerifKR', fontSize: 18, fontWeight: FontWeight.w800, color: r.color))),
            ]),
            const SizedBox(height: 6),
            Text(r.subtitle, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _tx)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 6),
          child: Wrap(spacing: 8, runSpacing: 4, children: [
            _chip(r.period, _dm),
            _chip(r.init, r.color),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 12, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ...r.details.asMap().entries.map((e) => Column(children: [
              if (e.key > 0) Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Container(height: 1, color: _bd.withOpacity(0.5)),
              ),
              Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: _rich(e.value)),
            ])),
          ]),
        ),
      ]),
    )),
  ];

  // ═══════════════════════════════════════
  //  3. 심리 분석 — V9 expanded
  // ═══════════════════════════════════════

  List<Widget> _buildPsychAnalysis() {
    final pa = _data!.psychAnalysis;
    return [
      _st('심리 분석', small: '5가지 뿌리 + 허락의 천장 + 13호기 심화'),

      ...pa.roots.asMap().entries.map((e) {
        final root = e.value;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: _sf, border: Border(left: BorderSide(color: root.color, width: 4))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${e.key + 1}. ${root.title}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: root.color)),
            const SizedBox(height: 6),
            _rich(root.body),
          ]),
        );
      }),

      if (pa.permissionCeiling != null) ...[
        _st('허락의 천장', small: pa.permissionCeiling!.title, top: 20),
        _cd([_p(pa.permissionCeiling!.body)]),
      ],

      // 10호기 심화
      if (pa.deepeningFlow.isNotEmpty) ...[
        _st('10호기 심화: 성 문제 → 자격 문제 → 70점', top: 20),
        _flowChart(pa.deepeningFlow),
      ],
      ...pa.deepeningSections.map((s) => _cd([
        _h3(s.title),
        _p(s.body),
      ], leftColor: s.color ?? _ac)),

      // 확신의 소멸
      if (pa.confirmationLoss != null) ...[
        _st('10호기 발견: "확신의 소멸"', top: 20),
        _vsBox(pa.confirmationLoss!.before, pa.confirmationLoss!.after),
        if (pa.confirmationLoss!.analysis.isNotEmpty)
          _cd([_p(pa.confirmationLoss!.analysis)]),
      ],

      // V11: 13호기 발견 — "아픈 것을 고쳐주려고"
      if (pa.discovery13HealPattern != null) ...[
        _st(pa.discovery13HealPattern!.title, top: 20),
        ...pa.discovery13HealPattern!.sections.map((s) => _cd([
          _h3(s.title), _p(s.body),
        ])),
      ],

      // V11: 공무원 선택 동기 구조
      if (pa.civilServiceMotivation != null) ...[
        _st(pa.civilServiceMotivation!.title, top: 20),
        ...pa.civilServiceMotivation!.points.map((s) => _cd([
          _h3(s.title), _p(s.body),
        ])),
        if (pa.civilServiceMotivation!.conclusion.isNotEmpty)
          _verdict(pa.civilServiceMotivation!.conclusion),
      ],

      // 성욕과 공존하는 공부 (V11: may be map or list)
      if (pa.sexCoexistenceMap != null) ...[
        _st('성욕과 공존하는 공부', small: '끊는 것이 아니라 회로를 바꾸는 것', top: 20),
        if (pa.sexCoexistenceMap!['diagnosis'] != null) ...[
          _cd([
            _h3('진단: 포르노는 원인이 아니라 증상이다'),
            ...((pa.sexCoexistenceMap!['diagnosis'] as Map?)?.entries.map((e) =>
              _p('**${e.key}:** ${e.value}')) ?? []),
          ], leftColor: _gn),
        ],
      ] else if (pa.sexCoexistenceList.isNotEmpty) ...[
        _st('11호기 신설: 성욕과 공존하는 공부', small: '끊는 것이 아니라 회로를 바꾸는 것', top: 20),
        ...pa.sexCoexistenceList.map((s) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _sf,
            border: Border(
              top: const BorderSide(color: _bd), right: const BorderSide(color: _bd),
              bottom: const BorderSide(color: _bd), left: const BorderSide(color: _gn, width: 4),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.title, style: const TextStyle(fontFamily: 'NotoSerifKR', fontSize: 15, fontWeight: FontWeight.w700, color: _gn)),
            const SizedBox(height: 8),
            _rich(s.body),
          ]),
        )),
      ],

      // 심리 패턴
      if (pa.patterns.isNotEmpty) ...[
        _subSt('심리 패턴 ${pa.patterns.length}가지', top: 20),
        ...pa.patterns.asMap().entries.map((e) {
          final p = e.value;
          return _cd([_p('**${e.key + 1}. ${p.title}** — ${p.body}')], leftColor: p.color);
        }),
      ],

      // 인용문
      ...pa.coreQuotes.map((q) => _bq('"$q"')),
    ];
  }

  // ═══════════════════════════════════════
  //  4. 공시 분석 — V9 expanded
  // ═══════════════════════════════════════

  List<Widget> _buildExamAnalysis() {
    final ea = _data!.examAnalysis;
    return [
      _st('공시 현실성 분석', small: '이중 진단 확정 — 방법의 문제 + 허락의 문제'),

      ...ea.scores.map((s) {
        final c = s.gap >= 0 ? _gn : (s.gap <= -5 ? _rd : _gd);
        return _statRow(s.category,
          s.score == s.score.roundToDouble() ? '${s.score.toInt()}' : s.score.toStringAsFixed(2),
          '합격선 ${s.cutoff.toStringAsFixed(2)} · ${s.gap >= 0 ? "합격" : "차이 ${s.gap.toStringAsFixed(2)}"}',
          s.note, c, s.score, s.cutoff);
      }),

      // 이중 진단
      if (ea.methodDiagnosis != null && ea.permissionDiagnosis != null) ...[
        _st('이중 진단: 방법 + 허락', top: 20),
        _sideBox(TitledSection(
          title: ea.methodDiagnosis!.title,
          body: ea.methodDiagnosis!.points.map((p) => '• $p').join('\n'),
        ), _ac2),
        const Padding(padding: EdgeInsets.symmetric(vertical: 8),
          child: Text('+', textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'NotoSerifKR', fontSize: 24, fontWeight: FontWeight.w900, color: _ac))),
        _sideBox(TitledSection(
          title: ea.permissionDiagnosis!.title,
          body: ea.permissionDiagnosis!.points.map((p) => '• $p').join('\n'),
        ), _rd),
        const SizedBox(height: 16),
      ],

      if (ea.history.isNotEmpty) ...[
        _subSt('시험 이력 전체', top: 20),
        ...ea.history.map((h) => _cd([_p('**${h.year}:** ${h.events.join(". ")}')])),
      ],

      // 경로 A / B
      if (ea.pathA != null) ...[
        _st('경로 A / 경로 B', top: 20),
        _pathCard(ea.pathA!, 'A'),
        if (ea.pathB != null) _pathCard(ea.pathB!, 'B'),
      ],

      // 편입준비기 복제 조건
      if (ea.transferConditions != null) ...[
        _st('편입준비기 복제 조건 분석', top: 20),
        _cd([
          if (ea.transferConditions!.had.isNotEmpty) ...[
            _p('**편입 때 있었던 것:**'),
            ...ea.transferConditions!.had.map((h) => _p('• $h')),
          ],
          if (ea.transferConditions!.missing.isNotEmpty) ...[
            _p('**지금 없는 것:**'),
            ...ea.transferConditions!.missing.map((m) => _p('• $m')),
          ],
          if (ea.transferConditions!.have.isNotEmpty) ...[
            _p('**지금 있는 것:**'),
            ...ea.transferConditions!.have.map((h) => _p('• $h')),
          ],
          if (ea.transferConditions!.coreQuestion.isNotEmpty)
            _p('**핵심 질문:** ${ea.transferConditions!.coreQuestion}'),
        ]),
      ],

      if (ea.evidence.isNotEmpty) ...[
        _subSt('능력 증거', top: 20),
        _cd([...ea.evidence.map((e) => _p(e))]),
      ],
    ];
  }

  Widget _statRow(String label, String value, String sub, String note, Color color, double score, double cutoff) {
    final isPassing = score >= cutoff;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: _sf, border: Border.all(color: _bd)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _tx)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 12, color: _dm)),
          ])),
          Text(value, style: TextStyle(fontFamily: 'monospace', fontSize: 30, fontWeight: FontWeight.w700, color: color)),
        ]),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 10),
          SizedBox(height: 22, child: LayoutBuilder(builder: (_, c) {
            final w = c.maxWidth;
            return Stack(clipBehavior: Clip.none, children: [
              Container(decoration: BoxDecoration(color: _sf2, border: Border.all(color: _bd, width: 0.5))),
              Positioned(left: 0, top: 0, bottom: 0, width: w * (score / 100).clamp(0.0, 1.0),
                child: Container(color: (isPassing ? _gn : _rd).withOpacity(0.45))),
              Positioned(left: w * (cutoff / 100).clamp(0.0, 1.0) - 1, top: -3, bottom: -3,
                child: Container(width: 2, color: _tx)),
            ]);
          })),
          const SizedBox(height: 4),
          Text(note, style: const TextStyle(fontSize: 12, color: _tx2)),
        ],
      ]),
    );
  }

  Widget _pathCard(ExamPath path, String label) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(color: _sf, border: Border.all(color: _bd)),
    child: Stack(children: [
      Positioned(top: 0, right: 0,
        child: Text(label, style: TextStyle(fontFamily: 'monospace', fontSize: 32, fontWeight: FontWeight.w700, color: _bd))),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _h3(path.title),
        if (path.premise.isNotEmpty) _p('**전제:** ${path.premise}'),
        if (path.evidence.isNotEmpty) _p('**근거:** ${path.evidence}'),
        if (path.period.isNotEmpty) _p('**기간:** ${path.period}'),
        if (path.risk.isNotEmpty) _p('**리스크:** ${path.risk}'),
      ]),
    ]),
  );

  // ═══════════════════════════════════════
  //  2. 거주지 아카이브 — V11 NEW
  // ═══════════════════════════════════════

  List<Widget> _buildHomes() {
    final homes = _data!.homes;
    return [
      _st('거주지 아카이브', small: '등본 확정. ${homes.length}곳'),
      ...homes.map((h) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(color: _sf, border: Border.all(color: _bd)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(h.name, style: const TextStyle(fontFamily: 'NotoSerifKR', fontSize: 16, fontWeight: FontWeight.w700, color: _tx)),
              if (h.address.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                child: Text(h.address, style: const TextStyle(fontSize: 11, color: _dm, fontFamily: 'monospace'))),
              Padding(padding: const EdgeInsets.only(top: 4),
                child: Text(h.period, style: const TextStyle(fontSize: 12, color: _ac, fontWeight: FontWeight.w600))),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: _rich(h.description)),
        ]),
      )),
    ];
  }

  // ═══════════════════════════════════════
  //  4. 인터넷 여성들 — V11 NEW
  // ═══════════════════════════════════════

  List<Widget> _buildInternetWomen() {
    final women = _data!.internetWomen;
    return [
      _st('인터넷 여성들', small: '"현실세계의 사람들과 멀어지는 것에 대한 보상으로 인터넷 여성들을 택한 것"'),
      ...women.map((w) => _cd([
        _h3(w.name),
        if (w.subtitle.isNotEmpty) _sub(w.subtitle),
        if (w.period.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6),
          child: Text('${w.platform} | ${w.nationality} | ${w.period} | 성관계 ${w.sexualContact ? "있음" : "없음"}',
            style: const TextStyle(fontSize: 11, color: _dm, fontFamily: 'monospace'))),
        _p(w.description),
        if (w.meaning.isNotEmpty) Container(
          margin: const EdgeInsets.only(top: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _cy.withOpacity(0.05),
            border: const Border(left: BorderSide(color: _cy, width: 2)),
          ),
          child: _rich('**의미:** ${w.meaning}'),
        ),
      ], leftColor: _cy)),
    ];
  }

  // ═══════════════════════════════════════
  //  5. 2017~18 거래내역 전수 — V11 NEW
  // ═══════════════════════════════════════

  List<Widget> _buildDetail() {
    final dt = _data!.detailTransactions;
    return [
      _st('2017~2018 거래내역 전수 분석', small: '세션12 확정. 날짜별 주요 거래.'),

      if (dt.year2017.isNotEmpty) ...[
        _subSt('2017년 핵심 이벤트', top: 0),
        ...dt.year2017.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(color: _sf, border: Border.all(color: _bd)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 64, child: Text(e.date,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700, color: _ac))),
            Expanded(child: _rich(e.description)),
          ]),
        )),
      ],

      if (dt.year2018.isNotEmpty) ...[
        _subSt('2018년 핵심 이벤트'),
        ...dt.year2018.map((e) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
          decoration: BoxDecoration(color: _sf, border: Border.all(color: _bd)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 64, child: Text(e.date,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700, color: _ac))),
            Expanded(child: _rich(e.description)),
          ]),
        )),
      ],
    ];
  }

  // ═══════════════════════════════════════
  //  6. 경제활동
  // ═══════════════════════════════════════

  List<Widget> _buildEconomy() {
    final eco = _data!.economy;
    return [
      _st('경제활동 분석', small: '2019~2026 실질지출 / 은행 데이터'),

      ...eco.stats.map((s) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: _sf, border: Border.all(color: _bd)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(s.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _tx))),
            Text(s.value, style: TextStyle(fontFamily: 'monospace', fontSize: 22, fontWeight: FontWeight.w700, color: s.color ?? _ac)),
          ]),
          if (s.sub.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3),
            child: Text(s.sub, style: const TextStyle(fontSize: 12, color: _dm))),
        ]),
      )),
      const SizedBox(height: 12),

      // V11: income history
      if (eco.incomeHistory.isNotEmpty) ...[
        _subSt('수입원 변화'),
        ...eco.incomeHistory.map((s) => _cd([_p('**${s.title}** ${s.body}')])),
      ],

      // V11: 정다영 경유 구조
      if (eco.dayoungBypass != null) ...[
        _subSt('정다영 경유 구조 (v11 신규)'),
        _cd([...((eco.dayoungBypass!['points'] as List?) ?? []).map((p) => _p(p.toString()))]),
      ],

      // PC방 summary (V11 or legacy)
      if (eco.pcBang != null) ...[
        _subSt('PC방 — 마취의 도구'),
        _cd([
          if (eco.pcBang!['total'] != null) _p(eco.pcBang!['total'].toString()),
          if (eco.pcBang!['cycles'] != null) _p(eco.pcBang!['cycles'].toString()),
        ]),
      ] else if (eco.pcBangSummary.isNotEmpty) ...[
        _subSt('PC방 — 마취의 도구'),
        _cd([_p(eco.pcBangSummary)]),
      ],

      // Consumption pattern
      if (eco.consumptionPattern.isNotEmpty) ...[
        _subSt('소비 패턴 특징'),
        _cd([_p(eco.consumptionPattern)]),
      ],

      if (eco.incomeBars.isNotEmpty) ...[
        _subSt('수입원별 비중'),
        _cd([...eco.incomeBars.map((b) => _bar(b))]),
      ],
      if (eco.categoryBars.isNotEmpty) ...[
        _subSt('카테고리별 지출'),
        _cd([...eco.categoryBars.map((b) => _bar(b))]),
      ],
      if (eco.fakeTags.isNotEmpty) ...[
        _subSt('가짜지출 (필터링 필수)'),
        _cd([...eco.fakeTags.map((f) => _p(f))]),
      ],
      if (eco.places.isNotEmpty) ...[
        _subSt('상호명 해독'),
        _cd([_p(eco.places)]),
      ],
    ];
  }

  Widget _bar(IncomeBar b) {
    final c = _hex(b.color);
    return Padding(padding: const EdgeInsets.only(bottom: 12), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(b.label, style: const TextStyle(fontSize: 13, color: _tx2))),
          Text(b.value, style: TextStyle(fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.w700, color: c)),
        ]),
        const SizedBox(height: 4),
        SizedBox(height: 12, child: Stack(children: [
          Container(decoration: BoxDecoration(color: _sf2, border: Border.all(color: _bd, width: 0.5))),
          FractionallySizedBox(widthFactor: b.widthPercent / 100, child: Container(color: c)),
        ])),
      ],
    ));
  }

  // ═══════════════════════════════════════
  //  7. 성적 기록 — V9 simplified
  // ═══════════════════════════════════════

  List<Widget> _buildSexual() {
    final s = _data!.sexual;
    return [
      _st('성적 기록', small: '구체적 기록. 순화 없음.'),

      // V9 partner records (paragraph style)
      if (s.partnerRecords.isNotEmpty)
        ...s.partnerRecords.map((r) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: _sf,
            border: Border(
              top: const BorderSide(color: _bd), right: const BorderSide(color: _bd),
              bottom: const BorderSide(color: _bd),
              left: BorderSide(color: r.color ?? _pColor(r.partner), width: 4),
            ),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              color: (r.color ?? _pColor(r.partner)).withOpacity(0.06),
              child: Row(children: [
                Expanded(child: Text(r.partner,
                  style: TextStyle(fontFamily: 'NotoSerifKR', fontSize: 16, fontWeight: FontWeight.w700,
                    color: r.color ?? _pColor(r.partner)))),
                if (r.period.isNotEmpty) Text(r.period,
                  style: const TextStyle(fontSize: 10, color: _dm, fontFamily: 'monospace')),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: _rich(r.content),
            ),
          ]),
        )),

      // V9 preferences (single paragraph)
      if (s.preferences.isNotEmpty) ...[
        _subSt('성적 취향 구조'),
        _cd([_p(s.preferences)]),
      ],

      // backward compat: old-style records
      if (s.partnerRecords.isEmpty && s.records.isNotEmpty) ..._oldPartnerCards(s.records),

      // backward compat: old comparisons
      if (s.comparisons.isNotEmpty) ...[
        _subSt('상대별 비교'),
        ...s.comparisons.map((c) => _cd([
          _h3(c.partner), _sub(c.period),
          _cmpRow('주도권', c.dominance), _cmpRow('오럴', c.oral),
          _cmpRow('사정', c.ejac), _cmpRow('동거', c.cohabitation),
          _cmpRow('이별', c.breakup), _cmpRow('지출', c.expense),
        ], leftColor: c.color)),
      ],

      if (s.patterns.isNotEmpty) ...[
        _subSt('성적 심리 패턴'),
        ...s.patterns.map((p) => _cd([_p('**${p.title}** — ${p.body}')], leftColor: p.color)),
      ],

      if (s.pcCorrelation.isNotEmpty) ...[
        _subSt('PC방 · 성관계 상관관계'),
        ...s.pcCorrelation.map((r) => _cd([
          _h3(r.period), _cmpRow('트리거', r.trigger),
          _cmpRow('PC방', r.pcBang), _cmpRow('거점', r.hub), _cmpRow('회복', r.recovery),
        ])),
      ],
    ];
  }

  List<Widget> _oldPartnerCards(List<SexualRecord> records) {
    final grouped = <String, List<SexualRecord>>{};
    for (final r in records) grouped.putIfAbsent(r.partner, () => []).add(r);
    return grouped.entries.map((e) => _cd([
      _h3(e.key),
      ...e.value.map((r) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${r.date} · ${r.place}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _pColor(r.partner), fontFamily: 'monospace')),
          const SizedBox(height: 2),
          Text(r.detail, style: const TextStyle(fontSize: 14, color: _tx2, height: 1.6)),
        ]),
      )),
    ], leftColor: _pColor(e.key))).toList();
  }

  Color _pColor(String n) {
    if (n.contains('이예지')) return _pk;
    if (n.contains('영등포')) return _rd;
    if (n.contains('최민지')) return _ac2;
    if (n.contains('Olive')) return _gn;
    if (n.contains('Sohui')) return _pk;
    if (n.contains('프랑스')) return _ac2;
    if (n.contains('정다영')) return _gn;
    if (n.contains('건대')) return _dm;
    return _ac;
  }

  // ═══════════════════════════════════════
  //  8. 육성 기록
  // ═══════════════════════════════════════

  List<Widget> _buildGrowthQuotes() => [
    _st('육성 기록', small: '${_data!.growthQuotes.length}개 — 천홍이 직접 한 말. 원문 그대로.'),
    ..._data!.growthQuotes.map((q) => _bq('"${q.text}"', attr: '— ${q.context}')),
  ];

  // ═══════════════════════════════════════
  //  9. 소설 콘티 — V9 NEW
  // ═══════════════════════════════════════

  List<Widget> _buildNovel() {
    final n = _data!.novel;
    if (n.title.isEmpty) return [_st('소설 콘티', small: '데이터 준비 중')];
    return [
      _st('소설 콘티 — 「${n.title}」', small: n.subtitle),

      GestureDetector(
        onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const NovelViewerScreen())),
        child: Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: _ac.withOpacity(0.08),
            border: const Border(left: BorderSide(color: _ac, width: 3)),
          ),
          child: Row(children: [
            const Icon(Icons.menu_book_rounded, color: _ac, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('소설 원문 읽기', style: TextStyle(
                  fontFamily: 'NotoSerifKR', fontSize: 14, fontWeight: FontWeight.w700, color: _tx)),
                const Text('「허락」 제1부: 흙 (1995~2018)', style: TextStyle(
                  fontSize: 11, color: _dm)),
              ],
            )),
            const Icon(Icons.arrow_forward_ios_rounded, color: _dm, size: 14),
          ]),
        ),
      ),

      if (n.quote.isNotEmpty) _bq('"${n.quote}"'),

      ...n.parts.map((part) => Container(
        margin: const EdgeInsets.only(bottom: 18),
        decoration: BoxDecoration(
          color: _sf,
          border: Border(
            top: const BorderSide(color: _bd), right: const BorderSide(color: _bd),
            bottom: const BorderSide(color: _bd),
            left: BorderSide(color: part.color, width: 4),
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            color: part.color.withOpacity(0.06),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('제${part.num}부: ${part.title}', style: TextStyle(
                fontFamily: 'NotoSerifKR', fontSize: 17, fontWeight: FontWeight.w700, color: part.color)),
              const SizedBox(height: 4),
              Text('${part.period} — ${part.pages}p', style: const TextStyle(fontSize: 11, color: _dm, fontFamily: 'monospace')),
            ]),
          ),
          Padding(padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ...part.chapters.map((ch) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${ch.num}장. ${ch.title} (${ch.pages}p)', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _tx)),
                  if (ch.description.isNotEmpty) Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(ch.description, style: const TextStyle(fontSize: 13, color: _tx2, height: 1.6)),
                  ),
                ]),
              )),
            ]),
          ),
        ]),
      )),

      if (n.stylePrinciples.isNotEmpty) ...[
        _subSt('문체 원칙'),
        _cd([...n.stylePrinciples.map((s) => _p(s))]),
      ],

      if (n.status.isNotEmpty) _verdict(n.status),
    ];
  }

  // ═══════════════════════════════════════
  //  10. 미완료 과제 — V9 restructured
  // ═══════════════════════════════════════

  List<Widget> _buildTodos() {
    final t = _data!.todos;
    return [
      _st('미완료 과제', small: '10호기 이후 작업 목록'),

      // V9: priority
      if (t.priority.isNotEmpty) ...[
        _subSt('최우선 — 전환 실행', top: 0),
        ...t.priority.map((x) => _dot(x, color: _rd, bold: true)),
      ] else if (t.high.isNotEmpty) ...[
        _subSt('최우선', top: 0),
        ...t.high.map((x) => _dot(x, color: _rd, bold: true)),
      ],

      // V9: novel tasks
      if (t.novelTasks.isNotEmpty) ...[
        _subSt('소설 프로젝트'),
        ...t.novelTasks.map((x) => _dot(x, color: _ac2)),
      ],

      // V9: interviews
      if (t.interviews.isNotEmpty) ...[
        _subSt('미완료 인터뷰'),
        ...t.interviews.map((x) => _dot(x)),
      ],

      // V9: unconfirmed
      if (t.unconfirmed.isNotEmpty) ...[
        _subSt('미확인 인물/사건'),
        ...t.unconfirmed.map((x) => _dot(x)),
      ] else ...[
        if (t.medium.isNotEmpty) ...[
          _subSt('미확인 인물'),
          ...t.medium.map((x) => _dot(x)),
        ],
        if (t.events.isNotEmpty) ...[
          _subSt('미확인 사건'),
          ...t.events.map((x) => _dot(x)),
        ],
      ],

      if (t.done.isNotEmpty) ...[
        _subSt('완료 항목'),
        ...t.done.map((x) => _dot(x, color: _gn, done: true)),
      ],
    ];
  }

  Widget _dot(String text, {Color color = _ac, bool bold = false, bool done = false}) => Container(
    margin: const EdgeInsets.only(left: 10),
    padding: const EdgeInsets.symmetric(vertical: 8),
    decoration: const BoxDecoration(border: Border(left: BorderSide(color: _bd, width: 2))),
    child: Stack(clipBehavior: Clip.none, children: [
      Positioned(left: -6, top: 14, child: Container(width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle))),
      Padding(padding: const EdgeInsets.only(left: 18),
        child: Text(text, style: TextStyle(
          fontSize: 14, color: done ? _dm : _tx2,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
          decoration: done ? TextDecoration.lineThrough : null, decorationColor: _dm,
          height: 1.55,
        ))),
    ]),
  );
}
