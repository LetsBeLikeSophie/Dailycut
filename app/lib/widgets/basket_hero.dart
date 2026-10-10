import 'package:flutter/material.dart';

import '../theme.dart';
import 'components.dart';

/// 생활 탭 맨 위 숫자·그래프: 기본은 "장바구니 지수"(대표 8품목의 지난주 대비 평균, 지난주=100),
/// 아래 칩으로 품목을 고르면 그 품목의 가격과 이번 달 추이로 바뀜. 그래프는 항상 이번 달 1일~말일 축이고
/// 서버가 쌓은 날짜까지만 선이 그려짐(점이 적은 건 가격 이력을 아직 쌓는 중이라서).
class BasketBody extends StatefulWidget {
  const BasketBody({super.key, required this.basket, required this.chartItems});

  final Map<String, dynamic> basket;
  final Map<String, dynamic> chartItems; // 품목 → {unit, price, week_ago, series:[{date,price}]}

  @override
  State<BasketBody> createState() => _BasketBodyState();
}

class _BasketBodyState extends State<BasketBody> {
  static const _all = '장바구니';
  String _selected = _all;

  List<ChartPoint> _points(List raw, String valueKey) {
    final now = DateTime.now();
    return [
      for (final e in raw.cast<Map<String, dynamic>>())
        if (DateTime.parse(e['date'] as String).month == now.month)
          ChartPoint(DateTime.parse(e['date'] as String).day, (e[valueKey] as num).toDouble()),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isBasket = _selected == _all;
    late final num value;
    late final String? unit;
    late final int decimals;
    late final String deltaText;
    late final String changeKey;
    late final List<ChartPoint> points;
    late final String note;

    if (isBasket) {
      final pct = (widget.basket['change_pct'] as num).toDouble();
      changeKey = pct.abs() < 0.5 ? 'flat' : (pct > 0 ? 'up' : 'down');
      value = widget.basket['value'] as num;
      decimals = 1;
      unit = '지난주 = 100';
      deltaText = '${changeLabel(changeKey)} 지난주보다 ${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%';
      points = _points(widget.basket['series'] as List, 'value');
      note = widget.basket['note'] as String;
    } else {
      final it = widget.chartItems[_selected] as Map<String, dynamic>;
      final price = (it['price'] as num).toDouble();
      final week = (it['week_ago'] as num?)?.toDouble();
      final pct = week == null ? 0.0 : (price - week) / week * 100;
      changeKey = pct.abs() < 0.5 ? 'flat' : (pct > 0 ? 'up' : 'down');
      value = price;
      decimals = 0;
      unit = it['unit'] as String;
      deltaText = week == null ? '지난주 가격 없음' : '${changeLabel(changeKey)} 지난주 ${formatNumber(week)}원 (${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(1)}%)';
      points = _points(it['series'] as List, 'price');
      note = '$_selected 소매가 평균 · 이번 달 일별 추이';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BigNumber(key: ValueKey('n$_selected'), to: value, decimals: decimals, unit: unit),
        const SizedBox(height: 4),
        Text(
          deltaText,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: changeColor(changeKey)),
        ),
        const SizedBox(height: 14),
        TrendChart(key: ValueKey('c$_selected'), section: Section.market, points: points),
        const SizedBox(height: 10),
        Text(note, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in [_all, ...widget.chartItems.keys])
              GestureDetector(
                onTap: () => setState(() => _selected = name),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _selected == name ? AppColors.ink : AppColors.background,
                    border: Border.all(color: _selected == name ? AppColors.ink : AppColors.line),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: _selected == name ? FontWeight.w700 : FontWeight.w500,
                      color: _selected == name ? Colors.white : AppColors.ink,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
