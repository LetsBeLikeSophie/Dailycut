import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics.dart';

import 'api_client.dart';
import 'location.dart';
import 'theme.dart';
import 'widgets/components.dart';

/// 앱 전체의 지역 단위: 시도(17곳) + 선택적으로 시군구. 시군구를 안 고르면 "시도 전체"로 동작함.
/// 날씨·미세먼지·전통시장·문화가 모두 이 한 지역을 기준으로 조회됨(데이터마다 더 거친 단위만
/// 지원하면 화면에 "서울 기준"처럼 범위 꼬리표가 붙음).
/// 시도 코드는 행정표준코드 앞 2자리이고 backend/geo.py의 REGIONS와 같아야 함.
class Region {
  const Region(this.code, this.name, [this.sgg]);

  final String code; // 시도 코드
  final String name; // 시도 이름
  final String? sgg; // 시군구(없으면 시도 전체)

  /// 화면에 보이는 이름("서울 중구" / "서울").
  String get label => sgg == null ? name : '$name $sgg';

  Region withSgg(String? s) => Region(code, name, s);
}

const kSidos = <Region>[
  Region('11', '서울'),
  Region('26', '부산'),
  Region('27', '대구'),
  Region('28', '인천'),
  Region('29', '광주'),
  Region('30', '대전'),
  Region('31', '울산'),
  Region('36', '세종'),
  Region('41', '경기'),
  Region('51', '강원'),
  Region('43', '충북'),
  Region('44', '충남'),
  Region('52', '전북'),
  Region('46', '전남'),
  Region('47', '경북'),
  Region('48', '경남'),
  Region('50', '제주'),
];

/// 서버(/regions)가 주는 시도 안 시군구 하나(별칭: 성남시 ← 분당구).
class SigunguNode {
  const SigunguNode(this.name, this.aliases);

  final String name;
  final List<String> aliases;
}

/// 현재 지역과 정한 방법(gps: 내 위치, saved: 사용자가 고른 지역, default: 기본 서울).
/// 고른 지역은 기기에 저장해서 다음 실행에도 유지하고, 저장된 값이 없을 때만 위치 권한을 요청함.
class RegionStore extends ChangeNotifier {
  RegionStore._();
  static final RegionStore instance = RegionStore._();

  static const _prefSido = 'region_code';
  static const _prefSgg = 'region_sgg';

  ApiClient? _api;
  Region current = kSidos.first;
  String source = 'default';
  bool ready = false;
  Map<String, List<SigunguNode>>? _tree;

  Region _sidoByCode(String? code) => kSidos.firstWhere((r) => r.code == code, orElse: () => kSidos.first);

  Future<void> init(ApiClient api) async {
    _api = api;
    if (ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefSido);
      if (saved != null) {
        current = _sidoByCode(saved).withSgg(prefs.getString(_prefSgg));
        source = 'saved';
      }
    } catch (_) {
      // 저장소 오류면 기본(서울)으로
    }
    // 2026-10-12: 위치 권한 확인(허용 창 + 최대 8초)이 끝나길 기다렸다가 데이터를 받던 걸 바꿈 — 첫 방문자는 그동안
    // 빈 화면만 봤음. 이제 기본 지역(서울)으로 바로 보여주고, 위치는 뒤에서 알아내서 맞으면 그 지역으로 바꿈.
    ready = true;
    notifyListeners();
    if (source == 'default') _locate(api);
  }

  Future<void> _locate(ApiClient api) async {
    try {
      final loc = await LocationService.get();
      if (!loc.real || source != 'default') return; // 위치를 못 받았거나, 그 사이 사용자가 지역을 직접 골랐으면 그대로
      // 좌표는 지역을 알아내는 이 한 번에만 서버로 보내고, 이후엔 지역 이름만 씀
      final r = await api.resolveRegion(lat: loc.lat, lon: loc.lon);
      if (source != 'default') return;
      current = _sidoByCode(r['code'] as String?).withSgg(r['sgg'] as String?);
      source = 'gps';
      notifyListeners();
    } catch (_) {
      // 위치 오류면 기본(서울) 유지
    }
  }

  Future<void> choose(Region r) async {
    Analytics.instance.track('region_pick', r.code); // 시도 코드만(시군구·좌표는 보내지 않음)
    current = r;
    source = 'saved';
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefSido, r.code);
      if (r.sgg == null) {
        await prefs.remove(_prefSgg);
      } else {
        await prefs.setString(_prefSgg, r.sgg!);
      }
    } catch (_) {}
  }

  /// 화면 맨 위 줄에 붙일 지역 문구(예: "서울 중구", 위치를 못 받아 기본값이면 "서울 · 기본").
  String get label => source == 'default' ? '${current.label} · 기본' : current.label;

  /// 시도별 시군구 목록(서버에서 한 번 받아 보관).
  Future<Map<String, List<SigunguNode>>> loadTree() async {
    final cached = _tree;
    if (cached != null) return cached;
    final res = await _api!.regions();
    final out = <String, List<SigunguNode>>{};
    for (final s in (res['regions'] as List).cast<Map<String, dynamic>>()) {
      out[s['code'] as String] = [
        for (final g in (s['sigungu'] as List).cast<Map<String, dynamic>>())
          SigunguNode(g['name'] as String, (g['aliases'] as List).cast<String>()),
      ];
    }
    return _tree = out;
  }
}

