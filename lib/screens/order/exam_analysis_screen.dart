import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../../models/roadmap_models.dart';

/// ═══════════════════════════════════════════════════════════
/// 공시 분석 — 독립 화면 (Flame 배경 + 다크 프리미엄)
/// ═══════════════════════════════════════════════════════════

// ─── Colors ───
const _bg = Color(0xFF0C0A12);
const _surface = Color(0xFF16131F);
const _border = Color(0xFF2A2538);
const _tx = Color(0xFFE0DAD0);
const _txSub = Color(0xFF9990A8);
const _txMuted = Color(0xFF6A6278);
const _purple = Color(0xFF7B4DB8);
const _purpleGlow = Color(0xFF9B6DDB);
const _cyan = Color(0xFF4AADAD);
const _red = Color(0xFFC04040);
const _green = Color(0xFF4AA060);
const _gold = Color(0xFFB89030);

// ═══════════════════════════════════════════════════════════
//  Flame Background — 보라 파티클 + 빛줄기
// ═══════════════════════════════════════════════════════════

class _ExamBgGame extends FlameGame {
  final Random _rng = Random();

  @override
  ui.Color backgroundColor() => _bg;

  @override
  Future<void> onLoad() async {
    for (int i = 0; i < 40; i++) {
      add(_Mote(rng: _rng, gs: size));
    }
    for (int i = 0; i < 6; i++) {
      add(_Ray(rng: _rng, gs: size));
    }
  }
}

// ─── 떠다니는 먼지 ───
class _Mote extends PositionComponent with HasGameRef<_ExamBgGame> {
  final Random rng;
  late double speed, opacity, wobble, radius;

  _Mote({required this.rng, required Vector2 gs}) {
    speed = 4 + rng.nextDouble() * 10;
    opacity = 0.05 + rng.nextDouble() * 0.15;
    wobble = rng.nextDouble() * 2 * pi;
    radius = 0.3 + rng.nextDouble() * 1.2;
    position = Vector2(rng.nextDouble() * gs.x, rng.nextDouble() * gs.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y -= speed * dt;
    wobble += dt * 0.4;
    position.x += sin(wobble) * 0.3;
    if (position.y < -10) {
      position.y = gameRef.size.y + 10;
      position.x = rng.nextDouble() * gameRef.size.x;
    }
  }

  @override
  void render(ui.Canvas canvas) {
    canvas.drawCircle(ui.Offset.zero, radius,
        ui.Paint()..color = _purpleGlow.withValues(alpha: opacity));
  }
}

// ─── 빛줄기 ───
class _Ray extends PositionComponent with HasGameRef<_ExamBgGame> {
  final Random rng;
  late double phase, length, angle, baseOp;

