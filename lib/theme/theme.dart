// DAILY theme — BotanicalTheme warm cream 중심 계승
// STUDY 는 sage cool, DAILY 는 warm clay — 두 앱 시각 분리
import 'package:flutter/material.dart';

class DailyPalette {
  DailyPalette._();
  // BotanicalTheme 핵심 계승
  static const primary = Color(0xFF8B6F47);        // warm brown/clay
  static const primaryLight = Color(0xFFA88868);
  static const primarySurface = Color(0xFFF3EBDD); // clay tint
  static const gold = Color(0xFFC8975B);           // warm sand
  static const goldSurface = Color(0xFFF7EFE0);
  static const cream = Color(0xFFFEF8EC);
  // 배경·surface
  static const paper = Color(0xFFFAF8F3);          // warm cream bg
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE8E2D4);           // warm border
  // 텍스트
  static const ink = Color(0xFF2C2A26);
  static const slate = Color(0xFF5E5A53);
  static const ash = Color(0xFF8A857C);
  static const fog = Color(0xFFB8B2A6);
  // 상태
  static const success = Color(0xFF7A8A6E);
  static const warn = Color(0xFFC8975B);
  static const error = Color(0xFFB05A5A);
  static const info = Color(0xFF6B8BA3);
  static const sleep = Color(0xFF6B5DAF);          // 수면 전용 포인트 (plum)
  static const craving = Color(0xFFB05A5A);        // 갈망 경고
}

class DailySpace {
  DailySpace._();
  static const double xs = 4, sm = 8, md = 12, lg = 16, xl = 20, xxl = 28;
  static const double radius = 10, radiusL = 14;
}

ThemeData buildDailyTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: DailyPalette.primary,
      primary: DailyPalette.primary,
      surface: DailyPalette.paper,
      onSurface: DailyPalette.ink,
    ),
    scaffoldBackgroundColor: DailyPalette.paper,
    textTheme: const TextTheme(
      titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: DailyPalette.ink, height: 1.25),
      titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: DailyPalette.ink),
      bodyLarge: TextStyle(fontSize: 14, color: DailyPalette.ink, height: 1.4),
      bodyMedium: TextStyle(fontSize: 13, color: DailyPalette.slate, height: 1.4),
      labelSmall: TextStyle(fontSize: 11, color: DailyPalette.ash, letterSpacing: 0.2),
    ),
    cardTheme: const CardThemeData(
      color: DailyPalette.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
  );
}