/// 지역 선택 시트: 시도를 고르고 시군구(또는 "시도 전체")를 고르거나, 이름으로 검색.
Future<void> showRegionPicker(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
    builder: (ctx) => const _RegionSheet(),
  );
}

class _RegionSheet extends StatefulWidget {
  const _RegionSheet();

  @override
  State<_RegionSheet> createState() => _RegionSheetState();
}

class _RegionSheetState extends State<_RegionSheet> {
  final _store = RegionStore.instance;
  late String _sido = _store.current.code;
  String _query = '';
  late final Future<Map<String, List<SigunguNode>>> _tree = _store.loadTree();

  void _pick(Region r) {
    _store.choose(r);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 16 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('지역 선택', style: AppTheme.subheading),
            const SizedBox(height: 4),
            Text(
              _store.source == 'default'
                  ? '위치를 받지 못해 서울로 보여드리고 있어요. 지역을 골라주세요.'
                  : '날씨·미세먼지·전통시장·문화가 고른 지역 기준으로 바뀌어요.',
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 12),
            TextField(
              onChanged: (v) => setState(() => _query = v.trim()),
              style: const TextStyle(fontSize: 16),
              decoration: InputDecoration(
                hintText: '시군구 이름으로 찾기 (예: 분당, 해운대)',
                hintStyle: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.line)),
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: FutureBuilder<Map<String, List<SigunguNode>>>(
                future: _tree,
                builder: (context, snap) {
                  final tree = snap.data;
                  if (_query.isNotEmpty && tree != null) return _results(tree);
                  return SingleChildScrollView(child: _browse(tree));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 검색 결과: 모든 시도의 시군구 이름·별칭에서 찾음.
  Widget _results(Map<String, List<SigunguNode>> tree) {
    final hits = <(Region, String?)>[];
    for (final sido in kSidos) {
      for (final g in tree[sido.code] ?? const <SigunguNode>[]) {
        final alias = g.aliases.where((a) => a.contains(_query)).toList();
        if (g.name.contains(_query) || alias.isNotEmpty) {
          hits.add((sido.withSgg(g.name), alias.isEmpty ? null : alias.first));
        }
      }
    }
    if (hits.isEmpty) {
      return const EmptyNote('찾는 지역이 없어요. 시도를 직접 골라보세요.', vertical: 24);
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final (r, alias) in hits)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(r.label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            subtitle: alias == null ? null : Text('$alias 포함', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
            onTap: () => _pick(r),
          ),
      ],
    );
  }

  Widget _browse(Map<String, List<SigunguNode>>? tree) {
    final sidoRegion = kSidos.firstWhere((r) => r.code == _sido);
    final sigungu = tree?[_sido] ?? const <SigunguNode>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final r in kSidos)
              PillChip(large: true, label: r.name, selected: r.code == _sido, onTap: () => setState(() => _sido = r.code)),
          ],
        ),
        const SizedBox(height: 18),
        Text('${sidoRegion.name}에서 고르기', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (tree == null)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              PillChip(large: true, 
                label: '${sidoRegion.name} 전체',
                selected: _store.current.code == _sido && _store.current.sgg == null,
                emphasized: true,
                onTap: () => _pick(sidoRegion),
              ),
              for (final g in sigungu)
                PillChip(large: true, 
                  label: g.name,
                  selected: _store.current.code == _sido && _store.current.sgg == g.name,
                  onTap: () => _pick(sidoRegion.withSgg(g.name)),
                ),
            ],
          ),
      ],
    );
  }
}

