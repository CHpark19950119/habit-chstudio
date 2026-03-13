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
      ..color = (dark ? Colors.white : Colors.black).withOpacity(0.012)
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

/// Cyber Grid 배경 페인터 — 홈스크린 등에서 사용
class CyberGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.025)
      ..strokeWidth = 0.5;
    const gap = 18.0;
    for (double x = 0; x < size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
          _surfWater.withOpacity(0.30),
          _midWater.withOpacity(0.45),
          _deepWater.withOpacity(0.55),
          _deepWater.withOpacity(0.65),
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(bodyRect);
    canvas.drawRect(bodyRect, bodyPaint);

    // ── 2. 세 겹 웨이브 레이어 (뒤→앞, 각기 다른 색/속도) ──
    // 뒷 레이어: 느리고 넓은 파도 (깊은 색)
    _drawGradientWave(canvas, w, h, waterTop, t,
      amplitude: 3.5, frequency: 2.0, speed: 0.6,
      colorTop: _midWater.withOpacity(0.25),
      colorBot: _deepWater.withOpacity(0.40),
      subWaveAmp: 0.8, subWaveFreq: 5.0);

    // 중간 레이어: 중간 속도 (중간 색)
    _drawGradientWave(canvas, w, h, waterTop, t,
      amplitude: 2.8, frequency: 3.0, speed: 1.0,
      colorTop: _surfWater.withOpacity(0.22),
      colorBot: _midWater.withOpacity(0.38),
      subWaveAmp: 1.0, subWaveFreq: 7.0);

    // 앞 레이어: 빠르고 선명한 파도 (밝은 색)
    _drawGradientWave(canvas, w, h, waterTop, t,
      amplitude: 2.2, frequency: 3.5, speed: 1.6,
      colorTop: _shallowWater.withOpacity(0.20),
      colorBot: _surfWater.withOpacity(0.35),
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
      ..color = Colors.white.withOpacity(0.30)
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
          _deepWater.withOpacity(0.15),
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
          ..color = Colors.white.withOpacity(opacity)
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
          ..color = Colors.white.withOpacity(sparkleAlpha)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
      );
    }
  }

  @override
  bool shouldRepaint(covariant WaterWavePainter old) =>
      old.fillPercent != fillPercent || old.phase != phase;
}

/// ═══════════════════════════════════════════════════
///  24시간 타임라인 그리드 페인터
/// ═══════════════════════════════════════════════════
class TimelineGridPainter extends CustomPainter {
  final int startHour;
  final int endHour;
  final double rowHeight;
  final Color lineColor;
  final Color textColor;

