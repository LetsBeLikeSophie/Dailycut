import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'sources_info.dart';

/// 2026-10-10: "카드 상자 대신 한 화면 전체를 규칙으로 디자인"하는 방향으로
/// 전면 개편(디자인 시안: 생활 탭 한 화면). 규칙 여섯 가지 —
///  1) 카드 상자 없음, 여백과 가는 선으로만 구분(목록 맨 위만 진한 선)
///  2) 그래픽은 화면 맨 위의 큰 도형 하나뿐
///  3) 섹션 색은 도형·제목 형광펜·차트 끝점에만, 오르내림은 의미색(파랑/빨강)
///  4) 세리프는 한 문장 제목과 큰 숫자에만, 나머지는 전부 산세리프
///  5) 목록은 "이름 · 작은 추이 · 값과 변동" 한 가지 모양(ListLine)
///  6) 글자 크기는 11 / 13 / 16 / 24 / 60 다섯 단계
/// 화면은 이 부품의 조합으로만 만들고, 색은 SectionTheme만 고치면 바뀜.

/// 개발용 임시 표시: 실데이터가 아닌(스텁/예시) 영역에 분홍 배경 + 빨간 왼쪽 선을 깔아서
/// 눈으로 구분함. 실데이터가 다 붙으면 false로 바꾸거나 이 표시를 지우면 됨.
// 2026-10-14: 배포본에선 끔(예시 구간은 화면에서 아예 뺐음). 개발 때만 `--dart-define=SHOW_STUB_MARKS=true`.
const kShowStubMarks = bool.fromEnvironment('SHOW_STUB_MARKS');

class StubMark extends StatelessWidget {
  const StubMark({super.key, required this.stub, required this.child});

  final bool stub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!stub || !kShowStubMarks) return child;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF0F0),
        border: Border(left: BorderSide(color: Color(0xFFE57373), width: 3)),
      ),
      child: child,
    );
  }
}

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

String formatNumber(num v, {int decimals = 0}) {
  final s = v.toStringAsFixed(decimals);
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
}

Color changeColor(String change) => switch (change) {
  'up' => AppColors.up,
  'down' => AppColors.down,
  _ => AppColors.inkSoft,
};

/// 작은 그래프 색: 오르면 빨강·내리면 파랑, **비슷하면 옅은 회색**(2026-10-17: 진한 회색 + "－ 0.4%"가 마이너스처럼 읽혀 헷갈렸음).
Color sparkColor(String change) => switch (change) {
  'up' => AppColors.up,
  'down' => AppColors.down,
  _ => const Color(0xFFC9C9C9),
};

/// 변동 표시. 0.5% 이내(change == 'flat')면 부호 없는 숫자 대신 **"비슷해요"**(2026-10-17: "－ 0.4%"가 마이너스로 보임).
String changeLabel(String change, {num? pct}) {
  if (change == 'flat') return '비슷해요';
  final arrow = change == 'up' ? '▲' : '▼';
  if (pct == null) return arrow;
  return '$arrow ${pct.abs() == pct.abs().roundToDouble() ? pct.abs().round() : pct.abs()}%';
}

/// 제목 속 일부 구절만 섹션 형광펜으로 강조(전체 문장은 그대로).
class HighlightText extends StatelessWidget {
  const HighlightText({
    super.key,
    required this.text,
    required this.color,
    this.emphasis,
    this.emphasisAll = const [],
    required this.style,
  });

  final String text;
  final Color color;
  final String? emphasis;
  final List<String> emphasisAll; // 글 안에 나오는 모든 자리를 칠할 낱말들(예: '토요일', '일요일')
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // 2026-10-16: 한글은 글자 사이 어디서나 줄이 바뀌어 "…21°예 / 요"처럼 마지막 글자가 혼자 내려왔음 →
    // 단어(띄어쓰기) 단위로만 줄을 바꿈(CSS word-break: keep-all). 공백 하나를 줄바꿈 하나로 바꾸는 거라 글자 위치(강조 구간)는 그대로.
    return LayoutBuilder(
      builder: (context, c) {
        final base = DefaultTextStyle.of(context).style.merge(style);
        final t = keepAllWrap(text, base, c.maxWidth, MediaQuery.textScalerOf(context));
        final ranges = <(int, int)>[];
        final e = emphasis;
        if (e != null) {
          final i = text.indexOf(e);
          if (i >= 0) ranges.add((i, i + e.length));
        }
        for (final w in emphasisAll) {
          var from = 0;
          while (w.isNotEmpty) {
            final i = text.indexOf(w, from);
            if (i < 0) break;
            ranges.add((i, i + w.length));
            from = i + w.length;
          }
        }
        if (ranges.isEmpty) return Text(t, style: style);
        ranges.sort((x, y) => x.$1.compareTo(y.$1));
        final marked = TextStyle(backgroundColor: color.withValues(alpha: 0.85));
        final spans = <TextSpan>[];
        var pos = 0;
        for (final (start, end) in ranges) {
          if (start < pos) continue; // 겹치면 앞의 것만
          if (start > pos) spans.add(TextSpan(text: t.substring(pos, start)));
          spans.add(TextSpan(text: t.substring(start, end), style: marked));
          pos = end;
        }
        if (pos < t.length) spans.add(TextSpan(text: t.substring(pos)));
        return Text.rich(TextSpan(style: style, children: spans));
      },
    );
  }
}

