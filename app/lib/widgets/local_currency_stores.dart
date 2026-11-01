import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';
import 'map_links.dart';

/// 지역화폐 "상품권 쓸 수 있는 가게"(2026-11-01): 한국조폐공사 가맹점 기본정보(모바일·카드)에서 계속사업자만, 업종 칩·가게 이름·동네로 찾음.
/// 통계만 있으면 "그래서 나는?"에 답이 없다는 의견(사용자)에서 나옴 — 눌러서 주소·전화·지도로 이어지게.
/// 정보 기준일이 가게마다 달라(2025~2026) 그 뒤에 닫았을 수 있음 → 시트에 기준일과 "가기 전에 전화로" 안내.
const _cats = <(String, String)>[
  ('food', '음식점'),
  ('cafe', '카페·주점'),
  ('mart', '마트·편의점'),
  ('grocery', '식료품'),
  ('pharm', '약국·화장품'),
  ('beauty', '미용·세탁'),
  ('clinic', '병원·의원'),
  ('academy', '학원'),
  ('stay', '숙박'),
  ('', '전체'),
];

class StoreFinder extends StatefulWidget {
  const StoreFinder({super.key, required this.api, required this.region, this.stats});

  final ApiClient api;
  final Region region;

  /// 지역화폐 통계 요청(동네 칩에 씀). 늦게 와도 가게 찾기는 먼저 돌고, 실패하면 동네 칩만 없음.
  final Future<Map<String, dynamic>>? stats;

  @override
  State<StoreFinder> createState() => StoreFinderState();
}

class StoreFinderState extends State<StoreFinder> {
  String _cat = 'food';
  String _q = '';
  String? _emd; // 읍면동 8자리 코드
  List<Map<String, dynamic>> _items = [];
  int _total = 0;
  int _page = 1;
  int _show = 6; // 처음엔 6곳만(아래 "내 또래"가 멀어지지 않게), 더 보기로 늘림
  bool _more = false;
  bool _loading = true;
  bool _failed = false;
  int _token = 0; // 늦게 온 옛 요청이 새 결과를 덮지 않게
  Timer? _debounce;
  final _qCtl = TextEditingController();
  List<Map<String, dynamic>> _dongs = const [];
  ({String code, String name})? _extraDong; // 칩에 없는 동네(내 또래 줄에서 넘어온 것)
  ({String key, String name})? _extraCat; // 칩에 없는 업종

  static const _ksicToChip = {'561': 'food', '562': 'cafe', '471': 'mart', '472': 'grocery', '477': 'pharm', '961': 'beauty', '862': 'clinic', '856': 'academy', '551': 'stay'};