  TimelineGridPainter({
    required this.startHour,
    required this.endHour,
    required this.rowHeight,
    this.lineColor = const Color(0x15000000),
    this.textColor = const Color(0x60000000),
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;

    final dashPaint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5;

    for (int h = startHour; h <= endHour; h++) {
      final y = (h - startHour) * rowHeight;
      final isPeriod = h % 6 == 0;

      if (isPeriod) {
        canvas.drawLine(Offset(44, y), Offset(size.width, y),
          linePaint..strokeWidth = 1.5..color = lineColor.withOpacity(0.3));
      } else {
        double x = 44;
        while (x < size.width) {
          canvas.drawLine(Offset(x, y), Offset(x + 4, y), dashPaint);
          x += 8;
        }
      }

      final tp = TextPainter(
        text: TextSpan(
          text: h.toString().padLeft(2, '0'),
          style: TextStyle(
            fontSize: 10,
            fontWeight: isPeriod ? FontWeight.w700 : FontWeight.w500,
            color: isPeriod ? textColor.withOpacity(0.8) : textColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(34 - tp.width, y - tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(covariant TimelineGridPainter old) => false;
}


// ═══════════════════════════════════════════════════════════════
//  ★ 작업4: 홈 대시보드 모션 이펙트용 페인터
// ═══════════════════════════════════════════════════════════════


/// ── A) Breathing Glow (숨쉬는 발광) ──
/// D-Day 카드 외곽에 부드러운 빛 파동 효과
class BreathingGlowPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final Color glowColor;
  final double borderRadius;

  BreathingGlowPainter({
    required this.progress,
    required this.glowColor,
    this.borderRadius = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final intensity = (math.sin(progress * math.pi * 2) + 1) / 2; // 0~1 oscillation
    final maxSpread = 12.0;
    final spread = maxSpread * intensity;

    for (int i = 3; i >= 0; i--) {
      final layerSpread = spread * (i / 3.0);
      final opacity = (0.08 * intensity * (1 - i / 4.0)).clamp(0.0, 0.15);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(-layerSpread, -layerSpread,
          size.width + layerSpread * 2, size.height + layerSpread * 2),
        Radius.circular(borderRadius + layerSpread));
      canvas.drawRRect(rrect, Paint()
        ..color = glowColor.withOpacity(opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 + layerSpread));
    }
  }

  @override
  bool shouldRepaint(covariant BreathingGlowPainter old) =>
      old.progress != progress || old.glowColor != glowColor;
}


/// ── B) Floating Particles (떠다니는 입자) ──
/// 보태니컬 분위기의 배경 파티클
class FloatingParticlesPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0 (반복)
  final List<Color> particleColors;
  final int count;

  FloatingParticlesPainter({
    required this.progress,
    this.particleColors = const [Color(0xFFFBBF24), Color(0xFF6EE7B7)],
    this.count = 7,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rand = math.Random(42);
    for (int i = 0; i < count; i++) {
      final baseX = rand.nextDouble() * size.width;
      final speed = 0.6 + rand.nextDouble() * 0.4;
      final phase = (progress * speed + i * 0.13) % 1.0;

      // 위로 올라가는 Y 계산
      final y = size.height * (1.0 - phase);
      final x = baseX + math.sin(phase * math.pi * 3 + i) * 15;

      // 투명도: 중간에 가장 밝고 양 끝에서 사라짐
      final fadeCurve = math.sin(phase * math.pi);
      final opacity = (0.35 * fadeCurve).clamp(0.0, 0.4);
      if (opacity < 0.02) continue;

      final radius = 2.0 + rand.nextDouble() * 2.5;
      final color = particleColors[i % particleColors.length].withOpacity(opacity);

      canvas.drawCircle(Offset(x, y), radius, Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
    }
  }

  @override
  bool shouldRepaint(covariant FloatingParticlesPainter old) =>
      old.progress != progress;
}


/// ── C) Morphing Blob (변형 블롭) ──
/// "이 디자인은 꼭 사용할것" — blob morph 애니메이션 재현
class MorphingBlobPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0 (8초 주기)
  final Color blobColor;
  final Color? secondaryColor;

  MorphingBlobPainter({
    required this.progress,
    required this.blobColor,
    this.secondaryColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final baseR = math.min(cx, cy) * 0.85;

    // 8개 제어점으로 blob 형태 생성
    final path = Path();
    final points = <Offset>[];
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * math.pi * 2;
      final wobble = math.sin(progress * math.pi * 2 + i * 0.9) * baseR * 0.15;
      final r = baseR + wobble;
      points.add(Offset(cx + math.cos(angle) * r, cy + math.sin(angle) * r));
    }

    // Catmull-Rom 스플라인으로 부드러운 blob
    path.moveTo(points[0].dx, points[0].dy);
    for (int i = 0; i < points.length; i++) {
      final p0 = points[(i - 1 + points.length) % points.length];
      final p1 = points[i];
      final p2 = points[(i + 1) % points.length];
      final p3 = points[(i + 2) % points.length];

      final cp1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6,
        p1.dy + (p2.dy - p0.dy) / 6,
      );
      final cp2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6,
        p2.dy - (p3.dy - p1.dy) / 6,
      );
      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p2.dx, p2.dy);
    }
    path.close();

    // 그라디언트 채우기
    final gradient = RadialGradient(
      center: Alignment(
        -0.2 + math.sin(progress * math.pi * 2) * 0.3,
        -0.3 + math.cos(progress * math.pi * 2) * 0.2,
      ),
      radius: 1.0,
      colors: [
        blobColor.withOpacity(0.5),
        (secondaryColor ?? blobColor).withOpacity(0.3),
      ],
    );

    canvas.drawPath(path, Paint()
      ..shader = gradient.createShader(
        Rect.fromCircle(center: Offset(cx, cy), radius: baseR)));

    // 내부 하이라이트
    canvas.drawPath(path, Paint()
      ..color = Colors.white.withOpacity(0.06)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20));
  }

  @override
  bool shouldRepaint(covariant MorphingBlobPainter old) =>
      old.progress != progress;
}


/// ── D) Shimmer Scan Line (스캔 라인) ──
/// 카드 위 반투명 하이라이트 스윕 효과
class ShimmerScanPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final double borderRadius;

  ShimmerScanPainter({
    required this.progress,
    this.borderRadius = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 카드 영역 클리핑
    canvas.clipRRect(RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(borderRadius)));

    // 좌→우 스캔 라인
    final scanX = -size.width * 0.3 + progress * (size.width * 1.6);
    final scanWidth = size.width * 0.3;

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.06),
          Colors.white.withOpacity(0.12),
          Colors.white.withOpacity(0.06),
          Colors.transparent,
        ],
        stops: const [0.0, 0.3, 0.5, 0.7, 1.0],
      ).createShader(Rect.fromLTWH(scanX, 0, scanWidth, size.height));

    canvas.drawRect(
      Rect.fromLTWH(scanX, 0, scanWidth, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant ShimmerScanPainter old) =>
      old.progress != progress;
}


/// ── F) Pulse Ring (펄스 링) ──
/// 포커스 진행 시 동심원 확산 효과
class PulseRingPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final Color ringColor;
  final int ringCount;

  PulseRingPainter({
    required this.progress,
    required this.ringColor,
    this.ringCount = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final maxR = math.min(cx, cy);

    for (int i = 0; i < ringCount; i++) {
      final ringPhase = (progress + i / ringCount) % 1.0;
      final r = maxR * 0.3 + maxR * 0.7 * ringPhase;
      final opacity = (1.0 - ringPhase) * 0.3;
      if (opacity < 0.01) continue;

      canvas.drawCircle(
        Offset(cx, cy), r,
        Paint()
          ..color = ringColor.withOpacity(opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0 * (1.0 - ringPhase));
    }
  }

  @override
  bool shouldRepaint(covariant PulseRingPainter old) =>
      old.progress != progress;
}