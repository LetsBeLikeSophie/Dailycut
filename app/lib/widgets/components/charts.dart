// 공용 부품 — 추이 차트(TrendChart)·작은 그래프(MiniSpark)
// (2026-10-29: 1,787줄짜리 components.dart를 주제별로 나눔. 불러오는 쪽은 그대로 `widgets/components.dart` 하나만 import 하면 됨.)
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'basics.dart';

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
