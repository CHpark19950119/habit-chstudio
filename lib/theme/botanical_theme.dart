import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ═══════════════════════════════════════════════════════════
/// CHEONHONG STUDIO — Studio Theme v10
/// ═══════════════════════════════════════════════════════════
///
/// 컨셉: 전문적 · 밀도 높음 · 캐주얼 · 모던
/// Light: 쿨 화이트 + 슬레이트 텍스트 + 인디고 액센트
/// Dark: 다크 슬레이트 + 크림 텍스트 + 바이올렛 액센트

class BotanicalColors {
  BotanicalColors._();

  // ─── Primary: 인디고 (전문적 + 신뢰감) ───
  static const primary = Color(0xFF4F46E5);
  static const primaryLight = Color(0xFF6366F1);
  static const primaryMuted = Color(0xFF818CF8);
  static const primarySurface = Color(0xFFEEF2FF);

  // ─── Accent: 앰버 (포인트 + 주의) ───
  static const gold = Color(0xFFF59E0B);
  static const goldLight = Color(0xFFFBBF24);
  static const goldMuted = Color(0xFFFDE68A);
  static const goldSurface = Color(0xFFFFFBEB);

  // ─── Light Mode: 쿨 화이트 ───
  static const scaffoldLight = Color(0xFFF8FAFC);    // 쿨 화이트
  static const cardLight = Color(0xFFFFFFFF);         // 순백
  static const surfaceLight = Color(0xFFF1F5F9);     // 슬레이트 50
  static const borderLight = Color(0xFFE2E8F0);      // 슬레이트 200
  static const textMain = Color(0xFF0F172A);          // 슬레이트 900
  static const textSub = Color(0xFF475569);           // 슬레이트 600
  static const textMuted = Color(0xFF94A3B8);         // 슬레이트 400
  static const textHint = Color(0xFFCBD5E1);          // 슬레이트 300

  // ─── Dark Mode: 다크 슬레이트 ───
  static const scaffoldDark = Color(0xFF0F172A);      // 슬레이트 900
  static const cardDark = Color(0xFF1E293B);          // 슬레이트 800
  static const surfaceDark = Color(0xFF334155);       // 슬레이트 700
  static const borderDark = Color(0xFF475569);        // 슬레이트 600
  static const textMainDark = Color(0xFFF1F5F9);     // 슬레이트 100
  static const textSubDark = Color(0xFFCBD5E1);      // 슬레이트 300
  static const textMutedDark = Color(0xFF94A3B8);    // 슬레이트 400
  static const lanternGold = Color(0xFF818CF8);       // 인디고 라이트 (다크 액센트)

  // ─── 과목 컬러 (선명하고 구분력 있는 톤) ───
  // 1차 PSAT
  static const subjectData = Color(0xFF10B981);       // 자료해석: 에메랄드
  static const subjectVerbal = Color(0xFF6366F1);     // 언어논리: 인디고
  static const subjectSituation = Color(0xFFF59E0B);  // 상황판단: 앰버
  // 2차 전공
  static const subjectEcon = Color(0xFF06B6D4);       // 경제학: 시안
  static const subjectIntlLaw = Color(0xFF8B5CF6);    // 국제법: 바이올렛
  static const subjectIntlPol = Color(0xFF059669);    // 국제정치학: 에메랄드 다크
  // 공통
  static const subjectConst = Color(0xFFEC4899);      // 헌법: 핑크
  static const subjectEnglish = Color(0xFF0EA5E9);    // 영어: 스카이 블루

  // ─── 시맨틱 ───
  static const success = Color(0xFF10B981);
  static const warning = Color(0xFFF59E0B);
  static const error = Color(0xFFEF4444);
  static const info = Color(0xFF3B82F6);

  // ─── 등급 컬러 ───
  static const gradeSPlus = Color(0xFFF59E0B);        // 앰버
  static const gradeS = Color(0xFF4F46E5);
  static const gradeA = Color(0xFF10B981);
  static const gradeB = Color(0xFF3B82F6);
  static const gradeC = Color(0xFFF59E0B);
  static const gradeD = Color(0xFFEF4444);
  static const gradeF = Color(0xFF94A3B8);