/// 띄어쓰기 단위로만 줄을 나눔: 한 줄에 안 들어가는 단어 앞의 공백을 줄바꿈으로 바꿔 돌려줌(길이는 같음).
/// 한 단어가 한 줄보다 길면 어쩔 수 없이 그대로 두어 기본 줄바꿈에 맡김.
final Map<String, String> _wrapMemo = {};

String keepAllWrap(String text, TextStyle style, double maxWidth, TextScaler scaler) {
  if (!maxWidth.isFinite || !text.contains(' ')) return text;
  // 같은 글·폭·글꼴 크기면 다시 재지 않음(다시 그릴 때마다 글자 폭을 재던 것). 글꼴 크기·굵기·배율이 키에 들어감.
  final memoKey = '${maxWidth.toStringAsFixed(1)}|${style.fontSize}|${style.fontWeight?.value}|${style.fontFamily}|${scaler.scale(10)}|$text';
  final memo = _wrapMemo[memoKey];
  if (memo != null) return memo;
  if (_wrapMemo.length > 200) _wrapMemo.clear();
  double width(String s) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
    return tp.width;
  }

  final out = StringBuffer();
  var line = '';
  var first = true;
  for (final w in text.split(' ')) {
    if (first) {
      out.write(w);
      line = w;
      first = false;
      continue;
    }
    final cand = '$line $w';
    if (line.isNotEmpty && width(cand) > maxWidth) {
      out.write('\n');
      line = w;
    } else {
      out.write(' ');
      line = cand;
    }
    out.write(w);
  }
  return _wrapMemo[memoKey] = out.toString();
}

/// 큰 숫자(세리프 60). 숫자는 처음 나타날 때 0에서 올라가며 멈춤.
class BigNumber extends StatelessWidget {
  const BigNumber({
    super.key,
    required this.to,
    this.decimals = 0,
    this.unit,
    this.suffix = '',
  });

  final num to;
  final int decimals;
  final String? unit;
  final String suffix; // 숫자 바로 뒤(예: 도 기호 °)에 같은 크기로 붙는 글자

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final big = const TextStyle(
      fontFamily: 'NotoSerifKR',
      fontSize: 60,
      fontWeight: FontWeight.w900,
      height: 1.05,
      letterSpacing: -1.8,
      color: AppColors.ink,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? to.toDouble() : 0, end: to.toDouble()),
      duration: still ? Duration.zero : const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text.rich(
        TextSpan(
          style: big,
          children: [
            TextSpan(text: '${formatNumber(v, decimals: decimals)}$suffix'),
            if (unit != null)
              TextSpan(
                text: '  $unit',
                style: const TextStyle(
                  fontFamily: 'NotoSansKR',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: AppColors.inkSoft,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 한 화면의 맨 위. 큰 도형(화면 가장자리로 잘려 나감) + 데일리컷/날짜 +
/// 섹션명 + 한 문장 제목. body에 큰 숫자·차트 같은 대표 내용을 넣음.
/// back을 주면 누르면 뒤집혀서 뒷면(back)이 보임.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.section,
    required this.headline,
    required this.body,
    this.emphasis,
    this.eyebrow,
    this.source,
    this.back,
    this.backTitle,
    this.backHint,
    this.stub = false,
    this.onEyebrowTap,
    this.headlineLines = 0,
    this.topExtra,
  });

  final Widget? topExtra; // 지역 줄 바로 아래(제목 위)에 놓는 전환 버튼 등

  final int headlineLines; // 제목이 짧아도 이 줄 수만큼 자리를 비워 둠(고른 항목이 바뀔 때 화면이 위아래로 안 출렁이게)
  final VoidCallback? onEyebrowTap; // 있으면 눈썹 글(예: '오늘 · 서울 ▾')을 눌러 지역 선택
  final bool stub; // 실데이터가 아니면 true(개발용 표시)
  final Section section;
  final String headline;
  final String? emphasis;
  final String? eyebrow;
  final List<Widget> body;
  final String? source;
  final Widget? back;
  final String? backTitle;
  final String? backHint;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    Widget hint(String text) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text.rich(
        TextSpan(children: [
          const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.refresh, size: 13, color: AppColors.inkSoft)),
          TextSpan(text: ' $text'),
        ]),
        style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
      ),
    );
    final front = _HeroFrame(
      section: section,
      source: source,
      topExtra: topExtra,
      onEyebrowTap: onEyebrowTap,
      eyebrow: eyebrow ?? t.label,
      headline: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 24 * 1.4 * headlineLines),
        child: HighlightText(
          text: headline,
          emphasis: emphasis,
          color: t.highlight,
          style: AppTheme.displaySerif(
            size: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...body,
          if (back != null) hint(backHint ?? '눌러서 더 보기'),
        ],
      ),
    );
    if (back == null) return StubMark(stub: stub, child: front);
    return FlipCard(
      front: StubMark(stub: stub, child: front),
      back: StubMark(
        stub: stub,
        child: _HeroFrame(
          section: section,
          source: source,
          topExtra: topExtra,
          onEyebrowTap: onEyebrowTap,
          eyebrow: eyebrow ?? t.label,
          headline: Text(
            backTitle ?? '',
            style: AppTheme.displaySerif(
              size: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [back!, hint('눌러서 앞면으로')],
          ),
        ),
      ),
    );
  }
}

