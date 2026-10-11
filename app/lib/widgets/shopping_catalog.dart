import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../my_basket.dart';
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
  static const _limit = kListLimit;
  late String _category = _categories.first;
  bool _onlySeason = false; // 걸러 보기 ①: 이번 달 제철인 것만
  bool _onlyMine = false; // 걸러 보기 ②: 내 장바구니에 담은 것만
  bool _showAll = false;

  /// 분류는 백엔드(market.py NAME_CATEGORY)에서 정함: 채소·과일·수산·곡물·두류·양념(·축산)
  List<String> get _categories {
    const order = ['채소', '과일', '수산', '곡물·두류', '양념', '축산'];
    final present = widget.catalog.map((e) => e['category'] as String).toSet();
    return [for (final c in order) if (present.contains(c)) c];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: MyBasket.instance, builder: (context, _) => _build(context));
  }

  Widget _build(BuildContext context) {
    final mine = MyBasket.instance;
    final inCategory = widget.catalog.where((e) => e['category'] == _category).toList();
    final seasonCount = inCategory.where((e) => e['in_season'] == true).length;
    final mineCount = inCategory.where((e) => mine.contains(e['name'] as String)).length;
    final rows = [
      for (final e in inCategory)
        if ((!_onlySeason || e['in_season'] == true) && (!_onlyMine || mine.contains(e['name'] as String))) e,
    ];
    final shown = _showAll ? rows : rows.take(_limit).toList();
    final asOf = widget.asOf == null ? null : DateTime.tryParse(widget.asOf!);
    final t = sectionThemes[Section.market]!;

    return ListSection(
      title: '장보기 시세',
      trailing: asOf == null ? '지난주 대비' : '${asOf.month}/${asOf.day} 기준 · 지난주 대비',
      children: [
        // 1줄: 분류(하나만 고름)
        Padding(
          padding: const EdgeInsets.only(top: 12),
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
        // 2줄: 걸러 보기(분류 안에서 겹쳐 적용) — 분류 알약과 모양을 달리해 헷갈리지 않게 체크 표시로
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Row(
            children: [
              _FilterToggle(
                label: '제철만',
                count: seasonCount,
                on: _onlySeason,
                onTap: () => setState(() {
                  _onlySeason = !_onlySeason;
                  _showAll = false;
                }),
              ),
              const SizedBox(width: 18),
              _FilterToggle(
                label: '담은 것만',
                count: mineCount,
                on: _onlyMine,
                icon: Icons.shopping_basket,
                iconColor: t.color,
                onTap: () => setState(() {
                  _onlyMine = !_onlyMine;
                  _showAll = false;
                }),
              ),
            ],
          ),
        ),
        Container(height: 1, color: AppColors.hair),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('해당하는 품목이 없어요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          ),
        for (final it in shown) _row(context, it),
        if (!_showAll && rows.length > _limit) ShowMoreButton(count: rows.length - _limit, onTap: () => setState(() => _showAll = true)),
      ],
    );
  }

  Widget _row(BuildContext context, Map<String, dynamic> it) {
    final change = (it['change'] as String?) ?? 'flat';
    final pct = it['pct'] as num?;
    final series = (it['series'] as List?)?.map((e) => (e as num).toDouble()).toList();
    final name = it['name'] as String;
    final inBasket = MyBasket.instance.contains(name);
    final line = ListLine(
      name: name,
      badge: it['in_season'] == true ? '제철' : null,
      nameIcon: inBasket ? Icons.shopping_basket : null,
      nameIconColor: sectionThemes[Section.market]!.color,
      sub: it['sub'] as String?,
      middle: series == null ? null : MiniSpark(series: series, color: changeColor(change)),
      value: '${formatNumber(it['price'] as num)}원',
      valueSub: pct == null ? null : changeLabel(change, pct: pct),
      valueSubColor: changeColor(change),
      onTap: () => showProduceSheet(context, it, widget.guide[it['guide']] as Map<String, dynamic>?),
    );
    // 왼쪽으로 밀면 담기/빼기 버튼이 보이고, 놓으면 바로 적용(줄은 제자리로 돌아옴)
    return Dismissible(
      key: ValueKey('b$name'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.3},
      confirmDismiss: (_) async {
        final added = await MyBasket.instance.toggle(name);
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              duration: const Duration(milliseconds: 1600),
              behavior: SnackBarBehavior.floating,
              backgroundColor: AppColors.ink,
              content: Text(added ? '$name을(를) 장바구니에 담았어요' : '$name을(를) 장바구니에서 뺐어요'),
            ));
        }
        return false;
      },
      background: Container(
        color: AppColors.ink,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(inBasket ? Icons.remove_shopping_cart_outlined : Icons.add_shopping_cart, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Text(inBasket ? '장바구니에서 빼기' : '장바구니에 담기', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
      child: Container(color: inBasket ? sectionThemes[Section.market]!.highlight.withValues(alpha: 0.35) : AppColors.background, child: line),
    );
  }
}

