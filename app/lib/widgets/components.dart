import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../theme.dart';

/// 기획 문서 "컴포넌트" 표의 부품들. 화면은 이 조합으로만 만들고,
/// 색을 바꾸려면 SectionTheme 표만 고치면 되게 함.

/// 2026-10-06: "출처 표시가 하나도 없다"는 피드백 — 기획 문서 원칙
/// ("모든 데이터 카드에는 출처를 표시")을 처음 반영함. 메인 카드(PosterCard/
/// WeatherHero/ChartCard) 하단에 공통으로 붙이는 작은 캡션.
class SourceTag extends StatelessWidget {
  const SourceTag({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text('출처: $source', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
    );
  }
}

/// 2026-10-10: 카드 실험 비교에서 고른 "테두리 없음 + 비비드 헤더 블록"
/// (1번) — 메인 카드의 윗부분이 섹션 색 블록이고 그 안에 도형(onColor로
/// 틴트)+섹션명(세리프)이 들어감. 예전 SectionHeader(페이지 맨 위 제목)를
/// 대체함: 각 섹션 화면의 첫 메인 카드가 곧 그 페이지의 제목 역할을 함.
class _VividHeader extends StatelessWidget {
  const _VividHeader({required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return Container(
      color: t.color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset(t.shapeAsset, width: 22, height: 22, color: t.onColor, colorBlendMode: BlendMode.srcIn),
          const SizedBox(width: 10),
          Text(
            t.label,
            style: AppTheme.displaySerif(size: 22, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.2)
                .copyWith(color: t.onColor),
          ),
        ],
      ),
    );
  }
}

/// 메인(hero) 카드 공통 틀 — 테두리 없음. 헤더가 있으면 섹션 색 블록 + 흰
/// 본문, 헤더가 없는 보조 메인 카드(예: 생활의 가격 추이)는 경계가 없어
/// 허공에 뜨지 않게 섹션 틴트색을 옅게 깔아서 구분함.
class _HeroShell extends StatelessWidget {
  const _HeroShell({required this.section, required this.child, this.showHeader = true});

  final Section section;
  final Widget child;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showHeader) _VividHeader(section: section),
        Container(
          color: showHeader ? AppColors.background : t.highlight.withValues(alpha: 0.35),
          padding: const EdgeInsets.all(16),
          child: child,
        ),
      ],
    );
  }
}

/// 메인 카드 앞/뒷면. back이 있으면 카드를 눌러서 뒤집을 수 있고(세로축
/// 3D 회전), 앞면 아래에 "↻ 눌러서 ..." 힌트가 붙음. 각 면은 같은 _HeroShell
/// (헤더 포함)로 감싸서 뒷면도 같은 카드처럼 보임. 면마다 높이가 달라도
/// 되게 회전이 90도(옆에서 봐서 폭이 0에 가까운 순간)일 때만 면을 바꿈.
class _FlippableHero extends StatelessWidget {
  const _FlippableHero({
    required this.section,
    required this.front,
    this.back,
    this.backHint,
    this.showHeader = true,
  });

  final Section section;
  final Widget front;
  final Widget? back;
  final String? backHint;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    if (back == null) {
      return _HeroShell(section: section, showHeader: showHeader, child: front);
    }
    Widget hint(String text) => Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
        );
    return FlipCard(
      front: _HeroShell(
        section: section,
        showHeader: showHeader,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [front, hint('↻ ${backHint ?? '눌러서 더 보기'}')],
        ),
      ),
      back: _HeroShell(
        section: section,
        showHeader: showHeader,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [back!, hint('↻ 눌러서 앞면으로')],
        ),
      ),
    );
  }
}

class FlipCard extends StatefulWidget {
  const FlipCard({super.key, required this.front, required this.back});

  final Widget front;
  final Widget back;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final Animation<double> _curve = CurvedAnimation(parent: _controller, curve: Curves.easeInOutCubic);
  bool _showingBack = false;

  void _toggle() {
    if (_showingBack) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    _showingBack = !_showingBack;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) {
          final angle = _curve.value * math.pi;
          final isBack = angle > math.pi / 2;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(isBack ? angle - math.pi : angle);
          return Transform(
            transform: transform,
            alignment: Alignment.center,
            child: isBack ? widget.back : widget.front,
          );
        },
      ),
    );
  }
}

class SectionDivider extends StatelessWidget {
  const SectionDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(height: 10, color: AppColors.sectionDivider);
  }
}