class _HeroFrame extends StatelessWidget {
  const _HeroFrame({
    required this.section,
    required this.eyebrow,
    required this.headline,
    required this.child,
    this.onEyebrowTap,
    this.source,
    this.topExtra,
  });

  final String? source;
  final Widget? topExtra;
  final VoidCallback? onEyebrowTap;
  final Section section;
  final String eyebrow;
  final Widget headline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _Blob(section: section),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: '데일리컷',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            '   ${now.month}월 ${now.day}일 ${_weekdays[now.weekday - 1]}요일',
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                ),
                // 데이터 출처: 날짜 옆의 작은 ⓘ(배경 없이) — 누르면 이 화면의 출처와 앱 전체 출처 목록
                GestureDetector(
                  onTap: () => showSourcesSheet(context, current: source),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, 12, 8),
                    child: Icon(Icons.info_outline, size: 15, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 86),
            GestureDetector(
              onTap: onEyebrowTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: eyebrow),
                    if (onEyebrowTap != null) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.arrow_drop_down, size: 18)),
                  ]),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (topExtra != null) ...[const SizedBox(height: 10), topExtra!],
            const SizedBox(height: 8),
            headline,
            const SizedBox(height: 22),
            child,
          ],
        ),
      ],
    );
  }
}

/// 화면 오른쪽 위 가장자리로 잘려 나가는 큰 도형. 아주 느리게 흔들림.
class _Blob extends StatefulWidget {
  const _Blob({required this.section});

  final Section section;

  @override
  State<_Blob> createState() => _BlobState();
}

class _BlobState extends State<_Blob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
        _c.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[widget.section]!;
    return Positioned(
      right: -76,
      top: -80,
      width: 200,
      height: 200,
      child: IgnorePointer(
        child: RotationTransition(
          turns: Tween<double>(
            begin: -0.014,
            end: 0.017,
          ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
          child: Image.asset(t.shapeAsset, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// 누르면 뒤집히는 앞/뒷면. 회전이 90도(옆에서 봐서 폭이 0에 가까운 순간)일
/// 때만 면을 바꿔서 면마다 높이가 달라도 어색하지 않게 함.
class FlipCard extends StatefulWidget {
  const FlipCard({super.key, required this.front, required this.back});

  final Widget front;
  final Widget back;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
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
            // 앞·뒷면을 IndexedStack에 같이 넣어 둘 중 큰 쪽 높이로 맞춤(뒤집어도 아래가 안 출렁임)
            child: IndexedStack(index: isBack ? 1 : 0, children: [widget.front, widget.back]),
          );
        },
      ),
    );
  }
}

/// 차트의 한 점: 이번 달의 며칠(1~말일)에 어떤 값이었는지.
class ChartPoint {
  const ChartPoint(this.day, this.value);

  final int day;
  final double value;
}

/// 화면 폭 끝까지 이어지는 이번 달 추이선. X축은 항상 이번 달 1일~말일(28~31)
/// 고정이고, 데이터는 오늘까지만 그려져서 오른쪽은 비어 있음(남은 날).
/// 선은 왼쪽→오른쪽으로 그려지고 끝점(오늘)은 섹션 색 원. 좌우 20px 안쪽에서
/// 시작해서 본문 여백과 정렬됨.
class TrendChart extends StatefulWidget {
  const TrendChart({
    super.key,
    required this.section,
    required this.points,
    this.format,
    this.unit = '',
    this.xMax,
    this.ticks,
    this.xLabel,
    this.selLabel,
  });

  final Section section;
  final List<ChartPoint> points;

  /// 값 표시 형식(기본: 1000 이상은 정수+쉼표, 그 밑은 소수 한 자리).
  final String Function(double)? format;
  final String unit;

  /// 기본은 "이번 달 1일~말일" 축. 월별 지표처럼 다른 축이 필요하면 xMax(1~xMax), 눈금, 라벨을 직접 줌.
  final int? xMax;
  final List<int>? ticks;
  final String Function(int)? xLabel;
  final String Function(int)? selLabel; // 눌러서 고른 점/최고·최저에 붙일 자세한 날짜(없으면 xLabel)

