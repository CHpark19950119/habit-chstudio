import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/botanical_theme.dart';
import '../../models/models.dart';
import '../../services/focus_service.dart';
import 'focus_result_sheet.dart';

class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});
  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen>
    with TickerProviderStateMixin {
  final _fs = FocusService();

  late AnimationController _pulseCtrl;
  bool get _dk => Theme.of(context).brightness == Brightness.dark;

  // theme-aware colors — no hardcoding
  Color get _bg => _dk ? const Color(0xFF18161E) : const Color(0xFFF6F4F0);
  Color get _t1 => _dk ? const Color(0xFFF2ECE4) : const Color(0xFF1A1714);
  Color get _t2 => _dk ? const Color(0xFFB8A898) : const Color(0xFF5C5048);
  Color get _t3 => _dk ? const Color(0xFF7A6E62) : const Color(0xFF9A8E82);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    if (_fs.isRunning) {
      _enterImmersive();
    }
    SubjectConfig.load();
    _loadRecords();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _exitImmersive();
    super.dispose();
  }

  void _enterImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  void _exitImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  static const _focusCh = MethodChannel('com.cheonhong.cheonhong_studio/focus_mode');

  void _goToDashboard() {
    _exitImmersive();
    if (mounted && Navigator.canPop(context)) Navigator.pop(context);
  }

  void _minimizeToHome() {
    _exitImmersive();
    _focusCh.invokeMethod('moveTaskToBack')
        .catchError((_) => SystemNavigator.pop(animated: true));
  }

  void _lockScreen() {
    _exitImmersive();
    _focusCh.invokeMethod('lockScreen').then((ok) {
      if (ok != true) {
        // Device admin not enabled — show hint
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('기기 관리자 권한을 허용하세요'), duration: Duration(seconds: 3)));
        }
      }
    }).catchError((_) {
      // Fallback: just minimize
      _focusCh.invokeMethod('moveTaskToBack').catchError((_) {});
    });
  }

  Future<void> _loadRecords() async {
    try {
      await _fs.getWeeklyStudyMinutes();
      await _fs.refreshTodaySessions();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // ★ AUDIT FIX: P-01 — timerTick + _fs 양쪽 listen (매초 리빌드는 이 화면만)
    return ListenableBuilder(
      listenable: Listenable.merge([_fs, _fs.timerTick]),
      builder: (context, _) {
        if (_fs.isRunning) return _immersiveView();
        // Session ended — pop back to home
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && Navigator.canPop(context)) Navigator.pop(context);
        });
        return Scaffold(backgroundColor: _bg, body: const SizedBox.shrink());
      },
    );
  }

  // ══════════════════════════════════════════
  //  Immersive Focus View
  // ══════════════════════════════════════════

  Widget _immersiveView() {
    final st = _fs.getCurrentState();
    final sc = BotanicalColors.subjectColor(st.subject);
    final isRest = st.mode == 'rest';
    final dc = isRest ? Colors.orange : sc;
    final mE = st.mode == 'study' ? '📖' : st.mode == 'lecture' ? '🎧' : '☕';
    final mL = st.mode == 'study' ? '집중공부' : st.mode == 'lecture' ? '강의듣기' : '휴식';

    return PopScope(
      canPop: isRest,
      onPopInvokedWithResult: (didPop, _) { if (!didPop) _confirmEnd(); },
      child: Scaffold(
        backgroundColor: const Color(0xFF121018),
        body: Stack(children: [
          // ambient glow
          Positioned(
            top: MediaQuery.of(context).size.height * 0.22,
            left: MediaQuery.of(context).size.width * 0.5 - 120,
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 240, height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    dc.withValues(alpha: 0.05 + _pulseCtrl.value * 0.04),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),
          ),

          SafeArea(child: Column(children: [
            // ── top bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.07))),
                    child: Row(children: [
                      GestureDetector(
                        onTap: () => _showSubjectPicker(st.subject),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: sc.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: sc.withValues(alpha: 0.25))),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text(SubjectConfig.subjects[st.subject]?.emoji ?? '📚',
                              style: const TextStyle(fontSize: 13)),
                            const SizedBox(width: 5),
                            Text(st.subject, style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: sc)),
                            Icon(Icons.unfold_more_rounded, size: 13, color: sc.withValues(alpha: 0.5)),
                          ]),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10)),
                        child: Text('순공 ${st.effectiveTimeFormatted}', style: const TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF10B981),
                          fontFeatures: [FontFeature.tabularFigures()])),
                      ),
                    ]),
                  ),
                ),
              ),
            ),

            // ── stats strip ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.05))),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      _imStat('📖', '${st.totalStudyMin}m'),
                      _imDiv(),
                      _imStat('🎧', '${st.totalLectureMin}m'),
                      _imDiv(),
                      _imStat('☕', '${st.totalRestMin}m'),
                      _imDiv(),
                      _imStat('⏱️', st.sessionTimeFormatted),
                    ]),
                  ),
                ),
              ),
            ),

            // ── center hourglass ──
            Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (_, __) {
                  final op = isRest ? 0.4 + _pulseCtrl.value * 0.6 : 0.7 + _pulseCtrl.value * 0.3;
                  return Text('$mE $mL', style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: dc.withValues(alpha: op), letterSpacing: 2));
                },
              ),
              const SizedBox(height: 18),
              SizedBox(width: 220, height: 300, child: Stack(alignment: Alignment.center, children: [
                // ambient glow behind hourglass
                if (!isRest) AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(width: 200, height: 200,
                    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                      BoxShadow(color: sc.withValues(alpha: 0.06 + _pulseCtrl.value * 0.04),
                        blurRadius: 50, spreadRadius: 15),
                    ])),
                ),
                AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => CustomPaint(
                    size: const Size(220, 300),
                    painter: _HourglassPainter(
                      progress: st.cycleProgress,
                      color: dc,
                      pulse: _pulseCtrl.value,
                    ),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(st.mainTimerFormatted, style: const TextStyle(
                    fontSize: 44, fontWeight: FontWeight.w200, color: Colors.white,
                    letterSpacing: -1, fontFamily: 'monospace',
                    fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 4),
                  Text('seg ${st.segmentTimeFormatted}', style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.25),
                    fontFamily: 'monospace', fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ])),
              const SizedBox(height: 12),
              // ── cycle info + collected hourglasses ──
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: dc.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                  child: Text('사이클 ${st.cycleCount + 1}', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w600, color: dc.withValues(alpha: 0.7))),
                ),
                const SizedBox(width: 10),
                Text('${(st.cycleProgress * 90).round()}/90분', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.3),
                  fontFeatures: const [FontFeature.tabularFigures()])),
              ]),
              if (st.cycleCount > 0) ...[
                const SizedBox(height: 8),
                // mini hourglasses — one per completed cycle
                Row(mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    st.cycleCount.clamp(0, 8),
                    (i) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Icon(Icons.hourglass_bottom_rounded,
                        size: 14, color: dc.withValues(alpha: 0.5 + i * 0.05)),
                    ),
                  ),
                ),
              ],
            ]))),

            // ── cycle bar ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: st.cycleProgress.clamp(0.0, 1.0), minHeight: 3,
                  backgroundColor: Colors.white.withValues(alpha: 0.05),
                  valueColor: AlwaysStoppedAnimation(dc.withValues(alpha: 0.55)))),
            ),
            const SizedBox(height: 10),

            // ── bottom controls ──
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                _imModeBtn('📖', '공부', 'study', sc, st.mode),
                const SizedBox(width: 6),
                _imModeBtn('🎧', '강의', 'lecture', const Color(0xFF3B7A57), st.mode),
                const SizedBox(width: 6),
                _imModeBtn('☕', '휴식', 'rest', Colors.orange, st.mode),
                const SizedBox(width: 6),
                _imActionBtn(Icons.lock_rounded, const Color(0xFF8B5CF6), _lockScreen),
                const SizedBox(width: 6),
                _imActionBtn(Icons.dashboard_rounded, Colors.blueAccent, _goToDashboard, onLongPress: _minimizeToHome),
                const SizedBox(width: 6),
                _imActionBtn(Icons.stop_rounded, Colors.redAccent, _confirmEnd, size: 24),
              ]),
            ),
            const SizedBox(height: 22),
          ])),

        ]),
      ),
    );
  }

  Widget _imStat(String e, String v) => Text('$e $v', style: TextStyle(
    fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.6),
    fontFeatures: const [FontFeature.tabularFigures()]));
  Widget _imDiv() => Container(width: 1, height: 20, color: Colors.white.withValues(alpha: 0.05));

  Widget _imModeBtn(String emoji, String label, String m, Color c, String cur) {
    final sel = cur == m;
    return Expanded(child: GestureDetector(
      onTap: sel ? null : () => _fs.switchMode(m),
      child: ClipRRect(borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: AnimatedContainer(duration: const Duration(milliseconds: 180), height: 48,
            decoration: BoxDecoration(
              color: sel ? c.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: sel ? Border.all(color: c.withValues(alpha: 0.45), width: 1.5)
                  : Border.all(color: Colors.white.withValues(alpha: 0.05))),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Text(emoji, style: const TextStyle(fontSize: 16)),
              Text(label, style: TextStyle(fontSize: 9, fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                color: sel ? c : Colors.white.withValues(alpha: 0.35))),
            ]))))));
  }


  Widget _imActionBtn(IconData icon, Color c, VoidCallback onTap, {double size = 22, VoidCallback? onLongPress}) {
    return GestureDetector(onTap: onTap, onLongPress: onLongPress,
      child: ClipRRect(borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Container(width: 48, height: 48,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.withValues(alpha: 0.22))),
            child: Icon(icon, color: c, size: size)))));
  }

  // ══════════════════════════════════════════
  //  Actions
  // ══════════════════════════════════════════

  void _confirmEnd() {
    final st = _fs.getCurrentState();
    showDialog(context: context, builder: (dCtx) => AlertDialog(
      backgroundColor: const Color(0xFF18181E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text('세션 종료', style: TextStyle(color: Colors.white, fontSize: 17)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _eRow('순공', st.effectiveTimeFormatted),
        _eRow('공부', '${st.totalStudyMin}분'),
        _eRow('강의', '${st.totalLectureMin}분'),
        _eRow('휴식', '${st.totalRestMin}분'),
        _eRow('세션', st.sessionTimeFormatted),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx),
          child: const Text('계속', style: TextStyle(color: Colors.white54))),
        TextButton(onPressed: () async {
          Navigator.pop(dCtx);
          final cycle = await _fs.endSession();
          _exitImmersive();
          _loadRecords();
          if (mounted) showFocusResultDialog(
            context: context, cycle: cycle, dk: _dk,
            textMain: _t1, textSub: _t2, textMuted: _t3);
        }, child: const Text('종료', style: TextStyle(
          color: Colors.redAccent, fontWeight: FontWeight.w700))),
      ],
    ));
  }

  Widget _eRow(String l, String v) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(fontSize: 12, color: Colors.white38)),
      Text(v, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white,
        fontFeatures: [FontFeature.tabularFigures()])),
    ]));


  void _showSubjectPicker(String cur) {
    showModalBottomSheet(context: context,
      backgroundColor: const Color(0xFF14141A),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 36, height: 4, decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8,
            children: SubjectConfig.subjects.entries.map((e) {
              final sel = cur == e.key;
              final c = BotanicalColors.subjectColor(e.key);
              return GestureDetector(
                onTap: () { if (!sel) _fs.changeSubject(e.key); if (context.mounted) Navigator.pop(context); },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? c.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: sel ? Border.all(color: c.withValues(alpha: 0.45), width: 1.5) : null),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text(e.value.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(e.key, style: TextStyle(fontSize: 13,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color: sel ? c : Colors.white.withValues(alpha: 0.65))),
                  ]),
                ),
              );
            }).toList()),
          const SizedBox(height: 14),
        ]),
      )));
  }

}

