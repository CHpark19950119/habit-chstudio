import 'dart:math';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'order/order_life_tab.dart';
import 'order/novel_viewer_screen.dart';
import 'order/exam_analysis_screen.dart';

/// ═══════════════════════════════════════════════════════════
/// 경로 — 박천홍의 여정
/// Flame 배경 + Flutter 인터랙티브 UI
/// 소설(허락)과 실제기록(로드맵) 분리 진입
/// ═══════════════════════════════════════════════════════════

// ─── Colors ───
const _cBg = Color(0xFF0F0D0A);
const _cEarth = Color(0xFF3A2E1E);
const _cDust = Color(0xFFC8B48C);
const _cAc = Color(0xFF8B2500);
const _cAc2 = Color(0xFF2D5A7B);
const _cBone = Color(0xFFE8DCC8);
const _cMoss = Color(0xFF4A5A3A);

// ═══════════════════════════════════════════════════════════
//  Flame Background Game — 먼지·반딧불·터치 파티클
// ═══════════════════════════════════════════════════════════

class _JourneyBgGame extends FlameGame {
  final Random _rng = Random();

  @override
  ui.Color backgroundColor() => _cBg;

  @override
  Future<void> onLoad() async {
    for (int i = 0; i < 55; i++) {
      add(_Dust(rng: _rng, gs: size));
    }
    for (int i = 0; i < 10; i++) {
      add(_Firefly(rng: _rng, gs: size));
    }
  }

  /// Flutter 쪽에서 호출 → 터치 위치에 파티클 폭발
  void spawnBurst(Offset pos) {
    for (int i = 0; i < 18; i++) {
      add(_Burst(origin: Vector2(pos.dx, pos.dy), rng: _rng));
    }
  }
}

// ─── 먼지 파티클 ───
class _Dust extends PositionComponent with HasGameRef<_JourneyBgGame> {
  final Random rng;
  late double speed;
  late double opacity;
  late double wobble;
  late double radius;

  _Dust({required this.rng, required Vector2 gs}) {
    speed = 6 + rng.nextDouble() * 16;
    opacity = 0.06 + rng.nextDouble() * 0.2;
    wobble = rng.nextDouble() * 2 * pi;
    radius = 0.4 + rng.nextDouble() * 1.6;
    position = Vector2(rng.nextDouble() * gs.x, rng.nextDouble() * gs.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    position.y -= speed * dt;
    wobble += dt * (0.3 + rng.nextDouble() * 0.15);
    position.x += sin(wobble) * 0.35;
    if (position.y < -20) {
      position.y = gameRef.size.y + 20;
      position.x = rng.nextDouble() * gameRef.size.x;
    }
  }

  @override
  void render(ui.Canvas canvas) {
    canvas.drawCircle(
      ui.Offset.zero,
      radius,
      ui.Paint()..color = _cDust.withValues(alpha: opacity),
    );
  }
}

// ─── 반딧불 ───
class _Firefly extends PositionComponent with HasGameRef<_JourneyBgGame> {
  final Random rng;
  late double phase;
  late double dx, dy;
  late double baseOp;
  late double glow;

  _Firefly({required this.rng, required Vector2 gs}) {
    phase = rng.nextDouble() * 2 * pi;
    final spd = 3 + rng.nextDouble() * 7;
    final a = rng.nextDouble() * 2 * pi;
    dx = cos(a) * spd;
    dy = sin(a) * spd;
    baseOp = 0.12 + rng.nextDouble() * 0.22;
    glow = 3 + rng.nextDouble() * 5;
    position = Vector2(rng.nextDouble() * gs.x, rng.nextDouble() * gs.y);
  }

  @override
  void update(double dt) {
    super.update(dt);
    phase += dt * 1.1;
    position.x += dx * dt;
    position.y += dy * dt;
    final s = gameRef.size;
    if (position.x < 0 || position.x > s.x) dx = -dx;
    if (position.y < 0 || position.y > s.y) dy = -dy;
    position.x = position.x.clamp(0, s.x);
    position.y = position.y.clamp(0, s.y);
  }

