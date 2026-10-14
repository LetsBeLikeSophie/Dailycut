import 'package:flutter/material.dart';

import '../my_basket.dart';
import '../theme.dart';
import 'components.dart';

/// 생활 탭 맨 위: 내 장바구니 합계와 이번 달 추이. 위의 ‹ 장바구니 › 로 담은 품목을 한 칸씩 넘겨 보며
/// (고정 크기라 내용이 출렁이지 않음), 품목마다 가격·지난주 대비·추이가 바뀜.
/// 기본으로 담긴 품목은 없고, 아래 "장보기 시세"에서 담기 버튼을 누르면 여기에 나타남.
/// 그래프는 이번 달 1일~말일 축이고 서버가 쌓은 날짜까지만 선이 그려짐.
class BasketHero extends StatefulWidget {
  const BasketHero({
    super.key,
    required this.chartItems,
    required this.suggestions,
    required this.eyebrow,
    required this.onEyebrowTap,
    this.source,
  });

  final Map<String, dynamic> chartItems; // 품목 → {unit, price, week_ago, series:[{date,price}]}
  final List<String> suggestions;
  final String eyebrow;
  final VoidCallback onEyebrowTap;
  final String? source;

  @override
  State<BasketHero> createState() => _BasketHeroState();
}

class _BasketHeroState extends State<BasketHero> {
  int _page = 0; // 0 = 장바구니 합계, 1.. = 담은 품목
  final _mine = MyBasket.instance;

  @override
  void initState() {
    super.initState();
    _mine.suggestions = widget.suggestions;
    _mine.load();
    _mine.addListener(_changed);
  }

  @override
  void dispose() {
    _mine.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  List<ChartPoint> _points(Map<String, double> byDate) {
    final now = DateTime.now();
    final keys = byDate.keys.toList()..sort();
    return [
      for (final k in keys)
        if (DateTime.parse(k).month == now.month && DateTime.parse(k).year == now.year) ChartPoint(DateTime.parse(k).day, byDate[k]!),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final names = [for (final n in _mine.names) if (widget.chartItems[n] != null) n];
    if (names.isEmpty) return _empty(context);

    final pages = names.length + 1;
    final page = _page.clamp(0, pages - 1);
    final isTotal = page == 0;

    final String label;
    final double value;
    final double? weekRatio; // 지난주 대비 비율(현재/지난주)
    final List<ChartPoint> points;
    final String sub;

    if (isTotal) {
      label = '장바구니';
      value = names.fold<double>(0, (a, n) => a + (widget.chartItems[n]['price'] as num).toDouble());
      // 지난주 합계는 지난주 값이 있는 품목끼리만 비교
      final withWeek = [for (final n in names) if (widget.chartItems[n]['week_ago'] != null) n];
      final nowSum = withWeek.fold<double>(0, (a, n) => a + (widget.chartItems[n]['price'] as num).toDouble());
      final weekSum = withWeek.fold<double>(0, (a, n) => a + (widget.chartItems[n]['week_ago'] as num).toDouble());
      weekRatio = weekSum == 0 ? null : nowSum / weekSum;
      // 날짜별 합계: 담은 품목 모두 값이 있는 날만
      final perDay = <String, Map<String, double>>{};
      for (final n in names) {
        for (final e in (widget.chartItems[n]['series'] as List).cast<Map<String, dynamic>>()) {
          (perDay[e['date'] as String] ??= {})[n] = (e['price'] as num).toDouble();
        }
      }
      points = _points({
        for (final d in perDay.keys)
          if (perDay[d]!.length == names.length) d: perDay[d]!.values.fold<double>(0, (a, b) => a + b),
      });
      sub = '담은 ${names.length}품목 합계(1kg·1개 등 1단위씩)';
    } else {
      final n = names[page - 1];
      final it = widget.chartItems[n] as Map<String, dynamic>;
      label = n;
      value = (it['price'] as num).toDouble();
      final w = (it['week_ago'] as num?)?.toDouble();
      weekRatio = w == null ? null : value / w;
      points = _points({for (final e in (it['series'] as List).cast<Map<String, dynamic>>()) e['date'] as String: (e['price'] as num).toDouble()});
      sub = '$n 소매가 평균 · ${it['unit']}';
    }

    final pct = weekRatio == null ? null : (weekRatio - 1) * 100;
    final changeKey = pct == null || pct.abs() < 0.5 ? 'flat' : (pct > 0 ? 'up' : 'down');
    final emphasis = pct == null || pct.abs() < 0.5 ? '비슷해요' : '${pct.abs().toStringAsFixed(1)}% ${pct < 0 ? '내렸어요' : '올랐어요'}';
    final headline = isTotal
        ? (changeKey == 'flat' ? '이번 주 장바구니는 지난주와 $emphasis' : '이번 주 장바구니, 지난주보다 $emphasis')
        : (changeKey == 'flat' ? '$label은 지난주와 $emphasis' : '$label, 지난주보다 $emphasis');
    final deltaText = pct == null ? '지난주 가격 없음' : '${changeLabel(changeKey)} 지난주 대비 ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';

    return PageHero(
      section: Section.market,
      eyebrow: widget.eyebrow,
      onEyebrowTap: widget.onEyebrowTap,
      headline: headline,
      emphasis: emphasis,
      headlineLines: 2,
      source: widget.source,
      body: [
        ArrowSelector(label: label, index: page, count: pages, onChanged: (i) => setState(() => _page = i)),
        const SizedBox(height: 10),
        BigNumber(key: ValueKey('n$label'), to: value, unit: '원'),
        const SizedBox(height: 4),
        Text(deltaText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: changeColor(changeKey))),
        const SizedBox(height: 14),
        TrendChart(
          key: ValueKey('c$label${names.length}'),
          section: Section.market,
          points: points,
          format: (v) => '${formatNumber(v)}원',
        ),
        const SizedBox(height: 10),
        Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5)),
      ],
    );
  }

  Widget _empty(BuildContext context) {
    return PageHero(
      section: Section.market,
      eyebrow: widget.eyebrow,
      onEyebrowTap: widget.onEyebrowTap,
      headline: '장바구니를 채워 보세요',
      emphasis: '채워 보세요',
      headlineLines: 2,
      source: widget.source,
      body: [
        const Text(
          '아래 장보기 시세에서 품목 오른쪽 끝의 장바구니 버튼을 누르면 담겨요. 담은 품목의 합계 가격과 지난주 대비, 이번 달 추이를 여기서 한눈에 볼 수 있어요.',
          style: TextStyle(fontSize: 15, height: 1.6),
        ),
        const SizedBox(height: 16),
        if (widget.suggestions.isNotEmpty) ...[
          GestureDetector(
            onTap: () => _mine.addAll(widget.suggestions.where(widget.chartItems.containsKey)),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_shopping_cart, size: 18),
                  const SizedBox(width: 8),
                  Text('대표 ${widget.suggestions.length}품목으로 시작', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(widget.suggestions.join('·'), style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5)),
        ],
      ],
    );
  }
}