/// 체크 모양 걸러 보기 스위치: ☐ 제철만 7
class _FilterToggle extends StatelessWidget {
  const _FilterToggle({required this.label, required this.count, required this.on, required this.onTap, this.icon, this.iconColor});

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;
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
            const SizedBox(width: 5),
            Text('$count', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap, });

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
  Analytics.instance.track('produce_open', item['name'] as String);
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

    // 항목 목록: 아이콘(✓ 챙길 것 / ⚠ 피할 것 / ・ 보관) + 라벨 + 짧은 문구
    Widget rowsSection(String title, List? rows, {IconData? icon, Color? color}) {
      final items = (rows ?? const []).map((e) => (e as List).cast<String>()).toList();
      if (items.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: color), const SizedBox(width: 6)],
                Text(title, style: AppTheme.subheading.copyWith(color: color ?? AppColors.ink)),
              ],
            ),
            const SizedBox(height: 8),
            for (final r in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 78, child: Text(r[0], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.5))),
                    Expanded(child: Text(r[1], style: const TextStyle(fontSize: 15, height: 1.5))),
                  ],
                ),
              ),
          ],
        ),
      );
    }

    // 팁: 라벨 없이 한 줄씩 짧은 문장(없는 품목은 섹션 자체를 안 보여줌)
    Widget tipsSection(List? tips) {
      final lines = (tips ?? const []).cast<String>();
      if (lines.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFFB98600)),
                const SizedBox(width: 6),
                Text('알아두면 좋은 팁', style: AppTheme.subheading.copyWith(color: const Color(0xFFB98600))),
              ],
            ),
            const SizedBox(height: 8),
            for (final l in lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(l, style: const TextStyle(fontSize: 15, height: 1.5)),
              ),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '사진 · ${_shortCredit(image['credit'] as String?)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showPhotoInfo(context, image),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.fromLTRB(8, 4, 0, 4),
                      child: Icon(Icons.info_outline, size: 15, color: AppColors.inkSoft),
                    ),
                  ),
                ],
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
            const SizedBox(height: 14),
            ListenableBuilder(
              listenable: MyBasket.instance,
              builder: (context, _) {
                final inBasket = MyBasket.instance.contains(item['name'] as String);
                return GestureDetector(
                  onTap: () => MyBasket.instance.toggle(item['name'] as String),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: inBasket ? AppColors.ink : null,
                      border: Border.all(color: AppColors.ink),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      inBasket ? '내 장바구니에 담김 · 누르면 빼기' : '내 장바구니에 담기',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: inBasket ? Colors.white : AppColors.ink),
                    ),
                  ),
                );
              },
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
              rowsSection('이렇게 고르세요', guide!['good'] as List?, icon: Icons.check_circle, color: const Color(0xFF2F8F5B)),
              rowsSection('이런 건 피하세요', guide!['avoid'] as List?, icon: Icons.warning_amber_rounded, color: const Color(0xFFC4472B)),
              rowsSection('보관법', guide!['storage'] as List?, icon: Icons.inventory_2_outlined),
              tipsSection(guide!['tips'] as List?),
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


String _shortCredit(String? credit) {
  final c = (credit ?? '').trim();
  if (c.isEmpty) return 'Wikimedia Commons';
  return c.length > 28 ? '${c.substring(0, 27)}…' : c;
}

/// 사진 ⓘ: 작가·라이선스(링크)·원본 페이지·변경 사항을 한곳에(라이선스가 요구하는 표기).
void _showPhotoInfo(BuildContext context, Map<String, dynamic> image) {
  Future<void> open(String? url) async {
    if (url != null && url.isNotEmpty) await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  Widget row(String k, String v, {String? url}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onTap: url == null ? null : () => open(url),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 64, child: Text(k, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
              Expanded(
                child: Text(v, style: TextStyle(fontSize: 14, height: 1.4, decoration: url == null ? null : TextDecoration.underline)),
              ),
            ],
          ),
        ),
      );

  showModalBottomSheet<void>(
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
            Text('사진 정보', style: AppTheme.subheading),
            const SizedBox(height: 12),
            row('작가', (image['credit'] as String?) ?? 'Wikimedia Commons'),
            row('라이선스', (image['license'] as String?) ?? '', url: image['license_url'] as String?),
            row('원본', 'Wikimedia Commons에서 보기', url: image['page'] as String?),
            const Text('크기를 줄이고 일부를 잘라 사용했어요.', style: TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          ],
        ),
      ),
    ),
  );
}