  @override
  State<TrendChart> createState() => _TrendChartState();
}

class _TrendChartState extends State<TrendChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;
  int? _sel; // 눌러서 고른 점(points 인덱스)

  String _fmt(double v) {
    final f = widget.format;
    if (f != null) return f(v);
    final txt = v.abs() >= 1000
        ? formatNumber(v)
        : (v == v.roundToDouble() ? v.toStringAsFixed(0) : formatNumber(v, decimals: 1));
    return '$txt${widget.unit}';
  }

  void _pick(double dx, double w, int days) {
    if (widget.points.isEmpty) return;
    const padX = 20.0;
    final width = w - padX * 2;
    var best = 0;
    var bestD = double.infinity;
    for (var i = 0; i < widget.points.length; i++) {
      final x = padX + width * (widget.points[i].day - 1) / (days - 1);
      final d = (x - dx).abs();
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    if (_sel != best) setState(() => _sel = best);
  }


  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _c.value = 1;
      } else {
        _c.forward();
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[widget.section]!;
    final now = DateTime.now();
    final monthly = widget.xMax == null;
    final days = widget.xMax ?? DateTime(now.year, now.month + 1, 0).day;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    // 눈금: 1, 5, 10, 15, 20, 25, 말일
    final ticks = widget.ticks ?? <int>[1, 5, 10, 15, 20, 25, days];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, cons) {
            final w = cons.maxWidth + 40;
            return SizedBox(
              height: 120,
              child: OverflowBox(
                minWidth: w,
                maxWidth: w,
                alignment: Alignment.center,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _pick(d.localPosition.dx, w, days),
                  onHorizontalDragStart: (d) => _pick(d.localPosition.dx, w, days),
                  onHorizontalDragUpdate: (d) => _pick(d.localPosition.dx, w, days),
                  child: AnimatedBuilder(
                    animation: curve,
                    builder: (context, _) => CustomPaint(
                      size: Size(w, 120),
                      painter: _TrendPainter(
                        points: widget.points,
                        days: days,
                        progress: curve.value,
                        fill: t.highlight,
                        dot: t.color,
                        selected: _sel,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, cons) => SizedBox(
            height: 16,
            width: cons.maxWidth,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final d in ticks)
                  Positioned(
                    left: cons.maxWidth * (d - 1) / (days - 1),
                    child: FractionalTranslation(
                      translation: const Offset(-0.5, 0),
                      child: Text(
                        widget.xLabel?.call(d) ?? (d == 1 || d == days ? '$d일' : '$d'),
                        style: TextStyle(
                          fontSize: 11,
                          color: monthly && d == now.day
                              ? AppColors.ink
                              : AppColors.inkSoft,
                          fontWeight: monthly && d == now.day
                              ? FontWeight.w700
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _summary(),
      ],
    );
  }

  Widget _summary() {
    final pts = widget.points;
    if (pts.isEmpty) return const SizedBox.shrink();
    var hi = pts.first, lo = pts.first;
    for (final p in pts) {
      if (p.value > hi.value) hi = p;
      if (p.value < lo.value) lo = p;
    }
    const soft = TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5);
    final sel = _sel != null && _sel! < pts.length ? pts[_sel!] : null;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 2,
      children: [
        Wrap(
          children: [
            sel != null
              ? Text.rich(
                  TextSpan(children: [
                    TextSpan(text: '${(widget.selLabel ?? widget.xLabel)?.call(sel.day) ?? '${sel.day}일'}  ', style: soft),
                    TextSpan(
                      text: _fmt(sel.value),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ]),
                )
              : const SizedBox.shrink(),
          ],
        ),
        if (pts.length >= 2 && hi.value != lo.value)
          Text(
            '최고 ${_fmt(hi.value)}(${(widget.selLabel ?? widget.xLabel)?.call(hi.day) ?? '${hi.day}일'}) · 최저 ${_fmt(lo.value)}(${(widget.selLabel ?? widget.xLabel)?.call(lo.day) ?? '${lo.day}일'})',
            style: soft,
          ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.days,
    required this.progress,
    required this.fill,
    required this.dot,
    this.selected,
  });

  final List<ChartPoint> points;
  final int days;
  final double progress;
  final Color fill;
  final Color dot;
  final int? selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    const padX = 20.0, padTop = 12.0, padBottom = 18.0;
    final values = points.map((p) => p.value);
    final minV = values.reduce(math.min);
    final maxV = values.reduce(math.max);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : maxV - minV;
    final width = size.width - padX * 2;
    Offset at(ChartPoint p) => Offset(
      padX + width * (p.day - 1) / (days - 1),
      padTop +
          (1 - (p.value - minV) / range) * (size.height - padTop - padBottom),
    );

    // 월 전체 폭을 알려주는 아주 옅은 바닥선
    canvas.drawLine(
      Offset(padX, size.height - 1),
      Offset(padX + width, size.height - 1),
      Paint()
        ..color = AppColors.hair
        ..strokeWidth = 1,
    );

    final last = at(points.last);
    if (points.length >= 2) {
      final line = Path()..moveTo(at(points.first).dx, at(points.first).dy);
      for (var i = 1; i < points.length; i++) {
        final o = at(points[i]);
        line.lineTo(o.dx, o.dy);
      }
      final area = Path.from(line)
        ..lineTo(last.dx, size.height)
        ..lineTo(at(points.first).dx, size.height)
        ..close();

      final startX = at(points.first).dx;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(
          0,
          0,
          startX + (last.dx - startX) * progress + 2,
          size.height,
        ),
      );
      canvas.drawPath(area, Paint()..color = fill.withValues(alpha: 0.7));
      canvas.drawPath(
        line,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      canvas.restore();
    }

    if (selected != null && selected! < points.length) {
      final sp = at(points[selected!]);
      canvas.drawLine(
        Offset(sp.dx, 0),
        Offset(sp.dx, size.height),
        Paint()
          ..color = AppColors.ink.withValues(alpha: 0.35)
          ..strokeWidth = 1,
      );
      canvas.drawCircle(sp, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        sp,
        5,
        Paint()
          ..color = AppColors.ink
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    final o = ((progress - 0.9) / 0.1).clamp(0.0, 1.0);
    if (o > 0) {
      canvas.drawCircle(last, 6, Paint()..color = dot.withValues(alpha: o));
      canvas.drawCircle(
        last,
        6,
        Paint()
          ..color = AppColors.ink.withValues(alpha: o)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter old) =>
      old.progress != progress || old.points != points || old.days != days || old.selected != selected;
}

/// 목록 속 작은 추이선(56x24).
class MiniSpark extends StatelessWidget {
  const MiniSpark({super.key, required this.series, required this.color});

  final List<double> series;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 56,
      height: 24,
      child: CustomPaint(painter: _MiniPainter(series, color)),
    );
  }
}

class _MiniPainter extends CustomPainter {
  _MiniPainter(this.series, this.color);

  final List<double> series;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.length < 2) return;
    final minV = series.reduce(math.min);
    final maxV = series.reduce(math.max);
    final range = (maxV - minV).abs() < 1e-6 ? 1.0 : maxV - minV;
    final dx = (size.width - 6) / (series.length - 1);
    Offset at(int i) => Offset(
      2 + dx * i,
      3 + (1 - (series[i] - minV) / range) * (size.height - 6),
    );
    final p = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < series.length; i++) {
      p.lineTo(at(i).dx, at(i).dy);
    }
    canvas.drawPath(
      p,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(at(series.length - 1), 2.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MiniPainter old) =>
      old.series != series || old.color != color;
}

/// 목록 한 묶음. 제목 + 오른쪽 작은 보조 글 + 진한 선 한 줄, 그 아래 행들.
/// 앱 전체에서 긴 목록을 처음에 보여주는 개수(맨 처음 화면의 날짜·기간 목록은 예외). 넘으면 "더 보기".
const kListLimit = 6;

/// 목록 맨 아래 "N개 더 보기" 버튼 — 모든 긴 목록이 같은 모양·같은 자리에서 펼쳐지게 공용으로 씀.
class ShowMoreButton extends StatelessWidget {
  const ShowMoreButton({super.key, required this.count, required this.onTap, this.unit = '개'});

  final int count;
  final String unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: Text('$count$unit 더 보기', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
      ),
    );
  }
}

/// 자식이 [limit]개를 넘으면 앞쪽만 보여주고 "더 보기"로 펼치는 목록(상태를 스스로 가짐).
class ExpandableList extends StatefulWidget {
  const ExpandableList({super.key, required this.children, this.limit = kListLimit, this.unit = '개'});

  final List<Widget> children;
  final int limit;
  final String unit;

  @override
  State<ExpandableList> createState() => _ExpandableListState();
}

class _ExpandableListState extends State<ExpandableList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final over = widget.children.length - widget.limit;
    final shown = _all || over <= 0 ? widget.children : widget.children.take(widget.limit).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...shown,
        if (!_all && over > 0) ShowMoreButton(count: over, unit: widget.unit, onTap: () => setState(() => _all = true)),
      ],
    );
  }
}