  @override
  void render(ui.Canvas canvas) {
    final op = baseOp * (0.5 + 0.5 * sin(phase));
    canvas.drawCircle(
      ui.Offset.zero,
      glow * 2.2,
      ui.Paint()
        ..color = Color.fromRGBO(200, 180, 140, op * 0.25)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 8),
    );
    canvas.drawCircle(
      ui.Offset.zero,
      glow * 0.5,
      ui.Paint()..color = _cBone.withValues(alpha: op),
    );
  }
}

// ─── 터치 폭발 파티클 ───
class _Burst extends PositionComponent {
  final Random rng;
  late double vx, vy;
  double life = 0;
  final double maxLife;
  late double radius;
  late Color color;

  _Burst({required Vector2 origin, required this.rng})
      : maxLife = 0.4 + rng.nextDouble() * 0.8 {
    position = origin.clone();
    final a = rng.nextDouble() * 2 * pi;
    final spd = 25 + rng.nextDouble() * 70;
    vx = cos(a) * spd;
    vy = sin(a) * spd;
    radius = 0.8 + rng.nextDouble() * 2.5;
    const colors = [_cDust, _cAc, _cBone, _cMoss];
    color = colors[rng.nextInt(colors.length)];
  }

  @override
  void update(double dt) {
    super.update(dt);
    life += dt;
    if (life >= maxLife) {
      removeFromParent();
      return;
    }
    position.x += vx * dt;
    position.y += vy * dt;
    vx *= 0.96;
    vy *= 0.96;
    vy += 12 * dt;
  }

  @override
  void render(ui.Canvas canvas) {
    final t = life / maxLife;
    canvas.drawCircle(
      ui.Offset.zero,
      radius * (1 - t * 0.4),
      ui.Paint()..color = color.withValues(alpha: (1 - t) * 0.65),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Journey Screen (Flutter + Flame)
// ═══════════════════════════════════════════════════════════

class JourneyScreen extends StatefulWidget {
  const JourneyScreen({super.key});
  @override
  State<JourneyScreen> createState() => _JourneyScreenState();
}

class _JourneyScreenState extends State<JourneyScreen>
    with TickerProviderStateMixin {
  late AnimationController _enterCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _cardCtrl;

  late Animation<double> _titleFade;
  late Animation<Offset> _titleSlide;
  // 카드별 slide-up + fade (고급스러운 등장)
  late Animation<double> _card1Fade;
  late Animation<Offset> _card1Slide;
  late Animation<double> _card2Fade;
  late Animation<Offset> _card2Slide;
  late Animation<double> _card3Fade;
  late Animation<Offset> _card3Slide;
  late Animation<double> _pulse;

  final _game = _JourneyBgGame();

  @override
  void initState() {
    super.initState();
    _enterCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3000))
      ..repeat(reverse: true);
    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800));

