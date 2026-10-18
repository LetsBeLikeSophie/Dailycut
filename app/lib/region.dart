import 'package:flutter/material.dart';

import 'analytics.dart';

import 'api_client.dart';
import 'local_prefs.dart';
import 'location_flow.dart';
import 'location.dart';
import 'theme.dart';
import 'widgets/components.dart';
import 'widget_bridge.dart';

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

/// 현재 지역과 정한 방법(saved: 고르거나 내 위치로 찾아 저장한 지역, default: 아직 안 정해서 기본 서울).
/// 고른·찾은 지역은 기기에 저장해서 다음 실행에도 유지하고, **위치는 다시 읽지 않음**(2026-10-17: 예전엔 저장이 없으면 켤 때마다 읽었음).
/// 첫 실행의 위치 안내·권한 요청은 location_flow.dart가 첫 화면이 뜬 뒤에 설명부터 보여 주고 시작함.
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
    // 저장된 지역은 main에서 미리 읽어 둔 값으로 바로(동기) — 스피너 한 프레임 없이 첫 화면이 곧바로 그 지역으로 시작
    final saved = LocalPrefs.stringSync(_prefSido);
    if (saved != null) {
      current = _sidoByCode(saved).withSgg(LocalPrefs.stringSync(_prefSgg));
      source = 'saved';
    }
    // 기본 지역(서울)으로 바로 첫 화면을 보여줌(위치 확인을 기다리지 않음).
    ready = true;
    notifyListeners();
  }

  /// 내 위치로 지역을 찾아 **저장**함(권한은 이미 허용된 상태에서만). 좌표는 이 한 번에만 서버로 보내고(뭉갠 값) 저장하지 않음. 성공하면 true.
  Future<bool> locate() async {
    final api = _api;
    if (api == null) return false;
    final loc = await LocationService.read();
    if (loc == null) return false;
    try {
      final r = await api.resolveRegion(lat: loc.lat, lon: loc.lon);
      await choose(_sidoByCode(r['code'] as String?).withSgg(r['sgg'] as String?));
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> choose(Region r) async {
    Analytics.instance.track('region_pick', r.code); // 시도 코드만(시군구·좌표는 보내지 않음)
    current = r;
    source = 'saved';
    notifyListeners();
    await LocalPrefs.setString(_prefSido, r.code);
    if (r.sgg == null) {
      await LocalPrefs.remove(_prefSgg);
    } else {
      await LocalPrefs.setString(_prefSgg, r.sgg!);
    }
    WidgetBridge.refresh(); // 홈 화면 위젯도 새 지역으로(저장이 끝난 뒤에 불러야 위젯이 새 값을 읽음)
  }

  /// 화면 맨 위 줄에 붙일 지역 문구(예: "서울 중구"). 다른 탭엔 없는 "· 기본" 꼬리는 뺌(2026-10-17).
  String get label => current.label;

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
                  ? '지금은 서울 기준이에요. 지역을 골라 주세요.'
                  : '날씨·미세먼지·전통시장·문화가 고른 지역 기준으로 바뀌어요.',
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 12),
            // 위치는 켤 때마다 읽지 않으니, 이사·여행 때는 여기서 다시 찾음
            ActionButton(
              label: '현재 위치로 찾기',
              icon: Icons.my_location,
              vertical: 11,
              onTap: () async {
                final nav = Navigator.of(context);
                final ok = await useMyLocation(context, fromPicker: true);
                if (ok) nav.pop();
              },
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