  static Color subjectColor(String subject) {
    switch (subject) {
      case '자료해석': return subjectData;
      case '언어논리': return subjectVerbal;
      case '상황판단': return subjectSituation;
      case '경제학': return subjectEcon;
      case '국제법': return subjectIntlLaw;
      case '국제정치학': return subjectIntlPol;
      case '헌법': return subjectConst;
      case '영어': return subjectEnglish;
      default: return primaryMuted;
    }
  }

  /// 시험 라운드별 대표 컬러
  static Color examRoundColor(String round) {
    switch (round) {
      case '1차': return const Color(0xFF3B6BA5); // 블루 계열
      case '2차': return const Color(0xFF7A5195); // 퍼플 계열
      default: return primaryMuted;
    }
  }

  static Color gradeColor(String grade) {
    switch (grade) {
      case 'S+': return gradeSPlus;
      case 'S': return gradeS;
      case 'A': return gradeA;
      case 'B': return gradeB;
      case 'C': return gradeC;
      case 'D': return gradeD;
      default: return gradeF;
    }
  }

  static List<Color> weatherGradient(String main) {
    switch (main.toLowerCase()) {
      case 'clear': return [const Color(0xFF3B82F6), const Color(0xFF60A5FA)];
      case 'clouds': return [const Color(0xFF64748B), const Color(0xFF94A3B8)];
      case 'rain': case 'drizzle': return [const Color(0xFF475569), const Color(0xFF64748B)];
      case 'thunderstorm': return [const Color(0xFF1E293B), const Color(0xFF334155)];
      case 'snow': return [const Color(0xFFCBD5E1), const Color(0xFFE2E8F0)];
      default: return [const Color(0xFF3B82F6), const Color(0xFF60A5FA)];
    }
  }
}

// ═══════════════════════════════════════════════════════════
// Spacing & Radius
// ═══════════════════════════════════════════════════════════

class BotanicalSpacing {
  BotanicalSpacing._();

  // ─── Border Radius ───
  static const double radiusXs = 4;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;

  static final borderRadiusXs = BorderRadius.circular(radiusXs);
  static final borderRadiusSm = BorderRadius.circular(radiusSm);
  static final borderRadiusMd = BorderRadius.circular(radiusMd);
  static final borderRadiusLg = BorderRadius.circular(radiusLg);
  static final borderRadiusXl = BorderRadius.circular(radiusXl);

  // ─── Padding ───
  static const double padXs = 4;
  static const double padSm = 8;
  static const double padMd = 12;
  static const double padLg = 16;
  static const double padXl = 20;
  static const double padXxl = 24;

  // ─── Gap (between items) ───
  static const double gapXs = 4;
  static const double gapSm = 8;
  static const double gapMd = 12;
  static const double gapLg = 16;
  static const double gapXl = 20;

  // ─── Helpers ───
  static const hGapXs = SizedBox(width: 4);
  static const hGapSm = SizedBox(width: 8);
  static const hGapMd = SizedBox(width: 12);
  static const hGapLg = SizedBox(width: 16);
  static const vGapXs = SizedBox(height: 4);
  static const vGapSm = SizedBox(height: 8);
  static const vGapMd = SizedBox(height: 12);
  static const vGapLg = SizedBox(height: 16);
  static const vGapXl = SizedBox(height: 20);
}

// ═══════════════════════════════════════════════════════════
// Typography
// ═══════════════════════════════════════════════════════════

class BotanicalTypo {
  BotanicalTypo._();

  static TextStyle heading({
    double size = 17,
    FontWeight weight = FontWeight.w700,
    Color? color,
  }) => GoogleFonts.notoSansKr(
    fontSize: size, fontWeight: weight,
    color: color ?? BotanicalColors.textMain,
    height: 1.3,
  );

  static TextStyle body({
    double size = 14,
    FontWeight weight = FontWeight.w500,
    Color? color,
  }) => GoogleFonts.notoSansKr(
    fontSize: size, fontWeight: weight,
    color: color ?? BotanicalColors.textMain,
    height: 1.4,
  );

  static TextStyle label({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double? letterSpacing,
  }) => GoogleFonts.notoSansKr(
    fontSize: size, fontWeight: weight,
    color: color ?? BotanicalColors.textSub,
    letterSpacing: letterSpacing,
    height: 1.3,
  );

