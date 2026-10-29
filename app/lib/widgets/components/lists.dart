// 공용 부품 — 목록 부품(ListSection·ListLine·RankRow·SeasonRow·ArrowSelector·더 보기)
// (2026-10-29: 1,787줄짜리 components.dart를 주제별로 나눔. 불러오는 쪽은 그대로 `widgets/components.dart` 하나만 import 하면 됨.)
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'basics.dart';
import 'charts.dart';

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