/// 보조 카드(StatTile)용 헤어라인 틀. 메인 카드는 _HeroShell을 씀.
class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    // 2026-10-06: "테두리가 촌스럽다, 더 얇게" 피드백 — 얇은 헤어라인.
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(border: Border.all(color: AppColors.line, width: 0.75)),
      child: child,
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value, required this.change});

  final String label;
  final String value;
  final String change; // up / down / flat

  Color get _changeColor => switch (change) {
        'up' => AppColors.up,
        'down' => AppColors.down,
        _ => AppColors.inkSoft,
      };

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            switch (change) { 'up' => '▲', 'down' => '▼', _ => '－' },
            style: TextStyle(color: _changeColor, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class RankRow extends StatelessWidget {
  const RankRow({super.key, required this.section, required this.rank, required this.title, required this.meta});

  final Section section;
  final int rank;
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            // rank가 없는 목록(제철 품목, 전통시장 등)은 0을 넘겨서 숫자
            // 대신 작은 점만 보여줌 — 숫자 "0"이 그대로 찍히던 문제 수정
            // (2026-09-29). 2026-09-30: 비정형 도형 이미지를 여기(14px)
            // 처럼 작게 쓰니 뭉개져 보인다는 피드백 — 도형은 대제목에만
            // 쓰고, 여기는 그냥 작은 색 점으로 되돌림.
            child: rank > 0
                ? Text(
                    '$rank',
                    style: TextStyle(
                      color: t.color,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : Center(
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
                    ),
                  ),
          ),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
          Text(meta, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
        ],
      ),
    );
  }
}

/// 홈(투데이)의 섹션별 대표 카드 — 제목 + 형광펜 강조 구절 + 보조 정보.
/// 투데이 화면(여러 섹션이 한 리스트에 섞임)에선 어느 섹션 카드인지
/// 표시할 SectionHeader가 카드 안에 필요하지만, 각 섹션 화면(SectionScreen)
/// 안에서 쓸 땐 화면 맨 위에 이미 SectionHeader가 한 번 있어서 중복으로
/// 두 번 찍히던 문제가 있었음(2026-09-29 발견) — showHeader:false로 끔.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.section,
    required this.title,
    this.highlight,
    this.meta,
    this.showHeader = true,
  });

  final Section section;
  final String title;
  final String? highlight;
  final String? meta;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return _HeroShell(
      section: section,
      showHeader: showHeader,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTheme.displaySerif(size: 15)),
          if (highlight != null) ...[
            const SizedBox(height: 6),
            _Highlight(text: highlight!, color: t.highlight),
          ],
          if (meta != null) ...[
            const SizedBox(height: 6),
            Text(meta!, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

/// 2026-10-05: "문화도 메인 영역 하나 있으면 좋겠다" 요청 — 기획 문서
/// 컴포넌트 표에 원래 있던 PosterCard(포스터+순위+누적 수치)를 이제야
/// 만듦. 백엔드 culture()의 hero 필드(박스오피스 1위)는 처음부터 있었는데
/// 화면에서 한 번도 안 썼던 걸 여기서 씀. 포스터 이미지는 아직 없어서
/// (KOBIS엔 포스터가 없음 — 기획 문서 "열린 질문", KMDb 등 별도 소스
/// 필요) null이면 섹션 도형을 넣은 자리표시자로 대신함.
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.section,
    required this.title,
    required this.rank,
    required this.statLabel,
    required this.stat,
    this.poster,
    this.source,
    this.back,
    this.backHint,
    this.showHeader = true,
  });

  final Section section;
  final String title;
  final int rank;
  final String statLabel;
  final String stat;
  final String? poster;
  final String? source;
  final Widget? back;
  final String? backHint;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return _FlippableHero(
      section: section,
      showHeader: showHeader,
      back: back,
      backHint: backHint,
      front: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 72,
                child: AspectRatio(
                  aspectRatio: 2 / 3,
                  child: poster != null
                      ? Image.network(poster!, fit: BoxFit.cover)
                      : DecoratedBox(
                          decoration: BoxDecoration(color: t.highlight),
                          child: Center(child: Image.asset(t.shapeAsset, width: 28, height: 28)),
                        ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$rank위',
                      style: TextStyle(
                        color: t.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(title, style: AppTheme.displaySerif(size: 18)),
                    const SizedBox(height: 8),
                    Text(statLabel, style: const TextStyle(color: AppColors.inkSoft, fontSize: 11)),
                    Text(
                      stat,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (source != null) SourceTag(source: source!),
        ],
      ),
    );
  }
}

