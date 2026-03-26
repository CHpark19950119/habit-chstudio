import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 종이 질감 배경 페인터
class PaperGrainPainter extends CustomPainter {
  final bool dark;
  PaperGrainPainter(this.dark);
  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    final paint = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.012)
      ..strokeWidth = 0.5;
    for (int i = 0; i < 800; i++) {
      canvas.drawCircle(
        Offset(rand.nextDouble() * size.width, rand.nextDouble() * size.height),
        rand.nextDouble() * 1.2, paint);
    }
  }
  @override
  bool shouldRepaint(covariant PaperGrainPainter old) => old.dark != dark;
}

/// ═══════════════════════════════════════════════════
///  Water Wave Painter — 캘린더 셀 워터탱크 파도
///  진짜 물 느낌 그라디언트 웨이브 (v2)
/// ═══════════════════════════════════════════════════
class WaterWavePainter extends CustomPainter {
  final double fillPercent; // 0.0 ~ 1.0
  final double phase;       // 애니메이션 phase (0.0 ~ 1.0)
  final Color waterColor;
  final Color waveColor;

  WaterWavePainter({
    required this.fillPercent,
    required this.phase,
    this.waterColor = const Color(0xFF38BDF8),
    this.waveColor = const Color(0xFF38BDF8),
  });

  // 실제 물 색상 팔레트 (깊은 물 → 수면)
  static const _deepWater = Color(0xFF0C4A6E);   // 깊은 바다
  static const _midWater  = Color(0xFF0369A1);   // 중간 깊이
  static const _surfWater = Color(0xFF0EA5E9);   // 수면 근처
  static const _shallowWater = Color(0xFF38BDF8); // 얕은 물

  @override
  void paint(Canvas canvas, Size size) {
    if (fillPercent <= 0) return;

    final w = size.width;
    final h = size.height;
    final waterHeight = h * fillPercent.clamp(0.0, 0.92);
    final waterTop = h - waterHeight;
    final t = phase * math.pi * 2; // radian phase

    // 전체 셀 하단 클리핑 (둥근 모서리)
    canvas.save();
    canvas.clipRRect(RRect.fromLTRBAndCorners(
      0, 0, w, h,
      bottomLeft: const Radius.circular(11),
      bottomRight: const Radius.circular(11),
    ));

    // ── 1. 깊은 물 바디 (multi-stop 그라디언트) ──
    final bodyRect = Rect.fromLTWH(0, waterTop, w, waterHeight);
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          _surfWater.withValues(alpha: 0.30),
          _midWater.withValues(alpha: 0.45),
          _deepWater.withValues(alpha: 0.55),
          _deepWater.withValues(alpha: 0.65),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(bodyRect);
    canvas.drawRect(bodyRect, bodyPaint);

    // ── 2. 세 겹 웨이브 레이어 (뒤→앞, 각기 다른 색/속도) ──
    // 뒷 레이어: 느리고 넓은 파도 (깊은 색)
    _drawGradientWave(canvas, w, h, waterTop, t,
      amplitude: 3.5, frequency: 2.0, speed: 0.6,
      colorTop: _midWater.withValues(alpha: 0.25),
      colorBot: _deepWater.withValues(alpha: 0.40),
      subWaveAmp: 0.8, subWaveFreq: 5.0);

    // 중간 레이어: 중간 속도 (중간 색)
    _drawGradientWave(canvas, w, h, waterTop, t,
      amplitude: 2.8, frequency: 3.0, speed: 1.0,
      colorTop: _surfWater.withValues(alpha: 0.22),
      colorBot: _midWater.withValues(alpha: 0.38),
      subWaveAmp: 1.0, subWaveFreq: 7.0);

    // 앞 레이어: 빠르고 선명한 파도 (밝은 색)
    _drawGradientWave(canvas, w, h, waterTop, t,
      amplitude: 2.2, frequency: 3.5, speed: 1.6,
      colorTop: _shallowWater.withValues(alpha: 0.20),
      colorBot: _surfWater.withValues(alpha: 0.35),
      subWaveAmp: 0.6, subWaveFreq: 9.0);

    // ── 3. 수면 코스틱 (빛 반사) ──
    _drawCaustics(canvas, w, waterTop, t);

    // ── 4. 수면 스파클 (반짝이는 점) ──
    _drawSparkles(canvas, w, waterTop, t);

    // ── 5. 수면 하이라이트 라인 ──
    final hlPath = Path();
    hlPath.moveTo(0, waterTop);
    for (double x = 0; x <= w; x += 0.5) {
      final y = waterTop +
          math.sin(x / w * 3.5 * math.pi + t * 1.6) * 2.2 +
          math.sin(x / w * 7 * math.pi + t * 3) * 0.6;
      hlPath.lineTo(x, y);
    }
    canvas.drawPath(hlPath, Paint()
      ..color = Colors.white.withValues(alpha: 0.30)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.8));