  static TextStyle number({
    double size = 48,
    FontWeight weight = FontWeight.w300,
    Color? color,
  }) => GoogleFonts.notoSansKr(
    fontSize: size, fontWeight: weight,
    color: color ?? BotanicalColors.textMain,
    height: 1.1,
  );

  static TextStyle brand({double size = 12, Color? color}) =>
      GoogleFonts.notoSansKr(
        fontSize: size, fontWeight: FontWeight.w800,
        letterSpacing: 2,
        color: color ?? BotanicalColors.primary,
      );
}

// ═══════════════════════════════════════════════════════════
// Component Decorations
// ═══════════════════════════════════════════════════════════

class BotanicalDeco {
  BotanicalDeco._();

  /// 기본 카드 — 깔끔한 보더 + 미묘한 그림자
  static BoxDecoration card(bool dark, {Color? color, double radius = 12}) =>
      BoxDecoration(
        color: color ?? (dark ? BotanicalColors.cardDark : BotanicalColors.cardLight),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark
            ? BotanicalColors.borderDark.withValues(alpha: 0.4)
            : BotanicalColors.borderLight,
          width: 1,
        ),
        boxShadow: dark
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 8, offset: const Offset(0, 2)),
            ]
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8, offset: const Offset(0, 2)),
            ],
      );

  /// 서재 다크 카드
  static BoxDecoration libraryCard({double radius = 12}) => BoxDecoration(
    color: BotanicalColors.cardDark,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: BotanicalColors.borderDark.withValues(alpha: 0.5)),
    boxShadow: [
      BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 2)),
    ],
  );

  static BoxDecoration iconBox(Color color, bool dark, {double radius = 14}) =>
      BoxDecoration(
        color: color.withValues(alpha: dark ? 0.15 : 0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: 0.1), width: 0.5),
      );

  static BoxDecoration badge(Color color, {double radius = 20}) => BoxDecoration(
    color: color.withValues(alpha: 0.1),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: color.withValues(alpha: 0.2)),
  );

  static BoxDecoration selectedChip(Color color, bool dark, {double radius = 14}) =>
      BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color, width: 1.5),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.15), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      );

  static BoxDecoration unselectedChip(bool dark, {double radius = 14}) =>
      BoxDecoration(
        color: dark ? BotanicalColors.surfaceDark : BotanicalColors.cardLight,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: dark ? BotanicalColors.borderDark : BotanicalColors.borderLight),
      );

  static BoxDecoration innerInfo(bool dark, {double radius = 16}) => BoxDecoration(
    color: dark ? BotanicalColors.surfaceDark : BotanicalColors.surfaceLight,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: dark ? BotanicalColors.borderDark : BotanicalColors.borderLight, width: 0.5),
  );

  /// ★ 글래스 카드
  static BoxDecoration warmGlass(bool dark, {double radius = 12}) => BoxDecoration(
    color: dark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.7),
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(
      color: dark ? BotanicalColors.borderDark.withValues(alpha: 0.3) : BotanicalColors.borderLight.withValues(alpha: 0.5)),
    boxShadow: [BoxShadow(
      color: Colors.black.withValues(alpha: dark ? 0.1 : 0.03),
      blurRadius: 8, offset: const Offset(0, 2))],
  );
}

// ═══════════════════════════════════════════════════════════
// 성장 메타포 시각화
// ═══════════════════════════════════════════════════════════

class GrowthMetaphor {
  GrowthMetaphor._();

  static ({String emoji, String label, String desc}) streakStage(int days) {
    if (days >= 100) return (emoji: '🌳', label: '거목', desc: '흔들리지 않는 뿌리');
    if (days >= 60)  return (emoji: '🌲', label: '큰 나무', desc: '굳건한 성장');
    if (days >= 30)  return (emoji: '🌿', label: '풀숲', desc: '안정적인 습관');
    if (days >= 14)  return (emoji: '🌱', label: '새싹', desc: '습관이 자라는 중');
    if (days >= 7)   return (emoji: '🫒', label: '씨앗', desc: '뿌리를 내리는 중');
    if (days >= 1)   return (emoji: '🌰', label: '씨앗', desc: '첫 발아');
    return (emoji: '💤', label: '휴면', desc: '새 시작을 기다리는 중');
  }

