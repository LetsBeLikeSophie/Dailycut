import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import 'components.dart';
import 'map_links.dart';
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
  static const _filters = ['주차장', '아케이드', '휴게실', '카트', '수유실'];
  static const _limit = kListLimit;
  // 여러 개를 골라 겹쳐 걸 수 있고(고른 시설을 모두 갖춘 시장만), 다시 누르면 풀림. 비어 있으면 "전체".
  final Set<String> _selected = {};
  _Sort _sort = _Sort.facilities;
  bool _showAll = false;

  List<Map<String, dynamic>> get _rows {
    var rows = widget.markets.where((m) {
      final have = ((m['facilities'] as List?) ?? const []).cast<String>();
      return _selected.every(have.contains);
    }).toList();
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
              PillChip(
                label: '전체',
                selected: _selected.isEmpty,
                onTap: () => setState(() {
                  _selected.clear();
                  _showAll = false;
                }),
              ),
              for (final f in _filters)
                PillChip(
                  label: f,
                  selected: _selected.contains(f),
                  onTap: () => setState(() {
                    _selected.contains(f) ? _selected.remove(f) : _selected.add(f);
                    _showAll = false;
                  }),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
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
          const EmptyNote('조건에 맞는 시장이 없어요.', vertical: 24),
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

class _MarketSheet extends StatelessWidget {
  const _MarketSheet({required this.api, required this.market});

  final ApiClient api;
  final Map<String, dynamic> market;

  static const _all = ['주차장', '아케이드', '휴게실', '카트', '수유실'];


  @override
  Widget build(BuildContext context) {
    final name = market['title'] as String;
    final sigungu = market['sigungu'] as String;
    final addr = market['addr'] as String;
    final have = (market['facilities'] as List).cast<String>();
    return SheetFrame(
      title: name,
      sub: '${market['type']} · $sigungu',
      gapAfterHeader: 20,
      infoLines: const ['소상공인시장진흥공단 전통시장현황(2026-08-04 기준)이에요.', '휴장일·영업시간은 이 데이터에 없어서 방문 전에 지도에서 확인해 주세요.'],
      children: [
            Text('주소', style: AppTheme.subheading),
            const SizedBox(height: 6),
            SelectableText(addr, style: const TextStyle(fontSize: 16, height: 1.5)),
            const SizedBox(height: 14),
            // 좌표가 없어서 도로명 주소로 찾음(시장 이름보다 정확)
            ActionButton(vertical: 12, label: '지도에서 보기', onTap: () => openMapChooser(context, {'name': name, 'q': addr.isNotEmpty ? addr : '$name $sigungu'})),
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
                      Row(
                        children: [
                          Expanded(child: Text('사진 · ${d['credit']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft))),
                          InfoIconButton(title: '사진 정보', lines: ['사진: ${d['credit']}', '이용 조건: ${d['license']}']),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
      ],
    );
  }
}