  _Ray({required this.rng, required Vector2 gs}) {
    phase = rng.nextDouble() * 2 * pi;
    length = 60 + rng.nextDouble() * 120;
    angle = -pi / 2 + (rng.nextDouble() - 0.5) * 0.6;
    baseOp = 0.02 + rng.nextDouble() * 0.04;
    position = Vector2(rng.nextDouble() * gs.x, rng.nextDouble() * gs.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    phase += dt * 0.5;
  }

  @override
  void render(ui.Canvas canvas) {
    final op = baseOp * (0.3 + 0.7 * sin(phase).abs());
    final end = Offset(cos(angle) * length, sin(angle) * length);
    canvas.drawLine(
      ui.Offset.zero, end,
      ui.Paint()
        ..color = _purpleGlow.withValues(alpha: op)
        ..strokeWidth = 1.5
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Exam Analysis Screen
// ═══════════════════════════════════════════════════════════

class ExamAnalysisScreen extends StatefulWidget {
  const ExamAnalysisScreen({super.key});
  @override
  State<ExamAnalysisScreen> createState() => _ExamAnalysisScreenState();
}

class _ExamAnalysisScreenState extends State<ExamAnalysisScreen>
    with SingleTickerProviderStateMixin {
  ExamAnalysisData? _data;
  bool _loading = true;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;
  final _game = _ExamBgGame();

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 800));
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final json = await rootBundle.loadString('assets/roadmap/roadmap_data.json');
      final map = Map<String, dynamic>.from(jsonDecode(json) as Map);
      final roadmap = RoadmapData.fromMap(map);
      _safeSetState(() {
        _data = roadmap.examAnalysis;
        _loading = false;
      });
      _fadeCtrl.forward();
    } catch (e) {
      _safeSetState(() => _loading = false);
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _tx, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(children: [
        Positioned.fill(child: GameWidget(game: _game)),
        Positioned.fill(child: IgnorePointer(child: Container(
          decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [_bg.withValues(alpha: 0.4), Colors.transparent, _bg.withValues(alpha: 0.7)],
            stops: const [0, 0.3, 1],
          )),
        ))),
        SafeArea(child: _loading
            ? const Center(child: CircularProgressIndicator(color: _purple))
            : _data == null
                ? Center(child: Text('데이터 로드 실패', style: TextStyle(color: _txSub)))
                : FadeTransition(opacity: _fade, child: _buildContent())),
      ]),
    );
  }

  Widget _buildContent() {
    final ea = _data!;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ─── 헤더 ───
        const Text('공시 분석', style: TextStyle(
          fontSize: 36, fontWeight: FontWeight.w900, color: _tx,
          letterSpacing: -1.5, height: 1.1)),
        const SizedBox(height: 6),
        Text('현실성 이중 진단', style: TextStyle(
          fontSize: 14, color: _purple, fontWeight: FontWeight.w600, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text('방법의 문제 + 허락의 문제', style: TextStyle(
          fontSize: 12, color: _txMuted, height: 1.6)),
        const SizedBox(height: 28),

        // ─── 성적 ───
        _sectionTitle('성적 비교'),
        ...ea.scores.map(_scoreCard),

        // ─── 이중 진단 ───
        if (ea.methodDiagnosis != null && ea.permissionDiagnosis != null) ...[
          _sectionTitle('이중 진단'),
          _diagnosisCard(ea.methodDiagnosis!, _cyan, Icons.build_rounded),
          const SizedBox(height: 4),
          Center(child: Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: _border, width: 1.5)),
            child: const Center(child: Text('+', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w700, color: _purple))),
          )),
          const SizedBox(height: 4),
          _diagnosisCard(ea.permissionDiagnosis!, _red, Icons.lock_rounded),
        ],

        // ─── 시험 이력 ───
        if (ea.history.isNotEmpty) ...[
          _sectionTitle('시험 이력'),
          ...ea.history.map(_historyCard),
        ],

        // ─── 경로 A / B ───
        if (ea.pathA != null) ...[
          _sectionTitle('경로 A / 경로 B'),
          _pathCard(ea.pathA!, 'A', _cyan),
          if (ea.pathB != null) _pathCard(ea.pathB!, 'B', _purple),
        ],

        // ─── 편입 조건 ───
        if (ea.transferConditions != null) ...[
          _sectionTitle('편입준비기 복제 조건'),
          _transferCard(ea.transferConditions!),
        ],

        // ─── 능력 증거 ───
        if (ea.evidence.isNotEmpty) ...[
          _sectionTitle('능력 증거'),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: ea.evidence.map((e) => _bullet(e)).toList())),
        ],

        // ─── 그들과 나 ───
        _sectionTitle('그들과 나'),
        _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('합격자 9명 개별 정밀 해부', style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: _tx)),
          const SizedBox(height: 8),
          Text('그들의 단점을 냉철하게, 천홍과의 차이를 정확하게.\n'
            '합격수기에 안 썼다고 없는 게 아니다.',
            style: TextStyle(fontSize: 12, color: _txSub, height: 1.6)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: const [
            _PasserChip('고나연', '외교관후보자', '연세대'),
            _PasserChip('강민우', '5급 일반행정', '한양대'),
            _PasserChip('이혜린', '5급 일반행정', '한양대'),
            _PasserChip('신재훈', '최연소 합격', '고려대'),
            _PasserChip('이윤진', '외교관후보자', '이화여대'),
            _PasserChip('김태영', '5급 재경직', '서강대'),
            _PasserChip('박주영', '5급 일반행정', '서울대'),
            _PasserChip('정승호', '5급 교육행정', '경북대'),
            _PasserChip('한서연', '5급 일반행정', '성균관대'),
          ]),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: const Text('전체 분석 보기 (V9)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _purple,
              side: BorderSide(color: _purple.withValues(alpha: 0.4)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const _V9CompareViewer())),
          )),
        ])),

        const SizedBox(height: 20),
      ]),
    );
  }

  // ═══ 위젯 빌더 ═══

  Widget _sectionTitle(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 14),
    child: Row(children: [
      Container(width: 3, height: 18,
        decoration: BoxDecoration(
          color: _purple,
          borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 10),
      Text(title, style: const TextStyle(
        fontSize: 18, fontWeight: FontWeight.w800, color: _tx, letterSpacing: -0.5)),
    ]),
  );

  Widget _card(Widget child, {Color leftColor = _border}) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _border.withValues(alpha: 0.6)),
    ),
    child: child,
  );

  Widget _scoreCard(ExamScore s) {
    final isPassing = s.gap >= 0;
    final barColor = isPassing ? _green : (s.gap <= -5 ? _red : _gold);
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(s.category, style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, color: _tx)),
          const SizedBox(height: 3),
          Text('합격선 ${s.cutoff.toStringAsFixed(2)} · ${isPassing ? "합격" : "차이 ${s.gap.toStringAsFixed(2)}"}',
            style: TextStyle(fontSize: 11, color: _txSub)),
        ])),
        Text(s.score == s.score.roundToDouble()
            ? '${s.score.toInt()}' : s.score.toStringAsFixed(2),
          style: TextStyle(fontFamily: 'monospace', fontSize: 28,
            fontWeight: FontWeight.w700, color: barColor)),
      ]),
      if (s.note.isNotEmpty) ...[
        const SizedBox(height: 12),
        // 프로그레스 바
        SizedBox(height: 20, child: LayoutBuilder(builder: (_, c) {
          final w = c.maxWidth;
          return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(children: [
              Container(color: _border),
              Positioned(left: 0, top: 0, bottom: 0,
                width: w * (s.score / 100).clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      barColor.withValues(alpha: 0.7), barColor.withValues(alpha: 0.4)]),
                  ),
                )),
              Positioned(
                left: (w * (s.cutoff / 100).clamp(0.0, 1.0) - 1),
                top: 0, bottom: 0,
                child: Container(width: 2, color: _tx.withValues(alpha: 0.8))),
            ]),
          );
        })),
        const SizedBox(height: 6),
        Text(s.note, style: const TextStyle(fontSize: 11, color: _txSub, height: 1.5)),
      ],
    ]));
  }

  Widget _diagnosisCard(DiagnosisSide d, Color color, IconData icon) => _card(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(d.title, style: TextStyle(
          fontSize: 14, fontWeight: FontWeight.w700, color: color)),
      ]),
      const SizedBox(height: 10),
      ...d.points.map((p) => _bullet(p, color: color)),
    ]),
  );

  Widget _historyCard(ExamYearEntry h) => _card(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(h.year, style: const TextStyle(
        fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.w700, color: _purple)),
      const SizedBox(height: 6),
      Text(h.events.join('. '), style: const TextStyle(
        fontSize: 13, color: _txSub, height: 1.6)),
    ]),
  );

  Widget _pathCard(ExamPath path, String label, Color color) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface.withValues(alpha: 0.85),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.3)),
    ),
    child: Stack(children: [
      Positioned(top: -4, right: 0,
        child: Text(label, style: TextStyle(fontFamily: 'monospace',
          fontSize: 40, fontWeight: FontWeight.w900,
          color: color.withValues(alpha: 0.12)))),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(path.title, style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 10),
        if (path.premise.isNotEmpty) _labelValue('전제', path.premise),
        if (path.evidence.isNotEmpty) _labelValue('근거', path.evidence),
        if (path.period.isNotEmpty) _labelValue('기간', path.period),
        if (path.risk.isNotEmpty) _labelValue('리스크', path.risk),
      ]),
    ]),
  );

  Widget _transferCard(TransferConditions tc) => _card(
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (tc.had.isNotEmpty) ...[
        _subLabel('편입 때 있었던 것'),
        ...tc.had.map((h) => _bullet(h, color: _green)),
      ],
      if (tc.missing.isNotEmpty) ...[
        const SizedBox(height: 10),
        _subLabel('지금 없는 것'),
        ...tc.missing.map((m) => _bullet(m, color: _red)),
      ],
      if (tc.have.isNotEmpty) ...[
        const SizedBox(height: 10),
        _subLabel('지금 있는 것'),
        ...tc.have.map((h) => _bullet(h, color: _cyan)),
      ],
      if (tc.coreQuestion.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: _purple.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(6)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.help_outline_rounded, size: 16, color: _purple),
            const SizedBox(width: 8),
            Expanded(child: Text(tc.coreQuestion, style: const TextStyle(
              fontSize: 13, color: _tx, fontWeight: FontWeight.w600, height: 1.5))),
          ]),
        ),
      ],
    ]),
  );

  Widget _bullet(String text, {Color color = _txSub}) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        margin: const EdgeInsets.only(top: 7, right: 10),
        width: 4, height: 4,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
      Expanded(child: Text(text, style: TextStyle(
        fontSize: 13, color: _txSub, height: 1.6))),
    ]),
  );

  Widget _labelValue(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 50, child: Text(label, style: const TextStyle(
        fontSize: 11, fontWeight: FontWeight.w700, color: _txMuted))),
      Expanded(child: Text(value, style: const TextStyle(
        fontSize: 13, color: _txSub, height: 1.5))),
    ]),
  );

  Widget _subLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(
      fontSize: 12, fontWeight: FontWeight.w700, color: _tx)),
  );
}

