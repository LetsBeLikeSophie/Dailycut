import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 기획 문서 "디자인 방향 v6" 표 그대로 옮긴 토큰.
/// https://claude.ai/artifact/U8h2Ukqj5FfBkLaPGVgtBZ

enum Section { weather, market, culture, money, ai }

class SectionTheme {
  const SectionTheme({
    required this.label,
    required this.color,
    required this.highlight,
    required this.shape,
    required this.shapeAsset,
  });

  final String label;
  final Color color;
  final Color highlight;
  final String shape; // ○ △ □ ✳ — 더 이상 화면에 안 쓰지만(비정형 도형
  // 이미지로 교체됨) 참고/디버그용으로 남겨둠.
  final String shapeAsset; // assets/shapes/*.png, 섹션 색으로 이미 리컬러됨.
}

// 2026-09-29: 기획 문서 결정 — "시세" 섹션을 "생활(Living)"로 넓힘(날씨,
// 미세먼지, 장보기 물가, 동네 최저가 주유소, 식품 회수 알림 등). 색(노랑)과
// 도형(○)은 그대로 두고 라벨만 바꿈 — enum 이름(market)은 코드 전체에 이미
// 퍼져있어서 안 바꿈, 화면에 보이는 한글 라벨만 의미에 맞게 갱신.
//
// 2026-09-30: 텍스트 글리프(○△□✳) 대신 사용자가 가져온 비정형(organic
// blob) 도형 이미지로 교체함 — 원래 도형과 최대한 비슷한 걸로 매칭
// (원→circle blob, 삼각→triangle blob, 사각→cross blob, ✳→star blob),
// 각 PNG는 섹션 테마 색으로 이미 리컬러돼 있어서 그대로 그리면 됨(추가
// 틴트 불필요).
const sectionThemes = <Section, SectionTheme>{
  // 2026-09-30: "생활에 날씨가 통째로 들어있는 게 이상하다"는 피드백 —
  // 날씨를 생활에서 분리함. 전용 탭/화면은 안 만들고 투데이 카드로만
  // 남겨서(main.dart엔 탭 없음) 이 SectionTheme은 투데이 카드 테마용으로만
  // 쓰임. 기존 4색과 안 겹치는 새 색(주황)을 새로 고름 — 기획 문서엔
  // 원래 없던 섹션이라 색·도형 둘 다 이번에 새로 정함.
  Section.weather: SectionTheme(
    label: '날씨',
    color: Color(0xFFE08A3E),
    highlight: Color(0xFFF7D9BA),
    shape: '☁',
    shapeAsset: 'assets/shapes/shape_weather.png',
  ),
  Section.market: SectionTheme(
    label: '생활',
    color: Color(0xFFE0A81E),
    highlight: Color(0xFFFCE9A8),
    shape: '○',
    shapeAsset: 'assets/shapes/shape_market.png',
  ),
  Section.culture: SectionTheme(
    label: '문화',
    color: Color(0xFFD0452E),
    highlight: Color(0xFFFAD6CC),
    shape: '△',
    shapeAsset: 'assets/shapes/shape_culture.png',
  ),
  Section.money: SectionTheme(
    label: '머니',
    color: Color(0xFF2F42B0),
    highlight: Color(0xFFD9DFFA),
    shape: '□',
    shapeAsset: 'assets/shapes/shape_money.png',
  ),
  Section.ai: SectionTheme(
    label: 'AI',
    color: Color(0xFF191919),
    highlight: Color(0xFFE5F7A3),
    shape: '✳',
    shapeAsset: 'assets/shapes/shape_ai.png',
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

  /// 2026-09-30: 원래 Instrument Serif를 썼는데, 구글 폰트 공식
  /// METADATA(subsets: latin/latin-ext뿐, korean 없음)를 확인해보니
  /// 한글 글리프가 아예 없는 폰트였음 — "생활"/"문화"/"머니"처럼 한글
  /// 라벨은 세리프가 적용된 적이 없고 폴백 폰트로 조용히 대체돼 그려지고
  /// 있었음(영문인 "AI"만 실제로 세리프였음). 이슈팝이 이미 검증해서 쓰고
  /// 있는 Noto Serif KR(한글 지원)로 교체함.
  ///
  /// 적용 범위: 대제목(SectionHeader) + "읽는 문장"류(투데이 헤드라인,
  /// HeroCard 타이틀, 날씨 옷차림 한 줄) — 가격·순위·달력처럼 숫자/표
  /// 형태 UI는 스캔하기 쉬운 산세리프로 남김(전부 세리프로 바꾸면 오히려
  /// 읽기 불편하다는 피드백 반영).
  /// 2026-10-06: "30대 이상 타게팅이면 여백이 더 편하게 느껴진다"는
  /// 피드백 — 세리프로 읽는 문장류는 기본 줄간격(height)이 너무 빽빽해서
  /// 1.4배로 넉넉하게 줌(한 줄짜리 제목엔 영향 없고, 두 줄 넘어가는
  /// 문장에서만 체감됨). 필요하면 height: 1.0으로 꺼서 쓸 수 있음.
  static TextStyle displaySerif({
    double size = 22,
    double? letterSpacing,
    FontWeight? fontWeight,
    double height = 1.4,
  }) =>
      GoogleFonts.notoSerifKr(
        fontSize: size,
        color: AppColors.ink,
        letterSpacing: letterSpacing,
        fontWeight: fontWeight,
        height: height,
      );

  /// 2026-09-29: displaySerif를 "축산물 시세"/"예·적금 금리 순위" 같은
  /// 화면 안 소제목에도 갖다 써서 "세리프는 섹션 대제목에만" 규칙을
  /// 어기고 있었음(직접 확인해서 발견) — 소제목은 이 스타일(Noto Sans
  /// KR 볼드)로 바꿔서 분리함.
  static const TextStyle subheading = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w700,
    color: AppColors.ink,
  );
}
