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
const _catChips = <(String, String)>[
  ('food', '음식점'),
  ('cafe', '카페·주점'),
  ('mart', '마트·편의점'),
  ('grocery', '식료품'),
  ('pharm', '약국·화장품'),
  ('beauty', '미용·세탁'),
  ('clinic', '병원·의원'),
  ('academy', '학원'),
  ('stay', '숙박'),
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
  final Set<String> _cats = {'food'}; // 여러 개 고를 수 있음. 비어 있으면 전체 업종
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
  final Map<String, String> _extraCats = {}; // 칩에 없는 업종(내 또래 줄에서 넘어온 3자리 코드 → 이름)
  bool _statsFailed = false;

  static const _ksicToChip = {'561': 'food', '562': 'cafe', '471': 'mart', '472': 'grocery', '477': 'pharm', '961': 'beauty', '862': 'clinic', '856': 'academy', '551': 'stay'};

  /// "내 또래" 줄에서 넘어와 그 동네·업종으로 맞춤(2026-11-01). 이름 검색은 지우고 화면을 가게 목록 위치로 올림.
  void focus({required String emd, required String dong, required String ksic, required String catName}) {
    final chip = _ksicToChip[ksic];
    setState(() {
      _cats
        ..clear()
        ..add(chip ?? ksic);
      _extraCats
        ..clear()
        ..addAll(chip == null ? {ksic: catName} : const {});
      _emd = emd;
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
      final list = ((d['dong_all'] as List?) ?? const []).cast<Map<String, dynamic>>();
      setState(() {
        _dongs = list;
        _statsFailed = list.isEmpty;
      });
    }).catchError((_) {
      if (mounted) setState(() => _statsFailed = true);
    });
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
      final d = await widget.api.localCurrencyStores(sido: widget.region.code, sgg: widget.region.sgg, q: _q, cat: (_cats.toList()..sort()).join(','), emd: _emd ?? '', page: page);
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

  void _toggleCat(String key) {
    setState(() {
      if (!_cats.remove(key)) _cats.add(key);
      _extraCats.removeWhere((k, _) => !_cats.contains(k)); // 해제한 임시 칩은 사라짐
    });
    _load(reset: true);
  }

  String get _dongLabel {
    if (_emd == null) return '전체';
    for (final d in _dongs) {
      if (d['code'] == _emd) return d['name'] as String;
    }
    return '전체';
  }

  /// 동네 고르기: 알약 대신 줄 하나(동네 · 전체 ▾)를 눌러 시트에서 고름(읍면동이 많아 칩으로 늘어놓으면 화면을 다 차지함).
  Widget _dongField() {
    final ready = _dongs.isNotEmpty;
    return GestureDetector(
      onTap: ready ? _pickDong : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(top: 14),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(
          children: [
            const Text('동네', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(ready ? _dongLabel : '불러오는 중이에요', style: TextStyle(fontSize: 16, fontWeight: ready ? FontWeight.w700 : FontWeight.w400, color: ready ? AppColors.ink : AppColors.inkSoft)),
            ),
            if (ready) const Icon(Icons.keyboard_arrow_down, size: 22, color: AppColors.ink),
          ],
        ),
      ),
    );
  }

  void _pickDong() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
      builder: (ctx) {
        void pick(String? code) {
          Navigator.of(ctx).pop();
          if (code == _emd) return;
          setState(() => _emd = code);
          _load(reset: true);
        }

        return SheetFrame(
          title: '동네 고르기',
          sub: '상품권 결제가 많은 동네부터 보여 줘요',
          gapAfterHeader: 12,
          children: [
            Container(height: 1, color: AppColors.ink),
            ListLine(name: '동네 전체', value: _emd == null ? '선택됨' : null, onTap: () => pick(null)),
            for (final d in _dongs) ListLine(name: d['name'] as String, value: _emd == d['code'] ? '선택됨' : null, onTap: () => pick(d['code'] as String)),
          ],
        );
      },
    );
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

  List<String> get _info {
    final range = dateRange([for (final s in _items) s['asof'] as String? ?? '']);
    return [
      '계속사업자로 표시된 모바일·카드 가맹점이에요.\n지류(종이) 상품권 가맹점은 이 자료에 없어요.',
      if (range.isNotEmpty) '정보 기준일은 ${range.contains('~') ? '$range로 가게마다 달라요' : '$range이에요'}.\n가게를 누르면 그 가게의 기준일이 나와요.',
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListSection(
      title: '상품권 쓸 수 있는 가게',
      trailing: _loading && _items.isEmpty ? null : (_total > 0 ? '약 ${formatNumber(_total)}곳' : null),
      info: InfoIconButton(title: '가맹점 안내', lines: _info, sources: const [('한국조폐공사', 'https://www.komsco.com')]),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final e in _extraCats.entries) PillChip(label: e.value, selected: _cats.contains(e.key), onTap: () => _toggleCat(e.key)),
              for (final c in _catChips) PillChip(label: c.$2, selected: _cats.contains(c.$1), onTap: () => _toggleCat(c.$1)),
            ],
          ),
        ),
        if (_cats.isEmpty)
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('업종을 고르지 않아서 모든 업종을 보여 드려요', style: TextStyle(fontSize: 11, color: AppColors.inkSoft))),
        if (!_statsFailed) _dongField(),
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

  @override
  Widget build(BuildContext context) {
    final name = store['name'] as String;
    final addr = store['addr'] as String;
    final phone = store['phone'] as String?;
    final ymd = store['asof'] as String? ?? '';
    return SheetFrame(
      title: name,
      sub: [if ((store['cat'] as String).isNotEmpty) store['cat'], '${store['kind']} 상품권'].join(' · '),
      gapAfterHeader: 20,
      infoLines: [
        if (dotDate(ymd).isNotEmpty) '정보 기준일은 ${dotDate(ymd)}이에요.',
        '카드 가맹점은 도로명 주소의 건물 번호가\n빠져 있기도 해요. 지도에서 위치를 확인해 주세요.',
        '가기 전에 전화로 상품권을 받는지 확인해 주세요.',
      ],
      infoSources: const [('한국조폐공사', 'https://www.komsco.com')],
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
      ],
    );
  }
}