  /// "내 또래" 줄에서 넘어와 그 동네·업종으로 맞춤(2026-11-01). 이름 검색은 지우고 화면을 가게 목록 위치로 올림.
  void focus({required String emd, required String dong, required String ksic, required String catName}) {
    final chip = _ksicToChip[ksic];
    setState(() {
      _cat = chip ?? ksic;
      _extraCat = chip == null ? (key: ksic, name: catName) : null;
      _emd = emd;
      _extraDong = _dongs.any((d) => d['code'] == emd) ? null : (code: emd, name: dong);
      _q = '';
      _qCtl.clear();
    });
    _load(reset: true);
    final ctx = context;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ctx.mounted) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 350), curve: Curves.easeOut);
    });
  }

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    widget.stats?.then((d) {
      if (!mounted || d['live'] != true) return;
      final list = ((d['dongs'] as List?) ?? const []).cast<Map<String, dynamic>>().where((x) => (x['code'] as String?)?.length == 8).toList();
      if (list.isNotEmpty) setState(() => _dongs = list);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qCtl.dispose();
    super.dispose();
  }

  Future<void> _load({required bool reset}) async {
    final token = ++_token;
    final page = reset ? 1 : _page + 1;
    setState(() {
      _loading = true;
      _failed = false;
      if (reset) _items = [];
    });
    try {
      final d = await widget.api.localCurrencyStores(sido: widget.region.code, sgg: widget.region.sgg, q: _q, cat: _cat, emd: _emd ?? '', page: page);
      if (!mounted || token != _token) return;
      if (d['live'] != true) throw Exception('no data');
      final got = (d['items'] as List).cast<Map<String, dynamic>>();
      setState(() {
        if (reset) {
          _items = got;
        } else {
          final seen = {for (final x in _items) '${x['name']}|${x['addr']}'};
          _items = [..._items, ...got.where((x) => !seen.contains('${x['name']}|${x['addr']}'))];
        }
        _page = page;
        _show = reset ? 6 : _items.length;
        _total = d['total'] as int;
        _more = d['has_more'] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || token != _token) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () {
      final q = v.trim();
      if (q == _q) return;
      _q = q;
      _load(reset: true);
    });
  }

  static const _info = [
    '한국조폐공사 "지역사랑상품권 가맹점 기본정보"(모바일·카드)에서 계속사업자로 표시된 가게만 모았어요. 지류(종이) 상품권 가맹점은 이 자료에 없어요.',
    '가게마다 정보 기준일이 달라서(2025~2026년), 그 뒤에 문을 닫거나 상품권을 안 받게 된 곳이 섞여 있을 수 있어요. 가기 전에 전화로 확인해 주세요.',
    '지역마다 상품권 종류와 사용처가 달라서, 내가 가진 상품권이 모바일인지 카드인지에 맞는 가게를 보세요.',
  ];

  @override
  Widget build(BuildContext context) {
    return ListSection(
      title: '상품권 쓸 수 있는 가게',
      trailing: _loading && _items.isEmpty ? null : (_total > 0 ? '약 ${formatNumber(_total)}곳' : null),
      info: const InfoIconButton(title: '가맹점 안내', lines: _info),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_extraCat != null) PillChip(label: _extraCat!.name, selected: _cat == _extraCat!.key, onTap: () {}),
              for (final c in _cats)
                PillChip(
                  label: c.$2,
                  selected: c.$1 == _cat,
                  onTap: () {
                    if (c.$1 == _cat) return;
                    _cat = c.$1;
                    _extraCat = null;
                    _load(reset: true);
                  },
                ),
            ],
          ),
        ),
        if (_dongs.isNotEmpty || _extraDong != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                PillChip(
                  label: '동네 전체',
                  selected: _emd == null,
                  onTap: () {
                    if (_emd == null) return;
                    _emd = null;
                    _extraDong = null;
                    _load(reset: true);
                  },
                ),
                if (_extraDong != null) PillChip(label: _extraDong!.name, selected: _emd == _extraDong!.code, onTap: () {}),
                for (final d in _dongs)
                  PillChip(
                    label: d['name'] as String,
                    selected: _emd == d['code'],
                    onTap: () {
                      _emd = _emd == d['code'] ? null : d['code'] as String;
                      _extraDong = null;
                      _load(reset: true);
                    },
                  ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: TextField(
            controller: _qCtl,
            onChanged: _onQuery,
            onSubmitted: (v) {
              _debounce?.cancel();
              final q = v.trim();
              if (q == _q) return;
              _q = q;
              _load(reset: true);
            },
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 16),
            decoration: InputDecoration(
              hintText: '가게 이름으로 찾기 (예: 김밥, 미용실)',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
            ),
          ),
        ),
        if (_items.isEmpty && _loading)
          const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: LoadingNote(label: '가게를 찾는 중이에요')))
        else if (_items.isEmpty && _failed)
          EmptyNote('가게 목록을 불러오지 못했어요. 눌러서 다시 시도', onTap: () => _load(reset: true))
        else if (_items.isEmpty)
          const EmptyNote('조건에 맞는 가게가 없어요.\n업종이나 동네를 바꿔 보세요', vertical: 32)
        else ...[
          for (final s in _items.take(_show))
            ListLine(
              name: s['name'] as String,
              sub: [
                if ((s['dong'] as String).isNotEmpty) s['dong'],
                if ((s['cat'] as String).isNotEmpty) s['cat'],
                '${s['kind']} 상품권',
              ].join(' · '),
              onTap: () => _showStore(context, s),
            ),
          if (_loading)
            const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Center(child: LoadingNote(label: null)))
          else if (_failed)
            EmptyNote('더 불러오지 못했어요. 눌러서 다시 시도', onTap: () => _load(reset: false), vertical: 16)
          else if (_items.length > _show)
            ShowMoreButton(count: _items.length - _show, unit: '곳', onTap: () => setState(() => _show = _items.length))
          else if (_more)
            ShowMoreButton(count: 24, unit: '곳', onTap: () => _load(reset: false)),
        ],
      ],
    );
  }

  void _showStore(BuildContext context, Map<String, dynamic> s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      builder: (_) => _StoreSheet(store: s, region: widget.region),
    );
  }
}

class _StoreSheet extends StatelessWidget {
  const _StoreSheet({required this.store, required this.region});

  final Map<String, dynamic> store;
  final Region region;

  String _asof(String ymd) => ymd.length == 8 ? '${ymd.substring(0, 4)}년 ${int.parse(ymd.substring(4, 6))}월' : '';

  @override
  Widget build(BuildContext context) {
    final name = store['name'] as String;
    final addr = store['addr'] as String;
    final phone = store['phone'] as String?;
    final asof = _asof(store['asof'] as String);
    return SheetFrame(
      title: name,
      sub: [if ((store['cat'] as String).isNotEmpty) store['cat'], '${store['kind']} 상품권'].join(' · '),
      gapAfterHeader: 20,
      infoLines: const [
        '한국조폐공사 지역사랑상품권 가맹점 기본정보예요. 계속사업자로 표시된 가게지만 정보 기준일 뒤에 바뀌었을 수 있어요.',
        '카드 가맹점은 도로명 주소의 건물 번호가 빠져 있기도 해요. 지도에서 위치를 확인해 주세요.',
      ],
      children: [
        Text('주소', style: AppTheme.subheading),
        const SizedBox(height: 6),
        SelectableText(addr.isEmpty ? (region.label) : addr, style: const TextStyle(fontSize: 16, height: 1.5)),
        if (phone != null) ...[
          const SizedBox(height: 18),
          Text('전화', style: AppTheme.subheading),
          const SizedBox(height: 6),
          SelectableText(phone, style: const TextStyle(fontSize: 16, height: 1.5)),
        ],
        const SizedBox(height: 18),
        ActionButton(
          vertical: 12,
          label: '지도에서 보기',
          onTap: () => openMapChooser(context, {'name': name, 'q': addr.isNotEmpty ? '$name $addr' : '$name ${region.label}', 'lat': store['lat'], 'lng': store['lng']}),
        ),
        if (phone != null) ...[
          const SizedBox(height: 10),
          ActionButton(vertical: 12, label: '전화 걸기', onTap: () => launchUrl(Uri.parse('tel:${phone.replaceAll('-', '')}'))),
        ],
        const SizedBox(height: 18),
        Text(
          '${asof.isEmpty ? '' : '정보 기준 $asof · '}가기 전에 전화로 상품권을 받는지 확인해 주세요.',
          style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5),
        ),
      ],
    );
  }
}
