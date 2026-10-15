import 'package:flutter/material.dart';

import '../analytics.dart';
import '../theme.dart';
import 'components.dart';

/// 축산물 시세 한 줄: 이름·100g당 가격·지난주 대비(다른 시세 목록과 같은 모양). 누르면 평년 대비·가격 범위가 있는 상세.
Widget livestockLine(BuildContext context, Map<String, dynamic> it) {
  final change = (it['change'] as String?) ?? 'flat';
  final pct = it['pct'] as num?;
  return ListLine(
    name: it['label'] as String,
    sub: it['sub'] as String?,
    value: it['value'] as String,
    valueSub: pct == null ? null : changeLabel(change, pct: pct),
    valueSubColor: changeColor(change),
    onTap: it['detail'] == null ? null : () => showLivestockSheet(context, it),
  );
}

Future<void> showLivestockSheet(BuildContext context, Map<String, dynamic> it) {
  Analytics.instance.track('life_open', 'livestock');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    builder: (_) => _LivestockSheet(item: it),
  );
}

class _LivestockSheet extends StatelessWidget {
  const _LivestockSheet({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final d = (item['detail'] as Map<String, dynamic>);
    String won(num? v) => v == null ? '-' : '${formatNumber(v)}원';

    // 비교 줄: 라벨 · 기준값 · 변화율(▲▼ + 색)
    Widget compare(String label, num? base, num? pct) {
      final key = pct == null || pct.abs() < 0.5 ? 'flat' : (pct > 0 ? 'up' : 'down');
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
            Text(won(base), style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(width: 14),
            SizedBox(
              width: 74,
              child: Text(
                pct == null ? '-' : changeLabel(key, pct: pct),
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: changeColor(key)),
              ),
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
            Text(item['label'] as String, style: AppTheme.displaySerif(size: 26, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text.rich(
              TextSpan(children: [
                TextSpan(text: won(d['price'] as num?), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                const TextSpan(text: '  100g', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
              ]),
            ),
            const SizedBox(height: 22),
            Container(height: 1, color: AppColors.ink),
            compare('지난주 대비', d['week'] as num?, d['week_pct'] as num?),
            Container(height: 1, color: AppColors.hair),
            compare('평년 대비', d['normal'] as num?, d['normal_pct'] as num?),
            Container(height: 1, color: AppColors.hair),
            if (d['min'] != null && d['max'] != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    const Expanded(child: Text('가격 범위(최저~최고)', style: TextStyle(fontSize: 16))),
                    Text('${won(d['min'] as num?)} ~ ${won(d['max'] as num?)}', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            const Text(
              '평년은 과거 같은 시기의 평균 가격이에요.',
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
