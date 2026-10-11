import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../theme.dart';
import 'components.dart';
import 'zoom_image.dart';

/// 지역(시군구, 없으면 시도)의 전통시장 목록. 시설(주차장·아케이드 등)로 거르고, 시설 많은 순·가나다순·
/// 시군구순으로 정렬하고, 누르면 주소·시설·지도 링크(있으면 사진)가 있는 상세가 열려요.
/// 데이터(소상공인시장진흥공단 전통시장현황)에 휴장일·좌표가 없어서 "가까운 순"은 아직 못 하고,
/// 지도 링크는 시장 이름과 주소로 검색하는 방식이에요.
class MarketList extends StatefulWidget {
  const MarketList({super.key, required this.api, required this.markets, required this.scope, required this.total, required this.stub});

  final ApiClient api;
  final List<Map<String, dynamic>> markets;
  final String scope;
  final int total;
  final bool stub;

  @override
  State<MarketList> createState() => _MarketListState();
}

enum _Sort { facilities, name, sigungu }

class _MarketListState extends State<MarketList> {
  static const _filters = ['전체', '주차장', '아케이드', '휴게실', '카트', '수유실'];
  static const _limit = kListLimit;
  String _filter = '전체';
  _Sort _sort = _Sort.facilities;
  bool _showAll = false;

  List<Map<String, dynamic>> get _rows {
    var rows = widget.markets.where((m) => _filter == '전체' || ((m['facilities'] as List?) ?? const []).contains(_filter)).toList();
    switch (_sort) {
      case _Sort.facilities:
        rows.sort((a, b) {
          final c = ((b['facilities'] as List?) ?? const []).length.compareTo(((a['facilities'] as List?) ?? const []).length);
          return c != 0 ? c : (a['title'] as String).compareTo(b['title'] as String);
        });
      case _Sort.name:
        rows.sort((a, b) => (a['title'] as String).compareTo(b['title'] as String));
      case _Sort.sigungu:
        rows.sort((a, b) {
          final c = ((a['sigungu'] as String?) ?? '').compareTo((b['sigungu'] as String?) ?? '');
          return c != 0 ? c : (a['title'] as String).compareTo(b['title'] as String);
        });
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    final shown = _showAll ? rows : rows.take(_limit).toList();
    return ListSection(
      title: '${widget.scope} 전통시장',
      trailing: widget.stub ? null : '총 ${widget.total}곳',
      stub: widget.stub,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final f in _filters)
                _MiniPill(
                  label: f,
                  selected: _filter == f,
                  onTap: () => setState(() {
                    _filter = f;
                    _showAll = false;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Text('정렬', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
            const SizedBox(width: 8),
            for (final (label, s) in const [('시설 많은 순', _Sort.facilities), ('가나다순', _Sort.name), ('시군구별', _Sort.sigungu)])
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => setState(() => _sort = s),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: _sort == s ? FontWeight.w700 : FontWeight.w400,
                        color: _sort == s ? AppColors.ink : AppColors.inkSoft,
                        decoration: _sort == s ? TextDecoration.underline : null,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Container(height: 1, color: AppColors.hair),
        if (shown.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('조건에 맞는 시장이 없어요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          ),
        for (final m in shown)
          ListLine(
            name: m['title'] as String,
            sub: m['sigungu'] == null ? (m['meta'] as String?) : [m['sigungu'], ...(((m['facilities'] as List?) ?? const []).take(3))].join(' · '),
            onTap: () => _showDetail(context, m),
          ),
        if (!_showAll && rows.length > _limit)
          ShowMoreButton(count: rows.length - _limit, unit: '곳', onTap: () => setState(() => _showAll = true)),
      ],
    );
  }

  void _showDetail(BuildContext context, Map<String, dynamic> m) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      builder: (_) => _MarketSheet(api: widget.api, market: m),
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.ink),
        ),
      ),
    );
  }
}

class _MarketSheet extends StatelessWidget {
  const _MarketSheet({required this.api, required this.market});

  final ApiClient api;
  final Map<String, dynamic> market;

  static const _all = ['주차장', '아케이드', '휴게실', '카트', '수유실'];

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) {
    final name = market['title'] as String;
    final sigungu = market['sigungu'] as String;
    final addr = market['addr'] as String;
    final have = (market['facilities'] as List).cast<String>();
    final query = Uri.encodeComponent('$name $sigungu');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('${market['type']} · $sigungu', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(height: 20),
            Text('주소', style: AppTheme.subheading),
            const SizedBox(height: 6),
            SelectableText(addr, style: const TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _LinkButton(label: '네이버지도', onTap: () => _open('https://map.naver.com/p/search/$query'))),
                const SizedBox(width: 10),
                Expanded(child: _LinkButton(label: '카카오맵', onTap: () => _open('https://map.kakao.com/?q=$query'))),
              ],
            ),
            const SizedBox(height: 24),
            Text('시설', style: AppTheme.subheading),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in _all)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: have.contains(f) ? AppColors.ink : AppColors.background,
                      border: Border.all(color: have.contains(f) ? AppColors.ink : AppColors.line),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      have.contains(f) ? f : '$f 없음',
                      style: TextStyle(fontSize: 13, color: have.contains(f) ? Colors.white : AppColors.inkSoft, fontWeight: FontWeight.w500),
                    ),
                  ),
              ],
            ),
            FutureBuilder<Map<String, dynamic>>(
              future: api.marketDetail(name: name, sigungu: sigungu),
              builder: (context, snap) {
                final d = snap.data;
                if (d == null || d['found'] != true) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ZoomImage(provider: NetworkImage('${api.baseUrl}${d['image']}')),
                      const SizedBox(height: 6),
                      Text('사진: ${d['credit']} · ${d['license']}', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 22),
            const Text(
              '소상공인시장진흥공단 전통시장현황(2026-08-04 기준)이에요. 휴장일·영업시간은 이 데이터에 없어서 방문 전에 지도에서 확인해 주세요.',
              style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(8)),
        child: Text('$label에서 보기', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
