import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 기획 문서 "디자인 방향 v6" 표 그대로 옮긴 토큰.
/// https://claude.ai/artifact/U8h2Ukqj5FfBkLaPGVgtBZ

enum Section { market, culture, money, ai }

class SectionTheme {
  const SectionTheme({
    required this.label,
    required this.color,
    required this.highlight,
    required this.shape,
  });

  final String label;
  final Color color;
  final Color highlight;
  final String shape; // ○ △ □ ✳
}

// 2026-09-29: 기획 문서 결정 — "시세" 섹션을 "생활(Living)"로 넓힘(날씨,
// 미세먼지, 장보기 물가, 동네 최저가 주유소, 식품 회수 알림 등). 색(노랑)과
// 도형(○)은 그대로 두고 라벨만 바꿈 — enum 이름(market)은 코드 전체에 이미
// 퍼져있어서 안 바꿈, 화면에 보이는 한글 라벨만 의미에 맞게 갱신.
const sectionThemes = <Section, SectionTheme>{
  Section.market: SectionTheme(
    label: '생활',
    color: Color(0xFFE0A81E),
    highlight: Color(0xFFFCE9A8),
    shape: '○',
  ),
  Section.culture: SectionTheme(
    label: '문화',
    color: Color(0xFFD0452E),
    highlight: Color(0xFFFAD6CC),
    shape: '△',
  ),
  Section.money: SectionTheme(
    label: '머니',
    color: Color(0xFF2F42B0),
    highlight: Color(0xFFD9DFFA),
    shape: '□',
  ),
  Section.ai: SectionTheme(
    label: 'AI',
    color: Color(0xFF191919),
    highlight: Color(0xFFE5F7A3),
    shape: '✳',
  ),
};

class AppColors {
  static const background = Color(0xFFFFFFFF);
  static const ink = Color(0xFF191919);
  static const inkSoft = Color(0xFF8B8B8B);
  static const line = Color(0xFFEBEBEB);
  static const sectionDivider = Color(0xFFF5F5F5);
  static const up = Color(0xFFD13A2A);
  static const down = Color(0xFF2F42B0);
}

class AppTheme {
  static ThemeData get light {
    final base = ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.ink,
        brightness: Brightness.light,
      ),
      fontFamily: GoogleFonts.notoSansKr().fontFamily,
    );
    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: AppColors.ink,
        displayColor: AppColors.ink,
      ),
      dividerColor: AppColors.line,
    );
  }

  /// 섹션 대제목에만 쓰는 세리프(Instrument Serif).
  static TextStyle displaySerif({double size = 22}) =>
      GoogleFonts.instrumentSerif(fontSize: size, color: AppColors.ink);
}