class ListSection extends StatelessWidget {
  const ListSection({
    super.key,
    required this.title,
    this.trailing,
    this.action,
    this.info,
    this.stub = false,
    required this.children,
  });

  final Widget? action; // 제목 줄 오른쪽 끝의 작은 버튼(예: 내 조건)
  final Widget? info; // 제목 글 바로 뒤에 붙는 ⓘ(출처·안내, 맨 위 "데일리컷 날짜 ⓘ"처럼)

  final String title;
  final String? trailing;
  // 실데이터가 아직 안 붙은(스텁) 묶음이면 true — 제목 옆에 "예시 데이터"를 표시해서
  // 가짜 숫자가 진짜처럼 보이지 않게 함.
  final bool stub;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 40),
      child: StubMark(
        stub: stub,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: Text(title, style: AppTheme.subheading)),
                      ?info,
                    ],
                  ),
                ),
                if (trailing != null || stub)
                  Text(
                    [?trailing, if (stub) '예시 데이터'].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ?action,
              ],
            ),
            const SizedBox(height: 10),
            Container(height: 1, color: AppColors.ink),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 모든 목록의 공통 한 줄: [앞] 이름(+작은 설명) · [가운데 위젯] · 값(+작은 변동).
class ListLine extends StatelessWidget {
  const ListLine({
    super.key,
    required this.name,
    this.sub,
    this.leading,
    this.middle,
    this.value,
    this.valueSub,
    this.valueSubColor = AppColors.inkSoft,
    this.stub = false,
    this.badge,
    this.onTap,
    this.valueColor,
    this.valueWeight = FontWeight.w700,
    this.nameIcon,
    this.nameIconColor = AppColors.ink,
    this.tag,
    this.trailing,
  });

