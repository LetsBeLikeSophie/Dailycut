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
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.section,
    required this.title,
    this.highlight,
    this.meta,
  });

  final Section section;
  final String title;
  final String? highlight;
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    return _CardShell(
      emphasized: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(section: section),
          const SizedBox(height: 12),
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