// ─── 합격자 칩 ───
class _PasserChip extends StatelessWidget {
  final String name, exam, school;
  const _PasserChip(this.name, this.exam, this.school);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: _border.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(6)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700, color: _tx)),
      Text('$exam · $school', style: const TextStyle(
        fontSize: 9, color: _txMuted)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════
//  V9 "그들과 나" 전체 뷰어
// ═══════════════════════════════════════════════════════════

class _V9CompareViewer extends StatefulWidget {
  const _V9CompareViewer();
  @override
  State<_V9CompareViewer> createState() => _V9CompareViewerState();
}

class _V9CompareViewerState extends State<_V9CompareViewer> {
  String _html = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final section = await rootBundle.loadString('assets/roadmap/그들과나.html');
      _safeSetState(() { _html = section; _loading = false; });
    } catch (e) {
      _safeSetState(() => _loading = false);
    }
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(fn);
      });
    } else {
      setState(fn);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _bg,
    appBar: AppBar(
      backgroundColor: _surface,
      title: const Text('그들과 나', style: TextStyle(
        fontSize: 18, fontWeight: FontWeight.w800, color: _tx)),
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new, color: _tx, size: 20),
        onPressed: () => Navigator.pop(context)),
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator(color: _purple))
        : SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: _renderHtml(_html)),
  );

  Widget _renderHtml(String html) {
    // 간단 HTML → Flutter 위젯 변환
    final cards = <Widget>[];
    // 서문 추출
    final prefaceMatch = RegExp(r'<h3[^>]*>(.*?)</h3>\s*<p[^>]*>(.*?)</p>', dotAll: true)
        .firstMatch(html);
    if (prefaceMatch != null) {
      cards.add(Container(
        margin: const EdgeInsets.only(bottom: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface, borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: _purple, width: 3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_stripTags(prefaceMatch.group(1)!), style: const TextStyle(
            fontSize: 15, fontWeight: FontWeight.w700, color: _tx)),
          const SizedBox(height: 8),
          Text(_stripTags(prefaceMatch.group(2)!), style: const TextStyle(
            fontSize: 12, color: _txSub, height: 1.7)),
        ]),
      ));
    }

    // 합격자 카드 추출 (①~⑨ 패턴)
    final cardPattern = RegExp(
      r'<!-- [①②③④⑤⑥⑦⑧⑨] .*?-->\s*<div[^>]*>.*?'
      r'<span[^>]*font-weight:700[^>]*>(.*?)</span>.*?'
      r'font-size:10px[^>]*>(.*?)</div>.*?'
      r'<div[^>]*padding:20px 22px[^>]*>(.*?)</div></div>',
      dotAll: true,
    );

    for (final m in cardPattern.allMatches(html)) {
      final name = _stripTags(m.group(1)!);
      final meta = _stripTags(m.group(2)!);
      final body = m.group(3)!;

      // 수험기간
      final periodMatch = RegExp(r'<b>수험기간:</b>\s*(.*?)</p>', dotAll: true).firstMatch(body);
      final period = periodMatch != null ? _stripTags(periodMatch.group(1)!) : '';

      // 냉철한 단점
      final weakMatch = RegExp(r'냉철한 단점 지적:</b>\s*(.*?)</div>', dotAll: true).firstMatch(body);
      final weakness = weakMatch != null ? _stripTags(weakMatch.group(1)!) : '';

      // 천홍이 가져갈 것
      final takeMatch = RegExp(r'천홍이 가져갈 것:</b>\s*(.*?)</div>', dotAll: true).firstMatch(body);
      final takeaway = takeMatch != null ? _stripTags(takeMatch.group(1)!) : '';

      cards.add(Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: _surface, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _border.withValues(alpha: 0.3),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10))),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Flexible(child: Text(name, style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: _tx))),
              Flexible(child: Text(meta, style: const TextStyle(
                fontSize: 9, color: _txMuted), textAlign: TextAlign.right)),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(14), child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (period.isNotEmpty) ...[
                Text(period, style: const TextStyle(
                  fontSize: 12, color: _txSub, height: 1.6)),
                const SizedBox(height: 12),
              ],
              if (weakness.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border(left: BorderSide(color: _red, width: 2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('냉철한 단점', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: _red)),
                    const SizedBox(height: 4),
                    Text(weakness, style: const TextStyle(
                      fontSize: 11, color: _txSub, height: 1.6)),
                  ]),
                ),
                const SizedBox(height: 8),
              ],
              if (takeaway.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border(left: BorderSide(color: _green, width: 2))),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('가져갈 것', style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700, color: _green)),
                    const SizedBox(height: 4),
                    Text(takeaway, style: const TextStyle(
                      fontSize: 11, color: _txSub, height: 1.6)),
                  ]),
                ),
            ],
          )),
        ]),
      ));
    }

    if (cards.isEmpty) {
      cards.add(const Text('데이터를 파싱할 수 없습니다.',
        style: TextStyle(color: _txSub)));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: cards);
  }

  String _stripTags(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .trim();
}
