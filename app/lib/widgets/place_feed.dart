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

  // 같은 조건의 요청은 ApiClient가 기억함(도서관 좌석은 1분, 나머지는 30분)
  static Future<Map<String, dynamic>> fetch(ApiClient api, Region r, PlaceKind kind) => api.places(kind: kind.name, sido: r.code, sgg: r.sgg);

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
          info: (d['note'] as String?)?.isNotEmpty ?? false ? InfoIconButton(title: '안내', lines: [d['note'] as String]) : null,
          children: [
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.hair),
            if (items.isEmpty)
              // 2026-10-16: 시군구에 없으면 상위 지역으로 채우지 않고 없다고 알림(누르면 지역 고르기)
              EmptyNote('${d['region']}에는 등록된 곳이 없어요.\n다른 지역으로 찾아보세요 ›', vertical: 40, onTap: () => showRegionPicker(context)),
            ExpandableList(
              key: ValueKey('place${_kind.name}'),
              unit: '곳',
              children: [
                for (final it in items)
                  ListLine(
                    name: it['name'] as String,
                    // 캠핑의 사이트 수(span)는 값 칸이 비면 안 보여서 설명 줄에 붙임
                    sub: _kind == PlaceKind.camp && (it['span'] as String?)?.isNotEmpty == true ? '${it['sub']} · ${it['span']}' : it['sub'] as String?,
                    middle: it['pet'] == null ? null : _PetBadge(level: (it['pet'] as Map)['level'] as String, label: (it['pet'] as Map)['label'] as String),
                    value: (it['tag'] as String?)?.isEmpty ?? true ? null : it['tag'] as String,
                    valueSub: _kind == PlaceKind.camp || ((it['span'] as String?)?.isEmpty ?? true) ? null : it['span'] as String,
                    onTap: () => showItemSheet(context, it, 'place-${_kind.name}'),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 반려동물 동반 배지(2026-10-16): 함께 갈 수 있는 크기를 발바닥 개수로 — 1개 소형견만 · 2개 중·소형견 · 3개 모든 크기(나들이 초록).
/// 안내견만·조건 있음·크기 안내 없는 동반 가능은 회색 발바닥 하나, 동반 불가는 금지 표시. 글은 아래에 작게.
class _PetBadge extends StatelessWidget {
  const _PetBadge({required this.level, required this.label});

  final String level;
  final String label;

  @override
  Widget build(BuildContext context) {
    final accent = sectionThemes[Section.place]!.color;
    final (sizes, color) = switch (level) {
      'small' => (const [14.0], accent),
      'mid' => (const [14.0, 14.0], accent),
      'all' => (const [14.0, 14.0, 14.0], accent),
      'no' => (const <double>[], AppColors.inkSoft),
      _ => (const [14.0], AppColors.inkSoft), // guide · other · ok
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (level == 'no') Icon(Icons.block, size: 15, color: color),
            for (final z in sizes) Icon(Icons.pets, size: z, color: color),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
      ],
    );
  }
}