  final Widget? trailing; // 줄 맨 오른쪽 끝 버튼(예: 장바구니 담기). 줄 전체의 onTap과 따로 눌림
  final Color nameIconColor;

  final String? tag; // 이름 옆 윤곽 알약(예: 장바구니에 '담김')

  final IconData? nameIcon; // 이름 옆 작은 아이콘(예: 장바구니에 담긴 품목)

  final FontWeight valueWeight; // 값 굵기(기본 굵게, 생활지수 같은 목록은 보통으로)
  final Color? valueColor; // 값 글자색(예: 지수 좋음/나쁨 구분)
  final String? badge; // 이름 옆 작은 알약(예: '제철')
  final VoidCallback? onTap; // 있으면 줄을 눌러 상세로
  final bool stub; // 실데이터가 아닌 줄(개발용 분홍 배경 표시)
  final String name;
  final String? sub;
  final Widget? leading;
  final Widget? middle;
  final String? value;
  final String? valueSub;
  final Color valueSubColor;

  @override
  Widget build(BuildContext context) {
    final line = Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: stub && kShowStubMarks ? const Color(0xFFFFF0F0) : null,
        border: const Border(bottom: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    if (nameIcon != null) ...[
                      const SizedBox(width: 6),
                      Icon(nameIcon, size: 16, color: nameIconColor),
                    ],
                    if (tag != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(999)),
                        child: Text(tag!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ],
                    if (badge != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          badge!,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (middle != null) ...[const SizedBox(width: 12), middle!],
          if (value != null) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 72, maxWidth: 150), // 값이 길어도 이름 칸이 눌리지 않게(2026-10-13)
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: valueWeight,
                      color: valueColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (valueSub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      valueSub!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: valueSubColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 4), trailing!],
        ],
      ),
    );
    return onTap == null
        ? line
        : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: line);
  }
}

/// {label, sub?, value, change, pct?, series?} 모양의 시세/지표 항목 한 줄.
ListLine priceRow(Map<String, dynamic> it) {
  final change = (it['change'] as String?) ?? 'flat';
  final series = (it['series'] as List?)
      ?.map((e) => (e as num).toDouble())
      .toList();
  return ListLine(
    name: it['label'] as String,
    sub: it['sub'] as String?,
    middle: series == null
        ? null
        : MiniSpark(series: series, color: sparkColor(change)),
    value: it['value'].toString(),
    valueSub: changeLabel(change, pct: it['pct'] as num?),
    valueSubColor: changeColor(change),
  );
}

/// 순위가 있으면 앞에 숫자, 없으면(rank 0) 이름·보조 글만.
class RankRow extends StatelessWidget {
  const RankRow({
    super.key,
    required this.rank,
    required this.title,
    required this.meta,
  });