    _titleFade = CurvedAnimation(
        parent: _enterCtrl,
        curve: const Interval(0, 0.5, curve: Curves.easeOut));
    _titleSlide = Tween<Offset>(
            begin: const Offset(0, -0.3), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _enterCtrl,
            curve: const Interval(0, 0.5, curve: Curves.easeOutCubic)));

    // 카드 1: 0~0.45 — slide up + fade
    _card1Fade = CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0, 0.45, curve: Curves.easeOut));
    _card1Slide = Tween<Offset>(
            begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _cardCtrl,
            curve: const Interval(0, 0.45, curve: Curves.easeOutQuint)));

    // 카드 2: 0.18~0.63
    _card2Fade = CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.18, 0.63, curve: Curves.easeOut));
    _card2Slide = Tween<Offset>(
            begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _cardCtrl,
            curve: const Interval(0.18, 0.63, curve: Curves.easeOutQuint)));

    // 카드 3: 0.36~0.81
    _card3Fade = CurvedAnimation(
        parent: _cardCtrl,
        curve: const Interval(0.36, 0.81, curve: Curves.easeOut));
    _card3Slide = Tween<Offset>(
            begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _cardCtrl,
            curve: const Interval(0.36, 0.81, curve: Curves.easeOutQuint)));

    _pulse = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _enterCtrl.forward();
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _cardCtrl.forward();
    });
  }

  @override
  void dispose() {
    _enterCtrl.dispose();
    _pulseCtrl.dispose();
    _cardCtrl.dispose();
    super.dispose();
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
          icon: const Icon(Icons.arrow_back_ios_new, color: _cBone, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(children: [
        // Flame 배경
        Positioned.fill(child: GameWidget(game: _game)),
        // 그래디언트 오버레이
        Positioned.fill(
            child: IgnorePointer(
                child: Container(
          decoration: BoxDecoration(
              gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _cBg.withValues(alpha: 0.3),
              Colors.transparent,
              _cBg.withValues(alpha: 0.6),
            ],
            stops: const [0, 0.35, 1],
          )),
        ))),
        // 터치 이벤트 → Flame 파티클
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (e) => _game.spawnBurst(e.localPosition),
          child: SafeArea(child: _buildContent()),
        ),
      ]),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 48),
          _buildTitle(),
          const SizedBox(height: 8),
          _buildSubtitle(),
          const SizedBox(height: 48),
          _buildNovelCard(),
          const SizedBox(height: 20),
          _buildDivider(),
          const SizedBox(height: 20),
          _buildRoadmapCard(),
          const SizedBox(height: 20),
          _buildDivider(),
          const SizedBox(height: 20),
          _buildExamCard(),
          const SizedBox(height: 40),
          _buildStats(),
          const SizedBox(height: 32),
          _buildQuote(),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  // ─── Title ───
  Widget _buildTitle() {
    return SlideTransition(
      position: _titleSlide,
      child: FadeTransition(
        opacity: _titleFade,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('경로',
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  color: _cBone,
                  letterSpacing: -2,
                  height: 1.1,
                  shadows: [
                    Shadow(color: _cAc.withValues(alpha: 0.3), blurRadius: 24)
                  ],
                )),
            const SizedBox(height: 6),
            Container(
              width: 56,
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                    colors: [_cAc, _cAc.withValues(alpha: 0)]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubtitle() {
    return FadeTransition(
      opacity: _titleFade,
      child: Text(
        '박천홍의 여정을 따라가다',
        style: TextStyle(
          fontSize: 13,
          color: _cDust.withValues(alpha: 0.55),
          letterSpacing: 3,
          height: 1.8,
        ),
      ),
    );
  }

  Widget _buildDivider() {
    return FadeTransition(
      opacity: _titleFade,
      child: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (_, __) {
            final p = _pulse.value;
            return Container(
              width: 120,
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  _cDust.withValues(alpha: 0.15 + p * 0.1),
                  Colors.transparent,
                ]),
              ),
            );
          },
        ),
      ),
    );
  }

  // ─── Novel Card ───
  Widget _buildNovelCard() {
    return SlideTransition(
      position: _card1Slide,
      child: FadeTransition(
      opacity: _card1Fade,
      child: _JCard(
        title: '허락',
        subtitle: '제1부: 흙',
        description: '1995년부터 2013년까지,\n한 사람의 뿌리를 파헤치는 소설',
        icon: Icons.menu_book_rounded,
        tags: const ['11챕터', '전반 · 후반'],
        gradient: [_cEarth.withValues(alpha: 0.85), _cBg.withValues(alpha: 0.75)],
        accentColor: _cAc,
        pulse: _pulse,
        chapters: const [
          '01  754',
          '02  이사',
          '03  사마귀',
          '04  찬양',
          '05  바닥',
          '06  바깥 원',
          '07  목격',
          '08  MB',
          '09  딴지',
          '10  잉꼬',
          '11  수능',
        ],
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const NovelViewerScreen())),
      ),
    ));
  }

  // ─── Roadmap Card ───
  Widget _buildRoadmapCard() {
    return SlideTransition(
      position: _card2Slide,
      child: FadeTransition(
      opacity: _card2Fade,
      child: _JCard(
        title: '실제 기록',
        subtitle: '인생 로드맵 v13',
        description: '13,315건의 데이터로 복원한\n실제 삶의 궤적',
        icon: Icons.route_rounded,
        tags: const ['12섹션', '1995–2026'],
        gradient: [
          const Color(0xFF1A2030).withValues(alpha: 0.85),
          _cBg.withValues(alpha: 0.75)
        ],
        accentColor: _cAc2,
        pulse: _pulse,
        sections: const [
          '통합 타임라인',
          '거주지 아카이브',
          '연애사',
          '인터넷 여성들',
          '전수 분석',
          '심리 분석',
          '경제활동',
          '성적 기록',
          '육성 기록',
          '소설 콘티',
          '미완료 과제',
        ],
        onTap: () => _pushLifeTab(0),
      ),
    ));
  }

  // ─── Exam Analysis Card ───
  Widget _buildExamCard() {
    return SlideTransition(
      position: _card3Slide,
      child: FadeTransition(
      opacity: _card3Fade,
      child: _JCard(
        title: '공시 분석',
        subtitle: '현실성 이중 진단',
        description: '방법의 문제와 허락의 문제,\n점수·이력·경로 분석',
        icon: Icons.analytics_rounded,
        tags: const ['점수 분석', '경로 A/B'],
        gradient: [
          const Color(0xFF1A1A2E).withValues(alpha: 0.85),
          _cBg.withValues(alpha: 0.75)
        ],
        accentColor: const Color(0xFF6B3A8B),
        pulse: _pulse,
        sections: const [
          '성적 비교',
          '이중 진단',
          '시험 이력',
          '경로 A / B',
          '편입 조건',
          '능력 증거',
        ],
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ExamAnalysisScreen())),
      ),
    ));
  }

  void _pushLifeTab(int tab) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: const Color(0xFFF5F0E8),
        appBar: AppBar(
          backgroundColor: const Color(0xFFF5F0E8),
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF1A1611)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(child: OrderLifeTab(initialTab: tab)),
      ),
    ));
  }

  // ─── Stats ───
  Widget _buildStats() {
    return FadeTransition(
      opacity: _titleFade,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          final p = _pulse.value;
          final op = 0.3 + p * 0.2;
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _stat('탄생', '1995.01.19', op),
              const SizedBox(width: 14),
              _stat('데이터', '13,315건', op),
              const SizedBox(width: 14),
              _stat('인터뷰', '14호기', op),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value, double op) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: _cDust.withValues(alpha: op * 0.4)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                color: _cDust.withValues(alpha: op),
                letterSpacing: 1.2)),
        const SizedBox(height: 2),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _cBone.withValues(alpha: op + 0.3),
                fontFamily: 'monospace')),
      ]),
    );
  }

  // ─── Quote ───
  Widget _buildQuote() {
    return FadeTransition(
      opacity: _titleFade,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: _cAc.withValues(alpha: 0.4), width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '"그때는 열심히 뭔가를 해보려고 했어.\n지금은 숨고 싶어진다."',
              style: TextStyle(
                fontSize: 13,
                color: _cDust.withValues(alpha: 0.5),
                height: 1.9,
                fontStyle: FontStyle.italic,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '— 14호기 인터뷰 中',
              style: TextStyle(
                fontSize: 10,
                color: _cDust.withValues(alpha: 0.3),
                letterSpacing: 0.5,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  Journey Card — 인터랙티브 카드 위젯
// ═══════════════════════════════════════════════════════════

class _JCard extends StatefulWidget {
  final String title, subtitle, description;
  final IconData icon;
  final List<String> tags;
  final List<Color> gradient;
  final Color accentColor;
  final Animation<double> pulse;
  final VoidCallback onTap;
  final List<String>? chapters;
  final List<String>? sections;

  const _JCard({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.tags,
    required this.gradient,
    required this.accentColor,
    required this.pulse,
    required this.onTap,
    this.chapters,
    this.sections,
  });

  @override
  State<_JCard> createState() => _JCardState();
}

class _JCardState extends State<_JCard> with SingleTickerProviderStateMixin {
  bool _pressed = false;
  bool _expanded = false;
  late AnimationController _expandCtrl;
  late Animation<double> _expandAnim;

  @override
  void initState() {
    super.initState();
    _expandCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _expandAnim =
        CurvedAnimation(parent: _expandCtrl, curve: Curves.easeOutCubic);
  }

  @override
  void dispose() {
    _expandCtrl.dispose();
    super.dispose();
  }

  void _toggleExpand() {
    HapticFeedback.selectionClick();
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _expandCtrl.forward();
    } else {
      _expandCtrl.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.chapters ?? widget.sections ?? [];
    final isNovel = widget.chapters != null;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        HapticFeedback.mediumImpact();
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: AnimatedBuilder(
          animation: widget.pulse,
          builder: (_, __) {
            final p = widget.pulse.value;
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: widget.gradient,
                ),
                border: Border.all(
                  color: widget.accentColor.withValues(alpha: 0.25 + p * 0.15),
                ),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: widget.accentColor.withValues(alpha: 0.08 + p * 0.08),
                    blurRadius: 24 + p * 12,
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 메인 카드 바디
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 아이콘 + 태그 행
                        Row(children: [
                          Icon(widget.icon,
                              color: widget.accentColor, size: 26),
                          const Spacer(),
                          ...widget.tags.map((t) => Container(
                                margin: const EdgeInsets.only(left: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 3),
                                decoration: BoxDecoration(
                                  color: widget.accentColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(t,
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: widget.accentColor,
                                        fontWeight: FontWeight.w600)),
                              )),
                        ]),
                        const SizedBox(height: 14),
                        // 제목
                        Text(widget.title,
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                                color: _cBone,
                                letterSpacing: -1,
                                height: 1.2)),
                        const SizedBox(height: 4),
                        Text(widget.subtitle,
                            style: TextStyle(
                                fontSize: 14,
                                color: widget.accentColor,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5)),
                        const SizedBox(height: 10),
                        Text(widget.description,
                            style: TextStyle(
                                fontSize: 12.5,
                                color: _cDust.withValues(alpha: 0.6),
                                height: 1.7)),
                        const SizedBox(height: 14),
                        // 하단: 열기 버튼 + 펼치기
                        Row(children: [
                          if (items.isNotEmpty)
                            GestureDetector(
                              onTap: _toggleExpand,
                              behavior: HitTestBehavior.opaque,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AnimatedRotation(
                                    turns: _expanded ? 0.25 : 0,
                                    duration: const Duration(milliseconds: 250),
                                    child: Icon(Icons.chevron_right_rounded,
                                        color: _cDust.withValues(alpha: 0.4),
                                        size: 18),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _expanded
                                        ? '접기'
                                        : isNovel
                                            ? '챕터 목록'
                                            : '섹션 목록',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: _cDust.withValues(alpha: 0.4)),
                                  ),
                                ],
                              ),
                            ),
                          const Spacer(),
                          Icon(Icons.arrow_forward_rounded,
                              color: widget.accentColor
                                  .withValues(alpha: 0.4 + p * 0.3),
                              size: 20),
                        ]),
                      ],
                    ),
                  ),
                  // 펼침 영역: 챕터/섹션 목록
                  SizeTransition(
                    sizeFactor: _expandAnim,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 1,
                            color: widget.accentColor.withValues(alpha: 0.1),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: items
                                .asMap()
                                .entries
                                .map((e) => _itemChip(
                                    e.value, e.key, items.length, isNovel))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _itemChip(String text, int index, int total, bool isNovel) {
    // 소설: 전반(0-4) 갈색, 후반(5-10) 짙은 갈색
    // 로드맵: 인덱스 기반 색상 변화
    final t = index / max(total - 1, 1);
    final Color chipColor;
    if (isNovel) {
      chipColor = index < 5
          ? Color.lerp(_cAc, _cEarth, t * 2)!
          : Color.lerp(_cEarth, const Color(0xFF2A2018), (t - 0.5) * 2)!;
    } else {
      chipColor = Color.lerp(_cAc2, const Color(0xFF1A4A5A), t)!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: chipColor.withValues(alpha: 0.15)),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10,
              color: _cBone.withValues(alpha: 0.7),
              fontWeight: FontWeight.w500)),
    );
  }
}