    // ── 6. 깊이감 비네트 ──
    final vignetteRect = Rect.fromLTWH(0, h - waterHeight * 0.4, w, waterHeight * 0.4);
    canvas.drawRect(vignetteRect, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.transparent,
          _deepWater.withValues(alpha: 0.15),
        ],
      ).createShader(vignetteRect));

    canvas.restore();
  }

  /// 그라디언트 파도 레이어 — 주파도 + 서브파도 합성
  void _drawGradientWave(Canvas canvas, double w, double h,
      double waterTop, double t, {
    required double amplitude,
    required double frequency,
    required double speed,
    required Color colorTop,
    required Color colorBot,
    required double subWaveAmp,
    required double subWaveFreq,
  }) {
    final path = Path();
    path.moveTo(0, h);
    for (double x = 0; x <= w; x += 1) {
      final nx = x / w;
      final y = waterTop +
          math.sin(nx * frequency * math.pi + t * speed) * amplitude +
          math.sin(nx * subWaveFreq * math.pi + t * speed * 2.5) * subWaveAmp;
      path.lineTo(x, y);
    }
    path.lineTo(w, h);
    path.close();

    final waveRect = Rect.fromLTWH(0, waterTop - amplitude, w, h - waterTop + amplitude);
    canvas.drawPath(path, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [colorTop, colorBot],
      ).createShader(waveRect));
  }

  /// 수면 코스틱 (물속 빛 무늬)
  void _drawCaustics(Canvas canvas, double w, double waterTop, double t) {
    final rand = math.Random(7);
    for (int i = 0; i < 5; i++) {
      final baseX = rand.nextDouble() * w;
      final baseY = waterTop + 6 + rand.nextDouble() * 20;
      final cx = baseX + math.sin(t * 0.8 + i * 1.7) * 6;
      final cy = baseY + math.cos(t * 0.6 + i * 2.3) * 3;
      final r = 4.0 + rand.nextDouble() * 6;
      final opacity = (math.sin(t * 1.2 + i * 1.1) * 0.5 + 0.5) * 0.08;

      canvas.drawOval(
        Rect.fromCenter(center: Offset(cx, cy), width: r * 2, height: r),
        Paint()
          ..color = Colors.white.withValues(alpha: opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  /// 수면 위 스파클 (반짝임)
  void _drawSparkles(Canvas canvas, double w, double waterTop, double t) {
    for (int s = 0; s < 4; s++) {
      final sx = w * (0.12 + s * 0.24) + math.sin(t + s * 1.5) * 4;
      final sy = waterTop +
          math.sin(sx / w * 3 * math.pi + t * 1.8) * 2.5 + 1;
      final sparkleAlpha = (math.sin(t * 3.5 + s * 2.2) * 0.35 + 0.35)
          .clamp(0.0, 0.6);
      if (sparkleAlpha < 0.05) continue;

      canvas.drawCircle(
        Offset(sx, sy), 1.2,
        Paint()
          ..color = Colors.white.withValues(alpha: sparkleAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaterWavePainter old) =>
      old.fillPercent != fillPercent || old.phase != phase;
}