/// Hourglass timer painter — sand flows from top to bottom based on progress.
/// [progress] 0.0 = start (all sand top), 1.0 = done (all sand bottom).
/// [pulse] drives subtle sand-stream shimmer.
class _HourglassPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double pulse;
  _HourglassPainter({required this.progress, required this.color, required this.pulse});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final p = progress.clamp(0.0, 1.0);

    // Dimensions
    final glassTop = h * 0.08;
    final glassBot = h * 0.92;
    final neck = h * 0.50;
    final halfW = w * 0.36;
    final neckW = w * 0.035;
    final capH = h * 0.025;

    // ── Metal caps (top & bottom) — 3D beveled ──
    final capRect = RRect.fromRectAndRadius(
      Rect.fromLTRB(cx - halfW - 8, glassTop - capH, cx + halfW + 8, glassTop + capH),
      const Radius.circular(3),
    );
    final capRectBot = RRect.fromRectAndRadius(
      Rect.fromLTRB(cx - halfW - 8, glassBot - capH, cx + halfW + 8, glassBot + capH),
      const Radius.circular(3),
    );

    // Cap gradient (metallic)
    final capPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: 0.5),
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.4),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(capRect.outerRect);
    canvas.drawRRect(capRect, capPaint);
    canvas.drawRRect(capRectBot, capPaint);

    // Cap highlight
    canvas.drawRRect(capRect, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.15));
    canvas.drawRRect(capRectBot, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 0.8
      ..color = Colors.white.withValues(alpha: 0.15));

    // ── Glass body path ──
    Path _glassShape() => Path()
      ..moveTo(cx - halfW, glassTop + capH)
      ..cubicTo(cx - halfW, neck - h * 0.08, cx - neckW, neck - h * 0.03, cx - neckW, neck)
      ..cubicTo(cx - neckW, neck + h * 0.03, cx - halfW, neck + h * 0.08, cx - halfW, glassBot - capH)
      ..lineTo(cx + halfW, glassBot - capH)
      ..cubicTo(cx + halfW, neck + h * 0.08, cx + neckW, neck + h * 0.03, cx + neckW, neck)
      ..cubicTo(cx + neckW, neck - h * 0.03, cx + halfW, neck - h * 0.08, cx + halfW, glassTop + capH)
      ..close();

    final glassPath = _glassShape();

    // Glass fill — translucent with depth
    canvas.drawPath(glassPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft, end: Alignment.centerRight,
        colors: [
          color.withValues(alpha: 0.06),
          color.withValues(alpha: 0.02),
          Colors.white.withValues(alpha: 0.04),
          color.withValues(alpha: 0.06),
        ],
        stops: const [0.0, 0.3, 0.6, 1.0],
      ).createShader(Rect.fromLTRB(cx - halfW, glassTop, cx + halfW, glassBot)));

    // Glass outline
    canvas.drawPath(glassPath, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.18));

    // ── Glass reflection (left highlight strip) ──
    final reflPath = Path()
      ..moveTo(cx - halfW + 8, glassTop + capH + 10)
      ..cubicTo(cx - halfW + 8, neck - h * 0.06, cx - neckW + 6, neck - h * 0.02, cx - neckW + 5, neck)
      ..cubicTo(cx - neckW + 6, neck + h * 0.02, cx - halfW + 8, neck + h * 0.06, cx - halfW + 8, glassBot - capH - 10);
    canvas.drawPath(reflPath, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 3.0
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeCap = StrokeCap.round);

    // Clip to glass for sand rendering
    canvas.save();
    canvas.clipPath(glassPath);

    // ── Top sand ──
    final topSandFraction = 1.0 - p;
    if (topSandFraction > 0.01) {
      final topZone = neck - h * 0.03 - (glassTop + capH);
      final topSandH = topZone * topSandFraction;
      final sandTop = neck - h * 0.03 - topSandH;

      // Sand surface is slightly curved
      final topSandPath = Path()
        ..moveTo(cx - halfW - 2, sandTop)
        ..quadraticBezierTo(cx, sandTop + 4, cx + halfW + 2, sandTop)
        ..lineTo(cx + halfW + 2, neck - h * 0.03)
        ..lineTo(cx + neckW, neck)
        ..lineTo(cx - neckW, neck)
        ..lineTo(cx - halfW - 2, neck - h * 0.03)
        ..close();

      // Sand gradient (warm, layered)
      canvas.drawPath(topSandPath, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.55),
            color.withValues(alpha: 0.40),
            color.withValues(alpha: 0.60),
          ],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromLTRB(cx - halfW, sandTop, cx + halfW, neck)));

      // Surface highlight
      canvas.drawPath(
        Path()
          ..moveTo(cx - halfW * 0.7, sandTop + 1)
          ..quadraticBezierTo(cx, sandTop + 5, cx + halfW * 0.7, sandTop + 1),
        Paint()..style = PaintingStyle.stroke ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: 0.12));
    }

    // ── Bottom sand ──
    if (p > 0.01) {
      final botZone = (glassBot - capH) - (neck + h * 0.03);
      final botSandH = botZone * p;
      final sandTopY = glassBot - capH - botSandH;

      // Sand mound — dome shaped top
      final botSandPath = Path()
        ..moveTo(cx - halfW - 2, glassBot - capH)
        ..lineTo(cx + halfW + 2, glassBot - capH)
        ..lineTo(cx + halfW + 2, sandTopY + 8)
        ..quadraticBezierTo(cx, sandTopY - 6, cx - halfW - 2, sandTopY + 8)
        ..close();

      canvas.drawPath(botSandPath, Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0.50),
            color.withValues(alpha: 0.65),
            color.withValues(alpha: 0.55),
          ],
          stops: const [0.0, 0.7, 1.0],
        ).createShader(Rect.fromLTRB(cx - halfW, sandTopY, cx + halfW, glassBot)));

      // Mound highlight
      canvas.drawPath(
        Path()
          ..moveTo(cx - halfW * 0.5, sandTopY + 6)
          ..quadraticBezierTo(cx, sandTopY - 4, cx + halfW * 0.5, sandTopY + 6),
        Paint()..style = PaintingStyle.stroke ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.10));
    }

    // ── Sand stream ──
    if (p < 0.99 && topSandFraction > 0.01) {
      final streamTop = neck - 2;
      final botZone = (glassBot - capH) - (neck + h * 0.03);
      final botSandH = botZone * p;
      final streamBot = glassBot - capH - botSandH + 4;

      // Main stream
      canvas.drawLine(
        Offset(cx, streamTop), Offset(cx, streamBot),
        Paint()
          ..strokeWidth = 1.2 + pulse * 0.4
          ..color = color.withValues(alpha: 0.45 + pulse * 0.15)
          ..strokeCap = StrokeCap.round);

      // Splash particles at bottom
      final rng = (progress * 1000).toInt();
      for (int i = 0; i < 6; i++) {
        final seed = (rng + i * 31 + (pulse * 13).toInt()) % 100;
        final spread = (seed % 11 - 5) * 1.8;
        final drop = (seed % 8) * 2.0;
        canvas.drawCircle(
          Offset(cx + spread, streamBot + drop),
          0.6 + (seed % 3) * 0.25,
          Paint()..color = color.withValues(alpha: 0.25 + (seed % 30) / 100.0),
        );
      }
    }

    canvas.restore();

    // ── Outer glass shine (right edge specular) ──
    final shinePath = Path()
      ..moveTo(cx + halfW - 6, glassTop + capH + 15)
      ..cubicTo(cx + halfW - 6, neck - h * 0.05, cx + neckW + 4, neck - h * 0.015, cx + neckW + 3, neck);
    canvas.drawPath(shinePath, Paint()
      ..style = PaintingStyle.stroke ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.06 + pulse * 0.03)
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant _HourglassPainter old) =>
      old.progress != progress || old.color != color || old.pulse != pulse;
}
