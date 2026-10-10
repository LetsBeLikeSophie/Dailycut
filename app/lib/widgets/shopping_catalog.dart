import 'package:flutter/material.dart';

import '../theme.dart';
import 'components.dart';

/// 생활 탭의 "장보기 시세": 카테고리(채소·과일·수산·축산·곡물)를 고르면 그 안의 품목이
/// "이름 · 제철 표시 · 작은 추이 · 가격과 지난주 대비" 한 줄로 나오고, 누르면 고르는 법·보관법·
/// 제철 시기·사진이 있는 상세가 열려요. 예전의 "지금 제철" 목록과 "채소·과일 시세" 목록을 하나로 합친 것.
class ShoppingCatalog extends StatefulWidget {
  const ShoppingCatalog({super.key, required this.catalog, required this.guide, this.asOf});

  final List<Map<String, dynamic>> catalog;
  final Map<String, dynamic> guide;
  final String? asOf;

  @override
  State<ShoppingCatalog> createState() => _ShoppingCatalogState();
}

class _ShoppingCatalogState extends State<ShoppingCatalog> {
  static const _limit = 12;
  late String _category = _categories.first;
  bool _onlySeason = false;
  bool _showAll = false;

  List<String> get _categories {
    const order = ['채소', '과일', '수산', '축산', '곡물·감자류'];
    final present = widget.catalog.map((e) => e['category'] as String).toSet();
    return [for (final c in order) if (present.contains(c)) c];
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.catalog.where((e) => e['category'] == _category && (!_onlySeason || e['in_season'] == true)).toList();
    final shown = _showAll ? rows : rows.take(_limit).toList();
    final seasonCount = widget.catalog.where((e) => e['category'] == _category && e['in_season'] == true).length;
    final asOf = widget.asOf == null ? null : DateTime.tryParse(widget.asOf!);

    return ListSection(
      title: '장보기 시세',
      trailing: asOf == null ? '지난주 대비' : '${asOf.month}/${asOf.day} 기준 · 지난주 대비',
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in _categories)
                _Pill(
                  label: c,
                  selected: c == _category,
                  onTap: () => setState(() {
                    _category = c;
                    _showAll = false;
                  }),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: GestureDetector(
            onTap: () => setState(() {
              _onlySeason = !_onlySeason;
              _showAll = false;
            }),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Icon(_onlySeason ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: AppColors.ink),
                  const SizedBox(width: 6),
                  Text('제철만 보기', style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text('이번 달 $seasonCount가지', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: AppColors.hair),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('이번 달 제철인 품목이 없어요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          ),
        for (final it in shown) _row(context, it),
        if (!_showAll && rows.length > _limit)
          GestureDetector(
            onTap: () => setState(() => _showAll = true),
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text('${rows.length - _limit}개 더 보기', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> it) {
    final change = (it['change'] as String?) ?? 'flat';
    final pct = it['pct'] as num?;
    final series = (it['series'] as List?)?.map((e) => (e as num).toDouble()).toList();
    return ListLine(
      name: it['name'] as String,
      badge: it['in_season'] == true ? '제철' : null,
      sub: it['sub'] as String?,
      middle: series == null ? null : MiniSpark(series: series, color: changeColor(change)),
      value: '${formatNumber(it['price'] as num)}원',
      valueSub: pct == null ? null : changeLabel(change, pct: pct),
      valueSubColor: changeColor(change),
      onTap: () => showProduceSheet(context, it, widget.guide[it['guide']] as Map<String, dynamic>?),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// 제철 시기 문자열: [10,11,12,1] → "10~1월" (이어지지 않으면 쉼표로).
String seasonText(List<int> months) {
  if (months.isEmpty) return '연중';
  final set = months.toSet();
  // 1월이 있고 12월이 있으면 연말~연초로 이어지는 구간의 시작을 찾음
  int start = months.first;
  for (final m in months) {
    final prev = m == 1 ? 12 : m - 1;
    if (!set.contains(prev)) {
      start = m;
      break;
    }
  }
  final run = <int>[];
  var cur = start;
  while (set.contains(cur) && run.length < 12) {
    run.add(cur);
    cur = cur == 12 ? 1 : cur + 1;
  }
  if (run.length == set.length) {
    return run.length == 1 ? '${run.first}월' : '${run.first}~${run.last}월';
  }
  return '${(set.toList()..sort()).join(', ')}월';
}

/// 품목 상세 시트: 사진, 가격, 제철 12개월 점, 고르는 법·보관법. 가이드가 없는 품목은 가격만.
Future<void> showProduceSheet(BuildContext context, Map<String, dynamic> item, Map<String, dynamic>? guide) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
    builder: (ctx) => _ProduceSheet(item: item, guide: guide),
  );
}

class _ProduceSheet extends StatelessWidget {
  const _ProduceSheet({required this.item, required this.guide});

  final Map<String, dynamic> item;
  final Map<String, dynamic>? guide;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[Section.market]!;
    final change = (item['change'] as String?) ?? 'flat';
    final pct = item['pct'] as num?;
    final months = ((guide?['season'] as List?) ?? const []).cast<int>();
    final nowMonth = DateTime.now().month;
    final inSeason = months.contains(nowMonth);
    final image = guide?['image'] as Map<String, dynamic>?;

    Widget section(String title, String? body) {
      if (body == null || body.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.subheading),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(fontSize: 16, height: 1.6)),
          ],
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  // 사진은 앱에 넣어둔 파일(assets/produce, 16:10으로 줄인 것)을 씀
                  child: image['asset'] != null
                      ? Image.asset(image['asset'] as String, fit: BoxFit.cover)
                      : ColoredBox(
                          color: t.highlight,
                          child: Center(child: Image.asset(t.shapeAsset, width: 72, height: 72)),
                        ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '사진: ${image['credit']} · ${image['license']} · Wikimedia Commons',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(item['name'] as String, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
                if (inSeason) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(999)),
                    child: const Text('지금 제철', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${formatNumber(item['price'] as num)}원',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  TextSpan(text: '  ${item['sub']}', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                  if (pct != null)
                    TextSpan(
                      text: '   지난주 대비 ${changeLabel(change, pct: pct)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: changeColor(change)),
                    ),
                ],
              ),
            ),
            if (guide != null) ...[
              const SizedBox(height: 22),
              Text('제철 · ${seasonText(months)}', style: AppTheme.subheading),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var m = 1; m <= 12; m++)
                    Expanded(
                      child: Column(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: months.contains(m) ? t.color : const Color(0xFFE9E9E9),
                              border: m == nowMonth ? Border.all(color: AppColors.ink, width: 1.5) : null,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('$m', style: TextStyle(fontSize: 11, color: m == nowMonth ? AppColors.ink : AppColors.inkSoft)),
                        ],
                      ),
                    ),
                ],
              ),
              section('고르는 법', guide!['pick'] as String?),
              section('보관법', guide!['storage'] as String?),
              if ((guide!['note'] as String?)?.isNotEmpty ?? false)
                Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Text(guide!['note'] as String, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6)),
                ),
              const SizedBox(height: 18),
              const Text(
                '고르는 법·보관법·제철 시기는 일반적인 상식을 정리한 데일리컷 편집 정보예요. 제철은 노지 재배 기준 대략이며 해마다·지역마다 다를 수 있어요. 가격은 한국농수산식품유통공사 소매가(상품 등급 평균)예요.',
                style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6),
              ),
            ] else
              const Padding(
                padding: EdgeInsets.only(top: 22),
                child: Text(
                  '이 품목의 고르는 법·제철 정보는 아직 정리하지 못했어요.',
                  style: TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