  final int rank;
  final String title;
  final String meta;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hair)),
      ),
      child: Row(
        children: [
          if (rank > 0)
            SizedBox(
              width: 32,
              child: Text(
                '$rank',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 170),
            child: Text(
              meta,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// 제철 한 줄: 이름 + 고르는 팁, 오른쪽에 1~12월 점(제철인 달은 섹션 색,
/// 이번 달은 링). 막대 간트차트가 3개월 창에선 의미 없이 길어 보여서 교체.
class SeasonRow extends StatelessWidget {
  const SeasonRow({
    super.key,
    required this.section,
    required this.name,
    required this.tip,
    required this.startMonth,
    required this.endMonth,
  });

  final Section section;
  final String name;
  final String tip;
  final int startMonth;
  final int endMonth;

  bool _in(int m) => startMonth <= endMonth
      ? (m >= startMonth && m <= endMonth)
      : (m >= startMonth || m <= endMonth);

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    final now = DateTime.now().month;
    return ListLine(
      name: name,
      sub: tip.isEmpty ? null : tip,
      middle: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var m = 1; m <= 12; m++)
            Padding(
              padding: EdgeInsets.only(left: m == 1 ? 0 : 3),
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _in(m) ? t.color : const Color(0xFFE9E9E9),
                  border: m == now
                      ? Border.all(color: AppColors.ink, width: 1.5)
                      : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 제철 점 열 아래에 붙이는 달 눈금(1·4·7·10·12).
class SeasonLegend extends StatelessWidget {
  const SeasonLegend({super.key});

  @override
  Widget build(BuildContext context) {
    const ticks = {1, 4, 7, 10, 12};
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (var m = 1; m <= 12; m++)
            Padding(
              padding: EdgeInsets.only(left: m == 1 ? 0 : 3),
              child: SizedBox(
                width: 8,
                height: 16,
                child: OverflowBox(
                  maxWidth: 24,
                  maxHeight: 16,
                  child: Text(
                    ticks.contains(m) ? '$m' : '',
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkSoft,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}


/// 화살표로 항목을 돌려 보는 선택기: ‹ 코스피 1/4 › — 고정 높이라 고른 항목이 바뀌어도 아래가 출렁이지 않음.
class ArrowSelector extends StatelessWidget {
  const ArrowSelector({super.key, required this.label, required this.index, required this.count, required this.onChanged});

  final String label;
  final int index; // 0부터
  final int count;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget arrow(IconData icon, int delta) => GestureDetector(
          onTap: count < 2 ? null : () => onChanged((index + delta + count) % count),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(width: 44, height: 36, child: Icon(icon, size: 22, color: count < 2 ? AppColors.line : AppColors.ink)),
        );
    return Row(
      children: [
        arrow(Icons.chevron_left, -1),
        Expanded(
          child: Center(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                TextSpan(text: '   ${index + 1}/$count', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
              ]),
            ),
          ),
        ),
        arrow(Icons.chevron_right, 1),
      ],
    );
  }
}


/// 화면 안 큰 구역 전환(예: 문화 탭의 행사·전시 / 영화 / 음악): 상자 없이 글자만, 고른 것은 굵게 + 밑줄.
/// 앱의 여백 많은 편집체 분위기에 맞춰 버튼 느낌을 뺌.
class SegmentToggle extends StatefulWidget {
  const SegmentToggle({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<SegmentToggle> createState() => _SegmentToggleState();
}

class _SegmentToggleState extends State<SegmentToggle> {
  final _c = ScrollController();
  bool _more = false; // 오른쪽에 더 있음
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_check);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _check() {
    if (!_c.hasClients) return;
    final more = _c.position.maxScrollExtent - _c.offset > 4;
    if (more != _more && mounted) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final index = widget.index;
    if (!_checked) {
      _checked = true; // 처음 그린 뒤 한 번만 확인(이후엔 스크롤할 때 listener가 확인)
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
    // 2026-10-16: 장소 탭처럼 구분이 6개면 폭을 넘어서 가로로 밀어 볼 수 있게 하고, 더 있다는 걸 오른쪽 끝 흐림+화살표로 알림(칸이 적으면 그대로 한 줄)
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _c,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  GestureDetector(
                    onTap: () => widget.onChanged(i),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: i == index ? AppColors.ink : Colors.transparent, width: 2)),
                        ),
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: i == index ? FontWeight.w700 : FontWeight.w400,
                            color: i == index ? AppColors.ink : AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < labels.length - 1) const SizedBox(width: 26),
                ],
              ],
            ),
          ),
          if (_more)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 44,
                  alignment: Alignment.centerRight,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0x00FFFFFF), AppColors.background], stops: [0, 0.7]),
                  ),
                  child: const Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 작은 ⓘ 안내 시트(2026-10-16): 출처·기준·설명 같은 부가 글을 본문 아래에 늘어놓지 않고 ⓘ를 누르면 보이게 함.
Future<void> showNoteSheet(BuildContext context, {required String title, required List<String> lines}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.subheading),
            const SizedBox(height: 12),
            for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l, style: const TextStyle(fontSize: 13, height: 1.6))),
          ],
        ),
      ),
    ),
  );
}

/// 제목·캡션 옆에 붙이는 ⓘ 버튼(누르면 [showNoteSheet]).
class InfoIconButton extends StatelessWidget {
  const InfoIconButton({super.key, required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showNoteSheet(context, title: title, lines: lines),
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.fromLTRB(8, 4, 0, 4),
        child: Icon(Icons.info_outline, size: 15, color: AppColors.inkSoft),
      ),
    );
  }
}

