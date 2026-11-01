import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';
import 'map_links.dart';

/// 종이(지류) 지역사랑상품권 "살 수 있는 곳"(2026-11-01): 한국조폐공사 지류 판매지점정보·지점별 재고정보.
/// 지점마다 5천·1만·5만원권의 재고 있음/없음이 와서 "동났는지"를 볼 수 있음(모바일·카드 상품권의 예산 소진은 해당 없음).
/// 자료가 있는 지역은 일부뿐(춘천·군산·강릉 …)이라 자료가 없거나 못 받으면 구역 전체를 숨김.
class PaperVoucherSection extends StatefulWidget {
  const PaperVoucherSection({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  @override
  State<PaperVoucherSection> createState() => _PaperVoucherSectionState();
}

String _denom(int won) => won >= 10000 ? '${won ~/ 10000}만' : '${won ~/ 1000}천';

class _PaperVoucherSectionState extends State<PaperVoucherSection> {
  late final Future<Map<String, dynamic>> _future = widget.api.localCurrencyPaper(sido: widget.region.code, sgg: widget.region.sgg);

  static const _info = [
    '종이 상품권을 파는 은행·새마을금고·농협 지점이에요.',
    '재고는 권종(5천·1만·5만원 등)마다 있음/없음만 알려 줘요. 몇 장 남았는지는 몰라요.',
    '이 자료를 올리는 지역은 일부뿐이라, 자료가 없는 지역에서는 이 구역이 안 보여요.',
  ];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null || d['live'] != true || d['empty'] == true) return const SizedBox.shrink();
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        final asof = d['asof'] as String? ?? '';
        return ListSection(
          title: '종이 상품권 살 수 있는 곳',
          trailing: (d['with_stock'] as int) > 0 ? '재고 있는 곳 ${d['with_stock']}곳' : null,
          info: const InfoIconButton(title: '종이 상품권 안내', lines: _info),
          children: [
            ExpandableList(
              unit: '곳',
              limit: 5,
              children: [
                for (final it in items)
                  ListLine(
                    name: it['name'] as String,
                    sub: [if ((it['dong'] as String).isNotEmpty) it['dong'], it['gt']].join(' · '),
                    value: _stockText(it)?.$1,
                    valueSub: _stockText(it)?.$2,
                    valueColor: _stockText(it)?.$3,
                    onTap: () => _showBranch(context, it, asof),
                  ),
              ],
            ),
            DataMeta(rows: [
              const DataMetaRow('출처', '한국조폐공사 지류 판매지점·재고정보'),
              DataMetaRow('기준일', dotDate(asof)),
            ]),
          ],
        );
      },
    );
  }

  /// (재고 있음/없음, 있는 권종, 색). 재고 정보가 없는 지점이면 null.
  (String, String?, Color?)? _stockText(Map<String, dynamic> it) {
    final st = (it['stock'] as List?)?.cast<Map<String, dynamic>>();
    if (st == null || st.isEmpty) return null;
    final have = [for (final x in st) if (x['have'] == true) _denom(x['denom'] as int)];
    return have.isEmpty ? ('재고 없음', null, AppColors.inkSoft) : ('재고 있음', '${have.join('·')}원권', null);
  }

  void _showBranch(BuildContext context, Map<String, dynamic> it, String asof) {
    final name = it['name'] as String;
    final addr = it['addr'] as String;
    final phone = it['phone'] as String?;
    final st = (it['stock'] as List?)?.cast<Map<String, dynamic>>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      builder: (ctx) => SheetFrame(
        title: name,
        sub: '${it['gt']} · 종이 상품권 판매',
        gapAfterHeader: 20,
        infoLines: _info,
        children: [
          if (st != null && st.isNotEmpty) ...[
            Text('권종별 재고', style: AppTheme.subheading),
            const SizedBox(height: 6),
            Container(height: 1, color: AppColors.ink),
            for (final x in st)
              ListLine(
                name: '${formatNumber(x['denom'] as int)}원권',
                value: x['have'] == true ? '있음' : '없음',
                valueColor: x['have'] == true ? null : AppColors.inkSoft,
              ),
            const SizedBox(height: 18),
          ],
          Text('주소', style: AppTheme.subheading),
          const SizedBox(height: 6),
          SelectableText(addr, style: const TextStyle(fontSize: 16, height: 1.5)),
          if (phone != null) ...[
            const SizedBox(height: 18),
            Text('전화', style: AppTheme.subheading),
            const SizedBox(height: 6),
            SelectableText(phone, style: const TextStyle(fontSize: 16, height: 1.5)),
          ],
          const SizedBox(height: 18),
          ActionButton(vertical: 12, label: '지도에서 보기', onTap: () => openMapChooser(context, {'name': name, 'q': '$name $addr', 'lat': it['lat'], 'lng': it['lng']})),
          if (phone != null) ...[
            const SizedBox(height: 10),
            ActionButton(vertical: 12, label: '전화 걸기', onTap: () => launchUrl(Uri.parse('tel:${phone.replaceAll('-', '')}'))),
          ],
          DataMeta(top: 20, rows: [
            DataMetaRow('재고 기준일', dotDate(asof)),
            const DataMetaRow('출처', '한국조폐공사 지류 판매지점·재고정보'),
            const DataMetaRow('가기 전에', '전화로 재고 확인'),
          ]),
        ],
      ),
    );
  }
}
