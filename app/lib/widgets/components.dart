import 'package:flutter/material.dart';
import '../theme.dart';

/// 기획 문서 "컴포넌트" 표의 부품들. 화면은 이 조합으로만 만들고,
/// 색을 바꾸려면 SectionTheme 표만 고치면 되게 함.

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.section, this.link});

  final Section section;
  final String? link;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return Row(
      children: [
        Text(t.shape, style: TextStyle(color: t.color, fontSize: 18)),
        const SizedBox(width: 8),
        Text(t.label, style: AppTheme.displaySerif()),
        const Spacer(),
        if (link != null)
          Text(link!, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
      ],
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

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child, this.emphasized = false});

  final Widget child;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.line, width: emphasized ? 1.5 : 1),
      ),
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
            // 대신 도형 글리프만 작게 보여줌 — 숫자 "0"이 그대로 찍히던
            // 문제 수정(2026-09-29).
            child: rank > 0
                ? Text(
                    '$rank',
                    style: TextStyle(
                      color: t.color,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  )
                : Text(t.shape, style: TextStyle(color: t.color, fontSize: 12)),
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
    return _CardShell(
      emphasized: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            SectionHeader(section: section),
            const SizedBox(height: 12),
          ],
          Text(title, style: const TextStyle(fontSize: 15)),
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

/// "지금 제철인 것들"을 강조된 카드 하나로 모아 보여줌. 2026-09-29:
/// "가격 순위보다 지금 뭐가 제철인지가 장보기 결정에 더 중요하다"는
/// 피드백으로, 화면 맨 위(hero 자리)에 오도록 만듦 — 제철 = 싸고
/// 품질 좋은 시기라는 걸 한눈에 보여주는 게 목적이라 가격 숫자는 안 넣고
/// 품목명 + 제철 시기만 나열함.
class SeasonalHero extends StatelessWidget {
  const SeasonalHero({super.key, required this.section, required this.items});

  final Section section;
  final List<({String name, String meta})> items;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return _CardShell(
      emphasized: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('지금 제철', style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          const SizedBox(height: 6),
          _Highlight(text: items.first.name, color: t.highlight),
          const SizedBox(height: 4),
          Text(items.first.meta, style: const TextStyle(color: AppColors.inkSoft, fontSize: 12)),
          if (items.length > 1) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                for (final it in items.skip(1))
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: it.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        TextSpan(
                          text: '  ${it.meta}',
                          style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
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
    this.showHeader = true,
  });

  final Section section;
  final String label;
  final String value;
  final String change; // up / down / flat
  final List<double> series;
  final bool showHeader;

  Color get _changeColor => switch (change) {
        'up' => AppColors.up,
        'down' => AppColors.down,
        _ => AppColors.inkSoft,
      };

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return _CardShell(
      emphasized: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            SectionHeader(section: section),
            const SizedBox(height: 12),
          ],
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
  const _Highlight({required this.text, required this.color});

  final String text;
  final Color color;

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
          child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}