/// 상세 시트의 공용 틀(2026-10-16): 안전 영역 + 스크롤 + 세리프 24 제목 + 13 회색 부제 + 내용. 혜택·장소·정부 지원·시장 상세가 같이 씀.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, this.sub, required this.children, this.gapAfterHeader = 22, this.infoLines});

  final String title;
  final String? sub;
  final List<String>? infoLines; // 있으면 제목 오른쪽에 ⓘ(출처·기준 설명)
  final List<Widget> children;
  final double gapAfterHeader; // 제목 묶음과 내용 사이

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: Text(title, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700))),
                if (infoLines != null) Padding(padding: const EdgeInsets.only(top: 6), child: InfoIconButton(title: '출처·안내', lines: infoLines!)),
              ],
            ),
            if (sub != null && sub!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(sub!, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            ],
            SizedBox(height: gapAfterHeader),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// 앱 공용 알약 칩(고르기/걸러 보기용). 선택되면 검정 바탕. 2026-10-16: 화면마다 따로 만들던 칩(_Pill·_Chip·_MiniPill)을 이것 하나로 합침.
///  - dotColor: 앞에 붙는 색 점(달력의 종류 칩) / large: 16글자·넉넉한 칩(지역 고르기) / emphasized: 선택 안 됐어도 테두리·글씨 진하게
/// 체크 모양 켜기/끄기 한 줄(2026-10-24, 장보기 시세의 `_FilterToggle`을 공용으로 뺌): ☐ 제철만 7.
/// 출처 시트의 "익명 통계 보내기"는 Material 기본 스위치(회색 트랙)가 앱 모양과 안 맞아서 이걸로 바꿈.
/// 알약 칩(PillChip)은 "여러 개 중 고르기", 이건 "하나를 켜고 끄기"에 씀.
class CheckToggle extends StatelessWidget {
  const CheckToggle({super.key, required this.label, required this.on, required this.onTap, this.count, this.icon, this.iconColor});

  final String label;
  final bool on;
  final VoidCallback onTap;
  final int? count; // 있으면 라벨 뒤에 작은 숫자
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: AppColors.ink),
            const SizedBox(width: 6),
            if (icon != null) ...[Icon(icon, size: 15, color: iconColor), const SizedBox(width: 3)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
            if (count != null) ...[const SizedBox(width: 5), Text('$count', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft))],
          ],
        ),
      ),
    );
  }
}

class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.selected, required this.onTap, this.vertical = 8, this.dotColor, this.large = false, this.emphasized = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double vertical;
  final Color? dotColor;
  final bool large;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final strong = selected || emphasized;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: large ? 9 : vertical),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          border: Border.all(color: strong ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontSize: large ? 16 : 13, fontWeight: strong ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// 앱 공용 가로 버튼(2026-10-16, 8개 파일에서 따로 그리던 윤곽선 버튼을 합침). 기본은 윤곽선, filled는 검정 바탕. 라벨은 13 굵게.
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.label, required this.onTap, this.filled = false, this.icon, this.expand = true, this.vertical = 14});

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final IconData? icon;
  final bool expand; // false면 글자 폭만큼(예: 히어로 안의 작은 버튼)
  final double vertical;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vertical, horizontal: expand ? 0 : 16),
        alignment: expand ? Alignment.center : null,
        decoration: BoxDecoration(color: filled ? AppColors.ink : null, border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 받는 중 표시(작은 원 + 문구). 목록 자리에서 쓰는 공용 모양.
class LoadingNote extends StatelessWidget {
  const LoadingNote({super.key, this.label = '불러오는 중이에요'});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink)),
        if (label != null) ...[
          const SizedBox(height: 14),
          Text(label!, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
        ],
      ],
    );
  }
}

/// 목록이 비었거나 못 받았을 때의 한 줄 안내(가운데, 회색 13). onTap이 있으면 눌러서 다시 시도하는 안내로 쓰임.
class EmptyNote extends StatelessWidget {
  const EmptyNote(this.text, {super.key, this.onTap, this.vertical = 40});

  final String text;
  final VoidCallback? onTap;
  final double vertical;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: vertical),
        child: Center(child: Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6))),
      ),
    );
  }
}

/// 개발자 점검용: 광고(상업 이용)를 켰을 때 라이선스 문제가 되는 구역에 테두리·꼬리표를 씌움.
/// 주소 뒤에 `?license=1`을 붙였을 때만 보이고, 평소엔 아무 일도 안 함(자식 그대로).
///  - block(빨강): 상업적 이용·제3자 제공이 약관/이용허락으로 막힌 데이터
///  - check(주황): 광고를 켜기 전에 허락·확인이 필요한 데이터
bool get kShowLicenseFlags => Uri.base.queryParameters['license'] == '1';

enum LicenseLevel { block, check }

class LicenseFlag extends StatelessWidget {
  const LicenseFlag({super.key, required this.label, required this.child, this.level = LicenseLevel.block});

  final String label;
  final Widget child;
  final LicenseLevel level;

  @override
  Widget build(BuildContext context) {
    if (!kShowLicenseFlags) return child;
    final color = level == LicenseLevel.block ? const Color(0xFFE5231B) : const Color(0xFFF08A00);
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
            decoration: BoxDecoration(border: Border.all(color: color, width: 2), borderRadius: BorderRadius.circular(6)),
            child: child,
          ),
          Positioned(
            top: -9,
            left: 10,
            right: 10,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                color: color,
                child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
