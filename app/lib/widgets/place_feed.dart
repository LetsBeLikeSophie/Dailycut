import 'package:flutter/material.dart';

import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'benefit_feed.dart';
import 'components.dart';

/// 장소 탭의 한 구분(도서관 열람실 빈자리 · 캠핑장 · 반려동물 동반 · 웰니스 · 걷기길 중 하나). 구분 전환은 바깥(SegmentedHost)이 함(2026-10-16).
/// 서버가 줄여서 준 항목({name, sub, tag, span, detail, url, link_label})을 청약·대출 목록과 같은 모양으로 보여주고,
/// 누르면 같은 상세 시트가 열림. 지역은 앱 전체 지역(시도·시군구)을 따름. 사진은 쓰지 않음(저작권 구분 확인 전).
enum PlaceKind { library, camp, pet, wellness, trail }

const _labels = {
  PlaceKind.library: '도서관',
  PlaceKind.camp: '캠핑',
  PlaceKind.pet: '반려동물',
  PlaceKind.wellness: '웰니스',
  PlaceKind.trail: '걷기길',
};

String placeKindLabel(PlaceKind k) => _labels[k]!;

const _titles = {
  PlaceKind.library: '도서관 열람실 빈자리',
  PlaceKind.camp: '근처 캠핑장',
  PlaceKind.pet: '반려동물과 갈 만한 곳',
  PlaceKind.wellness: '웰니스 관광지',
  PlaceKind.trail: '걷기길·자전거길',
};

class PlaceFeed extends StatefulWidget {
  const PlaceFeed({super.key, required this.api, required this.region, required this.kind});

  final ApiClient api;
  final Region region;
  final PlaceKind kind;

  static final Map<String, ({DateTime at, Future<Map<String, dynamic>> future})> _memo = {};

  static Future<Map<String, dynamic>> fetch(ApiClient api, Region r, PlaceKind kind) {
    final key = '${kind.name}/${r.code}/${r.sgg ?? ''}';
    final hit = _memo[key];
    // 도서관 좌석은 자주 바뀌니 짧게(2분), 나머지는 길게
    final ttl = kind == PlaceKind.library ? 2 : 30;
    if (hit != null && DateTime.now().difference(hit.at).inMinutes < ttl) return hit.future;
    final f = api.places(kind: kind.name, sido: r.code, sgg: r.sgg);
    _memo[key] = (at: DateTime.now(), future: f);
    f.catchError((_) {
      _memo.remove(key);
      return <String, dynamic>{};
    });
    return f;
  }

  @override
  State<PlaceFeed> createState() => _PlaceFeedState();
}

class _PlaceFeedState extends State<PlaceFeed> {
  PlaceKind get _kind => widget.kind;
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() => PlaceFeed.fetch(widget.api, widget.region, _kind);

  Widget _message(Widget child, {VoidCallback? onTap}) => ListSection(
        title: _titles[_kind]!,
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 48), child: Center(child: child)),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey(_kind), // 종류를 바꾸면 새로 받는 동안 이전 종류의 목록이 남아 보이지 않게(FutureBuilder는 옛 데이터를 들고 있음)
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (snap.hasError || (d != null && d['live'] != true)) {
          return _message(const Text('목록을 불러오지 못했어요. 눌러서 다시 시도', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)), onTap: () => setState(() => _future = _load()));
        }
        if (d == null) {
          return _message(const LoadingNote());
        }
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        return ListSection(
          title: _titles[_kind]!,
          trailing: '${d['total']}곳',
          children: [
            if (d['scope_note'] != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(d['scope_note'] as String, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6))),
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.hair),
            if (items.isEmpty)
              const EmptyNote('이 지역에는 등록된 곳이 없어요.', vertical: 40),
            ExpandableList(
              key: ValueKey('place${_kind.name}'),
              unit: '곳',
              children: [
                for (final it in items)
                  ListLine(
                    name: it['name'] as String,
                    sub: it['sub'] as String?,
                    value: (it['tag'] as String?)?.isEmpty ?? true ? null : it['tag'] as String,
                    valueSub: (it['span'] as String?)?.isEmpty ?? true ? null : it['span'] as String,
                    onTap: () => showItemSheet(context, it, 'place-${_kind.name}'),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                '${d['region']} 기준 · ${d['note'] ?? ''}',
                style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6),
              ),
            ),
          ],
        );
      },
    );
  }
}