  static String gradeFlower(String grade) {
    switch (grade) {
      case 'S+': return '🌺';
      case 'S': return '🌸';
      case 'A': return '🌷';
      case 'B': return '🌼';
      case 'C': return '🌻';
      case 'D': return '🥀';
      default: return '🍂';
    }
  }

  static ({String emoji, String label, double fill}) waterLevel(int minutes) {
    if (minutes >= 480) return (emoji: '💧💧💧', label: '충분한 관수', fill: 1.0);
    if (minutes >= 360) return (emoji: '💧💧', label: '적정 관수', fill: minutes / 480);
    if (minutes >= 240) return (emoji: '💧', label: '기본 관수', fill: minutes / 480);
    if (minutes >= 120) return (emoji: '🫗', label: '부족', fill: minutes / 480);
    return (emoji: '🏜️', label: '가뭄', fill: minutes / 480);
  }

  static String progressPlant(double ratio) {
    if (ratio >= 1.0) return '🌳';
    if (ratio >= 0.8) return '🌿';
    if (ratio >= 0.6) return '🌱';
    if (ratio >= 0.4) return '☘️';
    if (ratio >= 0.2) return '🫒';
    return '🌰';
  }
}

// ═══════════════════════════════════════════════════════════
// ThemeData builders
// ═══════════════════════════════════════════════════════════

class BotanicalTheme {
  BotanicalTheme._();

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorSchemeSeed: BotanicalColors.primary,
    scaffoldBackgroundColor: BotanicalColors.scaffoldLight,
    textTheme: GoogleFonts.notoSansKrTextTheme(),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: BotanicalColors.cardLight,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: BotanicalColors.scaffoldLight,
      elevation: 0, scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.notoSansKr(
        fontSize: 17, fontWeight: FontWeight.w700, color: BotanicalColors.textMain),
      iconTheme: const IconThemeData(color: BotanicalColors.textSub),
    ),
    dividerColor: BotanicalColors.borderLight,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BotanicalColors.primary, linearTrackColor: BotanicalColors.surfaceLight),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? BotanicalColors.primary : BotanicalColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? BotanicalColors.primarySurface : BotanicalColors.surfaceLight),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: BotanicalColors.primary, thumbColor: BotanicalColors.primary,
      inactiveTrackColor: BotanicalColors.surfaceLight),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: Color(0xFFFFFFFF),
      selectedItemColor: BotanicalColors.primary,
      unselectedItemColor: BotanicalColors.textMuted, elevation: 0),
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorSchemeSeed: BotanicalColors.primary,
    scaffoldBackgroundColor: BotanicalColors.scaffoldDark,
    textTheme: GoogleFonts.notoSansKrTextTheme(ThemeData.dark().textTheme),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: BotanicalColors.cardDark,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: BotanicalColors.scaffoldDark,
      elevation: 0, scrolledUnderElevation: 0,
      titleTextStyle: GoogleFonts.notoSansKr(
        fontSize: 17, fontWeight: FontWeight.w700, color: BotanicalColors.textMainDark),
      iconTheme: const IconThemeData(color: BotanicalColors.textSubDark),
    ),
    dividerColor: BotanicalColors.borderDark,
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: BotanicalColors.lanternGold, linearTrackColor: BotanicalColors.surfaceDark),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? BotanicalColors.lanternGold : BotanicalColors.textMutedDark),
      trackColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? BotanicalColors.surfaceDark : BotanicalColors.cardDark),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: BotanicalColors.lanternGold, thumbColor: BotanicalColors.lanternGold,
      inactiveTrackColor: BotanicalColors.surfaceDark),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: BotanicalColors.scaffoldDark,
      selectedItemColor: BotanicalColors.lanternGold,
      unselectedItemColor: BotanicalColors.textMutedDark, elevation: 0),
  );
}

// ═══ GLOBAL BOTTOM SHEET SAFE PADDING ═══
/// 바텀시트 안전 하단 패딩: 키보드 또는 시스템 네비바 높이 + 여유
double sheetBottomPad(BuildContext ctx, {double extra = 20}) {
  final mq = MediaQuery.of(ctx);
  final kbOrNav = mq.viewInsets.bottom > 0
      ? mq.viewInsets.bottom
      : mq.viewPadding.bottom;
  return kbOrNav + extra;
}
