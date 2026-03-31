import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
  late AnimationController _staggerCtrl;
  late AnimationController _heroCountCtrl;

  String _subj = '자료해석';
  String _mode = 'study';

  List<FocusCycle> _todaySessions = [];
  Map<String, int> _weeklyData = {};
  bool _recordsLoading = false;

  bool get _dk => Theme.of(context).brightness == Brightness.dark;

  // theme-aware colors — no hardcoding
  Color get _bg => _dk ? const Color(0xFF111015) : const Color(0xFFF6F4F0);
  Color get _card => _dk ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.65);
  Color get _cardBorder => _dk ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04);
  Color get _t1 => _dk ? const Color(0xFFF2ECE4) : const Color(0xFF1A1714);
  Color get _t2 => _dk ? const Color(0xFFB8A898) : const Color(0xFF5C5048);
  Color get _t3 => _dk ? const Color(0xFF7A6E62) : const Color(0xFF9A8E82);
  Color get _accent => BotanicalColors.subjectColor(_subj);

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
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _staggerCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..forward();
    _heroCountCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..forward();
    if (_fs.isRunning) {
      final st = _fs.getCurrentState();
      _subj = st.subject;
      _mode = st.mode;
      _enterImmersive();
    }
    SubjectConfig.load();

    _todaySessions = _fs.todaySessions;
    _loadRecords();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _staggerCtrl.dispose();
    _heroCountCtrl.dispose();
    _exitImmersive();
    super.dispose();
  }

  void _enterImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  void _exitImmersive() =>
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  static const _focusCh = MethodChannel('com.cheonhong.cheonhong_studio/focus_mode');

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
    _safeSetState(() => _recordsLoading = true);
    try {
      final w = await _fs.getWeeklyStudyMinutes();
      await _fs.refreshTodaySessions();
      _safeSetState(() {
        _weeklyData = w;
        _todaySessions = _fs.todaySessions;
        _recordsLoading = false;
      });
    } catch (_) {
      _safeSetState(() => _recordsLoading = false);
    }
  }

  // ── glass card ──
  Widget _frost({
    required Widget child,
    double blur = 16,
    double radius = 24,
    EdgeInsets padding = const EdgeInsets.all(20),
    Color? borderColor,
    Color? fillColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: fillColor ?? _card,
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: borderColor ?? _cardBorder),
          ),
          child: child,
        ),
      ),
    );
  }

  // ── stagger helpers ──
  Widget _stagger(int i, Widget child) {
    final begin = (i * 0.10).clamp(0.0, 0.6);
    final end = (begin + 0.5).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _staggerCtrl,
      curve: Interval(begin, end, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, __) {
        final v = anim.value;
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 24 * (1 - v)), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _fs,
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

  Widget _secLabel(String t) => Padding(
    padding: const EdgeInsets.only(left: 2),
    child: Text(t, style: TextStyle(
      fontSize: 10, fontWeight: FontWeight.w800,
      color: _t3.withValues(alpha: 0.55), letterSpacing: 2.5)),
  );

  Widget _modeChip(String emoji, String label, String desc, String m) {
    final sel = _mode == m;
    final c = m == 'study' ? const Color(0xFF6366F1) : BotanicalColors.subjectData;
    return GestureDetector(
      onTap: () => setState(() => _mode = m),
      child: _frost(
        blur: sel ? 14 : 8,
        radius: 16,
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
        borderColor: sel ? c.withValues(alpha: 0.35) : _cardBorder,
        fillColor: sel ? c.withValues(alpha: _dk ? 0.10 : 0.05) : _card,
        child: Row(children: [
          Text(emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700, color: sel ? c : _t1)),
            Text(desc, style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w500, color: _t3)),
          ]),
          const Spacer(),
          if (sel) Container(width: 7, height: 7, decoration: BoxDecoration(
            shape: BoxShape.circle, color: c,
            boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 6)])),
        ]),
      ),
    );
  }

  Widget _startButton() {
    return GestureDetector(
      onTap: _start,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _accent.withValues(alpha: _dk ? 0.18 : 0.12),
                  _accent.withValues(alpha: _dk ? 0.08 : 0.04),
                ],
                begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _accent.withValues(alpha: 0.25)),
              boxShadow: [
                BoxShadow(color: _accent.withValues(alpha: 0.08), blurRadius: 20, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 34, height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _accent.withValues(alpha: 0.22),
                  boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.15), blurRadius: 12)]),
                child: Icon(Icons.play_arrow_rounded, size: 22, color: _accent),
              ),
              const SizedBox(width: 10),
              Text('시작', style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
                color: _accent, letterSpacing: 0.5)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String emoji, int min) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _dk ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(7)),
      child: Text('$emoji ${min}m', style: TextStyle(
        fontSize: 9, fontWeight: FontWeight.w700, color: _t2,
        fontFeatures: const [FontFeature.tabularFigures()])),
    );
  }

  void _confirmDeleteSession(FocusCycle c) {
    showDialog(context: context, builder: (dCtx) => AlertDialog(
      backgroundColor: _dk ? const Color(0xFF18181E) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('삭제할까요?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _t1)),
      content: Text(
        '${c.subject} · ${_fmtTime(c.startTime)}~${c.endTime != null ? _fmtTime(c.endTime) : '...'} · 순공 ${c.effectiveMin}분',
        style: TextStyle(fontSize: 12, color: _t2)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx),
          child: Text('취소', style: TextStyle(color: _t3))),
        TextButton(onPressed: () async {
          Navigator.pop(dCtx);
          await _fs.deleteFocusCycle(c.date, c.id);
          _safeSetState(() {
            _todaySessions = _fs.todaySessions;
          });
        }, child: const Text('삭제', style: TextStyle(
          color: Colors.redAccent, fontWeight: FontWeight.w700))),
      ],
    ));
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
        backgroundColor: const Color(0xFF08080C),
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

            // ── center ring ──
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
              SizedBox(width: 240, height: 240, child: Stack(alignment: Alignment.center, children: [
                if (!isRest) AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (_, __) => Container(width: 240, height: 240,
                    decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
                      BoxShadow(color: sc.withValues(alpha: 0.07 + _pulseCtrl.value * 0.05),
                        blurRadius: 44, spreadRadius: 12),
                    ])),
                ),
                CustomPaint(size: const Size(240, 240),
                  painter: _RingPainter(progress: st.cycleProgress, color: dc)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(st.mainTimerFormatted, style: const TextStyle(
                    fontSize: 48, fontWeight: FontWeight.w200, color: Colors.white,
                    letterSpacing: -1, fontFamily: 'monospace',
                    fontFeatures: [FontFeature.tabularFigures()])),
                  const SizedBox(height: 4),
                  Text('seg ${st.segmentTimeFormatted}', style: TextStyle(
                    fontSize: 11, color: Colors.white.withValues(alpha: 0.25),
                    fontFamily: 'monospace', fontFeatures: const [FontFeature.tabularFigures()])),
                ]),
              ])),
              const SizedBox(height: 16),
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
                _imActionBtn(Icons.home_rounded, Colors.blueAccent, _minimizeToHome),
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


  Widget _imActionBtn(IconData icon, Color c, VoidCallback onTap, {double size = 22}) {
    return GestureDetector(onTap: onTap,
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

  Future<void> _start() async {
    await _fs.startSession(subject: _subj, mode: _mode);
    _enterImmersive();
  }

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

  static const _sColors = [
    0xFF6366F1,0xFF10B981,0xFFF59E0B,0xFFEF4444,0xFF3B82F6,
    0xFF8B5CF6,0xFFEC4899,0xFF14B8A6,0xFFF97316,0xFF06B6D4];

  void _editSubjectDlg(String old, SubjectInfo info, BuildContext ctx, StateSetter setBS) {
    final nc = TextEditingController(text: old);
    final ec = TextEditingController(text: info.emoji);
    int sc = info.colorValue;
    showDialog(context: ctx, builder: (dCtx) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('수정', style: TextStyle(fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nc, decoration: const InputDecoration(labelText: '과목명', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: ec, decoration: const InputDecoration(labelText: '이모지', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: _sColors.map((c) => GestureDetector(
          onTap: () => setD(() => sc = c),
          child: Container(width: 28, height: 28, decoration: BoxDecoration(
            color: Color(c), borderRadius: BorderRadius.circular(6),
            border: sc == c ? Border.all(color: Colors.white, width: 2.5) : null)),
        )).toList()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
        TextButton(onPressed: () async {
          final n = nc.text.trim(); final e = ec.text.trim();
          if (n.isEmpty) return;
          await SubjectConfig.updateSubject(old, n, e.isEmpty ? '📚' : e, sc);
          if (_subj == old) _subj = n;
          if (dCtx.mounted) Navigator.pop(dCtx);
          setBS(() {}); setState(() {});
        }, child: const Text('저장')),
      ])));
  }

  void _addSubjectDlg(BuildContext ctx, StateSetter setBS) {
    final nc = TextEditingController();
    final ec = TextEditingController(text: '📚');
    int sc = _sColors.first;
    showDialog(context: ctx, builder: (dCtx) => StatefulBuilder(builder: (_, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Text('추가', style: TextStyle(fontSize: 15)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nc, decoration: const InputDecoration(labelText: '과목명', hintText: '국어')),
        const SizedBox(height: 10),
        TextField(controller: ec, decoration: const InputDecoration(labelText: '이모지'),
          style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: _sColors.map((c) => GestureDetector(
          onTap: () => setD(() => sc = c),
          child: Container(width: 28, height: 28, decoration: BoxDecoration(
            color: Color(c), borderRadius: BorderRadius.circular(6),
            border: sc == c ? Border.all(color: Colors.white, width: 2.5) : null)),
        )).toList()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소')),
        TextButton(onPressed: () async {
          final n = nc.text.trim(); final e = ec.text.trim();
          if (n.isEmpty) return;
          await SubjectConfig.addSubject(n, e.isEmpty ? '📚' : e, sc);
          if (dCtx.mounted) Navigator.pop(dCtx);
          setBS(() {}); setState(() {});
        }, child: const Text('추가')),
      ])));
  }

  // ── helpers ──
  String _fmtMin(int m) {
    final h = m ~/ 60; final r = m % 60;
    if (h > 0 && r > 0) return '${h}h ${r}m';
    if (h > 0) return '${h}h';
    return '${r}m';
  }

  String _fmtTime(String? raw) {
    if (raw == null) return '--:--';
    if (raw.contains('T')) {
      try {
        final dt = DateTime.parse(raw);
        return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
      } catch (_) {}
    }
    if (raw.length >= 5 && raw.contains(':')) return raw.substring(0, 5);
    return raw;
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(4, 4, size.width - 8, size.height - 8);
    final p = Paint()..style = PaintingStyle.stroke..strokeWidth = 8..strokeCap = StrokeCap.round;
    p.color = color.withValues(alpha: 0.10);
    canvas.drawArc(rect, -pi / 2, 2 * pi, false, p);
    if (progress > 0) {
      p.shader = SweepGradient(
        colors: [color.withValues(alpha: 0.35), color],
        transform: const GradientRotation(-pi / 2),
      ).createShader(rect);
      canvas.drawArc(rect, -pi / 2, 2 * pi * progress.clamp(0.0, 1.0), false, p);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color;
}
