import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';
import 'components.dart';

/// 금융감독원 금융상품 한눈에 순위 한 줄: 순위 · 상품명(작게 금융회사·업권·기간) · 금리(작게 기본/최저).
/// 누르면 우대 조건·가입 방법·금리표가 있는 상세가 열려요. 예시 데이터(상세 없음)면 기존 한 줄로.
Widget financeLine(BuildContext context, Map<String, dynamic> it) {
  if (it['company'] == null) {
    return RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String);
  }
  final sub = [it['company'], it['group'], if (it['term'] != null) it['term']].join(' · ');
  return ListLine(
    leading: SizedBox(
      width: 20,
      child: Text('${it['rank']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    ),
    name: it['product'] as String,
    sub: sub,
    value: it['value'] as String,
    valueSub: it['value_sub'] as String?,
    onTap: () => showFinanceSheet(context, it),
  );
}

Future<void> showFinanceSheet(BuildContext context, Map<String, dynamic> it) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
    builder: (_) => _FinanceSheet(item: it),
  );
}

class _FinanceSheet extends StatelessWidget {
  const _FinanceSheet({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final info = ((item['info'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final rates = ((item['rates'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final link = item['link'] as String?;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.ink, borderRadius: BorderRadius.circular(999)),
                  child: Text(item['group'] as String, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(item['company'] as String, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
              ],
            ),
            const SizedBox(height: 8),
            Text(item['product'] as String, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '연 ${item['value']}',
                    style: AppTheme.displaySerif(size: 36, fontWeight: FontWeight.w900, height: 1.1),
                  ),
                  TextSpan(
                    text: '  ${[item['value_sub'], item['term']].where((e) => e != null).join(' · ')}',
                    style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                  ),
                ],
              ),
            ),
            if (rates.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text((item['rates_title'] as String?) ?? '기간별 금리', style: AppTheme.subheading),
              const SizedBox(height: 4),
              Container(height: 1, color: AppColors.ink),
              for (final r in rates)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hair))),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(r['label'] as String, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                      const SizedBox(width: 12),
                      Text(r['value'] as String, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
                    ],
                  ),
                ),
            ],
            for (final r in info)
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r['label'] as String, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                    const SizedBox(height: 4),
                    SelectableText(r['value'] as String, style: const TextStyle(fontSize: 16, height: 1.55)),
                  ],
                ),
              ),
            if (link != null) ...[
              const SizedBox(height: 26),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(8)),
                  child: const Text('금융상품한눈에에서 비교하기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              '금융감독원 금융상품한눈에에 금융회사가 공시한 정보예요. 금리는 우대조건을 모두 채웠을 때의 최고 금리이고, 실제 가입 가능 여부와 조건은 금융회사에서 확인해 주세요.',
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}