/// 오늘 날씨 + 옷차림 + 빨래/세차하기 좋은 날 + 미세먼지를 한 카드로.
/// 2026-09-29: 기획 문서에 "생활" 섹션이 확정되며 날씨가 제일 먼저
/// 나오는 항목으로 정해짐 — 축제(문화 섹션)가 맑은 날 위주로 뜨는 것처럼
/// 다른 섹션도 같이 쓸 "공통" 데이터라 구현 우선순위를 여기부터 잡음.
/// 화면 맨 위, 제철보다도 앞에 옴(아침에 제일 먼저 확인하는 정보라서).
class WeatherHero extends StatelessWidget {
  const WeatherHero({super.key, required this.section, required this.data});

  final Section section;
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    final today = data['today'] as Map<String, dynamic>;
    final hourly = (data['hourly'] as List).cast<Map<String, dynamic>>();
    final weekly = (data['weekly'] as List).cast<Map<String, dynamic>>();
    final goodFor = (data['good_for'] as List).cast<Map<String, dynamic>>();
    final air = data['air_quality'] as Map<String, dynamic>;
    // WeatherHero는 투데이에서만 쓰여서 항상 섹션 색 헤더 블록을 보여줌.
    return _HeroShell(
      section: section,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('오늘 날씨', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${today['temp']}°',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(today['condition'] as String, style: const TextStyle(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '체감 ${today['feels_like']}° · 최고 ${today['high']}° · 최저 ${today['low']}°',
            style: const TextStyle(color: AppColors.inkSoft, fontSize: 12),
          ),
          const SizedBox(height: 14),
          // 2026-09-29: "한국 날씨는 변덕스러우니 네이버처럼 자세히" 요청 —
          // 오늘 한 줄 요약만으론 부족해서 시간대별 가로 스크롤 스트립을 추가함.
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: hourly.length,
              separatorBuilder: (context, i) => const SizedBox(width: 16),
              itemBuilder: (context, i) {
                final h = hourly[i];
                final pop = h['pop'] as int;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(h['time'] as String, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                    const SizedBox(height: 6),
                    Text(
                      '${h['temp']}°',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pop > 0 ? '$pop%' : '',
                      // 2026-09-30: "제일 작은 글씨가 너무 작다"는 피드백 —
                      // 10px는 업계 최소 권장선(11~12px)보다 작아서 11로 올림.
                      style: TextStyle(fontSize: 11, color: pop > 0 ? t.color : Colors.transparent),
                    ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          _Highlight(
            text: data['outfit'] as String,
            color: t.highlight,
            style: AppTheme.displaySerif(size: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Text(
            data['weekend'] as String,
            style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.5),
          ),
          const SizedBox(height: 14),
          for (final w in weekly)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(w['day'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(w['date'] as String, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                  ),
                  Expanded(
                    child: Text(w['condition'] as String, style: const TextStyle(fontSize: 12)),
                  ),
                  if ((w['pop'] as int) > 0)
                    Text('${w['pop']}%', style: TextStyle(fontSize: 11, color: t.color)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${w['low']}° / ${w['high']}°',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              for (final g in goodFor)
                Text(
                  '${g['good'] == true ? '✓' : '✕'} ${g['label']}하기 ${g['good'] == true ? '좋은' : '별로인'} 날',
                  style: TextStyle(
                    fontSize: 12,
                    color: g['good'] == true ? t.color : AppColors.inkSoft,
                    fontWeight: g['good'] == true ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              Text(
                '미세먼지 ${air['pm10']} · 초미세먼지 ${air['pm25']}',
                style: const TextStyle(fontSize: 12, color: AppColors.inkSoft),
              ),
            ],
          ),
          if (data['source'] != null) SourceTag(source: data['source'] as String),
        ],
      ),
    );
  }
}

/// 2026-09-30: "제철이 언제부터 언제까지인지 월 단위 간트차트처럼
/// 보여달라"는 요청으로 SeasonalHero(품목명+짧은 문구 나열)를 대체함 —
/// 당월 기준 앞뒤 2개월(총 5개월)을 열로 두고, 품목별로 제철에 해당하는
/// 달만 칸을 채워서 시작~끝을 한눈에 보여줌. 가로로 길게 안 늘어나도
/// 되게 폭을 고정폭 5칸으로 좁혀서 폰 화면에 맞춤.
class SeasonalGantt extends StatelessWidget {
  const SeasonalGantt({super.key, required this.section, required this.items, this.showHeader = true});

  final Section section;
  final List<({String name, int startMonth, int endMonth, String tip})> items;
  final bool showHeader;

  static const _monthsAround = 2;

  bool _inSeason(int month, int start, int end) {
    if (start <= end) return month >= start && month <= end;
    return month >= start || month <= end; // 연말~연초로 걸치는 경우
  }

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    final now = DateTime.now().month;
    final months = [
      for (var i = -_monthsAround; i <= _monthsAround; i++) ((now - 1 + i) % 12 + 12) % 12 + 1,
    ];

    // 2026-10-10: 뒷면 — 앞면 달력은 당월 기준 ±2개월 창이라 제철이 그
    // 밖으로 이어지는 품목은 막대만으로 끝을 알 수 없었음. 뒷면에 정확한
    // 제철 기간을 글로 적고, 고르는 팁도 같이 보여줌.
    final back = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('제철 기간 · 고르는 팁', style: TextStyle(color: AppColors.inkSoft, fontSize: 12)),
        const SizedBox(height: 10),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(it.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${it.startMonth}~${it.endMonth}월',
                        style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
                  ],
                ),
                const SizedBox(height: 2),
                Text(it.tip, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft, height: 1.45)),
              ],
            ),
          ),
      ],
    );

    return _FlippableHero(
      section: section,
      showHeader: showHeader,
      back: back,
      backHint: '눌러서 제철 기간·고르는 팁 보기',
      front: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('제철 캘린더', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(width: 52),
              for (final m in months)
                Expanded(
                  child: Center(
                    child: Text(
                      '$m월',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: m == now ? FontWeight.w800 : FontWeight.w400,
                        color: m == now ? AppColors.ink : AppColors.inkSoft,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final it in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(it.name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  ),
                  for (final m in months)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Container(
                          height: 16,
                          color: _inSeason(m, it.startMonth, it.endMonth) ? t.color : AppColors.line,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// 큰 숫자 + 선 그래프. "전주 대비 -18%" 같은 단일 텍스트보다 추이 자체가
/// 장보기 결정에 더 도움된다는 피드백(2026-09-29)으로 만듦 — 새 패키지
/// 없이 CustomPainter로 직접 그림(형광펜 효과처럼 단순한 선 하나라 굳이
/// 차트 라이브러리를 새로 안 들여도 됨).
class ChartCard extends StatelessWidget {
  const ChartCard({
    super.key,
    required this.section,
    required this.label,
    required this.value,
    required this.change,
    required this.series,
    this.source,
    this.showHeader = true,
    this.back,
    this.backHint,
  });

  final Section section;
  final String label;
  final String value;
  final String change; // up / down / flat
  final List<double> series;
  final String? source;
  final bool showHeader;
  final Widget? back;
  final String? backHint;

  Color get _changeColor => switch (change) {
        'up' => AppColors.up,
        'down' => AppColors.down,
        _ => AppColors.inkSoft,
      };

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return _FlippableHero(
      section: section,
      showHeader: showHeader,
      back: back,
      backHint: backHint,
      front: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                switch (change) { 'up' => '▲', 'down' => '▼', _ => '－' },
                style: TextStyle(color: _changeColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: CustomPaint(painter: _LineChartPainter(series: series, color: t.color)),
          ),
          if (source != null) SourceTag(source: source!),
        ],
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter({required this.series, required this.color});

  final List<double> series;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.length < 2) return;
    final minV = series.reduce((a, b) => a < b ? a : b);
    final maxV = series.reduce((a, b) => a > b ? a : b);
    final range = (maxV - minV).abs() < 1e-6 ? 1 : maxV - minV;
    final dx = size.width / (series.length - 1);

    Offset pointAt(int i) {
      final normalized = (series[i] - minV) / range;
      return Offset(dx * i, size.height - normalized * size.height);
    }

    final line = Path()..moveTo(pointAt(0).dx, pointAt(0).dy);
    for (var i = 1; i < series.length; i++) {
      line.lineTo(pointAt(i).dx, pointAt(i).dy);
    }

    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.08));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final last = pointAt(series.length - 1);
    canvas.drawCircle(last, 3, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) =>
      oldDelegate.series != series || oldDelegate.color != color;
}

class _Highlight extends StatelessWidget {
  const _Highlight({required this.text, required this.color, this.style});

  final String text;
  final Color color;
  // 2026-09-30: SectionHeader 타이틀에도 재사용하려고 폰트 스타일을
  // 바꿀 수 있게 함(기본값은 기존 본문 강조 스타일 그대로 유지).
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.bottomLeft,
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.bottomLeft,
            child: FractionallySizedBox(heightFactor: 0.42, child: ColoredBox(color: color)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(text, style: style ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
