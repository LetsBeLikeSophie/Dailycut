import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme.dart';

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
const kShowStubMarks = true;

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

String changeLabel(String change, {num? pct}) {
  final arrow = switch (change) {
    'up' => '▲',
    'down' => '▼',
    _ => '－',
  };
  if (pct == null) return arrow;
  return '$arrow ${pct.abs() == pct.abs().roundToDouble() ? pct.abs().round() : pct.abs()}%';
}

/// 출처 표기 — 기획 문서 원칙("모든 데이터 카드에는 출처를 표시").
class SourceTag extends StatelessWidget {
  const SourceTag({super.key, required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Text(
        '출처: $source',
        style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
      ),
    );
  }
}

/// 제목 속 일부 구절만 섹션 형광펜으로 강조(전체 문장은 그대로).
class HighlightText extends StatelessWidget {
  const HighlightText({
    super.key,
    required this.text,
    required this.color,
    this.emphasis,
    required this.style,
  });

  final String text;
  final Color color;
  final String? emphasis;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final e = emphasis;
    final i = e == null ? -1 : text.indexOf(e);
    if (e == null || i < 0) return Text(text, style: style);
    return Text.rich(
      TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, i)),
          TextSpan(
            text: e,
            style: TextStyle(backgroundColor: color.withValues(alpha: 0.85)),
          ),
          TextSpan(text: text.substring(i + e.length)),
        ],
      ),
    );
  }
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
    final big = GoogleFonts.notoSerifKr(
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
                style: GoogleFonts.notoSansKr(
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
  });

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
      child: Text(
        '↻ $text',
        style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
      ),
    );
    final front = _HeroFrame(
      section: section,
      onEyebrowTap: onEyebrowTap,
      eyebrow: eyebrow ?? t.label,
      headline: HighlightText(
        text: headline,
        emphasis: emphasis,
        color: t.highlight,
        style: AppTheme.displaySerif(
          size: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...body,
          if (source != null) SourceTag(source: source!),
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
  });

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
            const SizedBox(height: 86),
            GestureDetector(
              onTap: onEyebrowTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  onEyebrowTap == null ? eyebrow : '$eyebrow ▾',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
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
  const TrendChart({super.key, required this.section, required this.points});

  final Section section;
  final List<ChartPoint> points;

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
    final days = DateTime(now.year, now.month + 1, 0).day;
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    // 눈금: 1, 5, 10, 15, 20, 25, 말일
    final ticks = <int>[1, 5, 10, 15, 20, 25, days];
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
                        d == 1 || d == days ? '$d일' : '$d',
                        style: TextStyle(
                          fontSize: 11,
                          color: d == now.day
                              ? AppColors.ink
                              : AppColors.inkSoft,
                          fontWeight: d == now.day
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
  });

  final List<ChartPoint> points;
  final int days;
  final double progress;
  final Color fill;
  final Color dot;

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
      old.progress != progress || old.points != points || old.days != days;
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
class ListSection extends StatelessWidget {
  const ListSection({
    super.key,
    required this.title,
    this.trailing,
    this.stub = false,
    required this.children,
  });

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
                Expanded(child: Text(title, style: AppTheme.subheading)),
                if (trailing != null || stub)
                  Text(
                    [?trailing, if (stub) '예시 데이터'].join(' · '),
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.inkSoft,
                    ),
                  ),
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
  });

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
    return Container(
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
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
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
              constraints: const BoxConstraints(minWidth: 72),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value!,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (valueSub != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      valueSub!,
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
        ],
      ),
    );
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
        : MiniSpark(series: series, color: changeColor(change)),
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
