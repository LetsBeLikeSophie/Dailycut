import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'location.dart';
import 'theme.dart';

/// 앱 전체의 지역 단위는 "시도 17곳"으로 통일함(날씨·문화·전통시장 등이 모두 이 코드로 조회).
/// 코드는 행정표준코드 앞 2자리이고 backend/geo.py의 REGIONS와 같아야 함.
class Region {
  const Region(this.code, this.name);

  final String code;
  final String name;
}

const kRegions = <Region>[
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

/// 현재 지역과 그걸 어떻게 정했는지(gps: 내 위치, saved: 사용자가 고른 지역, default: 기본 서울).
/// 고른 지역은 기기에 저장해서 다음 실행에도 유지하고, 저장된 값이 없을 때만 위치 권한을 요청함.
class RegionStore extends ChangeNotifier {
  RegionStore._();
  static final RegionStore instance = RegionStore._();

  static const _prefKey = 'region_code';

  Region current = kRegions.first;
  String source = 'default';
  bool ready = false;

  Region _byCode(String? code) => kRegions.firstWhere((r) => r.code == code, orElse: () => kRegions.first);

  Future<void> init(ApiClient api) async {
    if (ready) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        current = _byCode(saved);
        source = 'saved';
      } else {
        final loc = await LocationService.get();
        if (loc.real) {
          // 좌표는 시도를 알아내는 이 한 번에만 서버로 보내고, 이후엔 시도 코드만 씀
          final r = await api.resolveRegion(lat: loc.lat, lon: loc.lon);
          current = _byCode(r['code'] as String?);
          source = 'gps';
        }
      }
    } catch (_) {
      // 위치/저장소 오류면 기본(서울)으로
    }
    ready = true;
    notifyListeners();
  }

  Future<void> choose(Region r) async {
    current = r;
    source = 'saved';
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKey, r.code);
    } catch (_) {}
  }

  /// 화면 맨 위 줄에 붙일 지역 문구(예: "서울", 위치를 못 받아 기본값이면 "서울 · 기본").
  String get label => source == 'default' ? '${current.name} · 기본' : current.name;
}

/// 시도 17곳 중에서 고르는 아래 시트.
Future<void> showRegionPicker(BuildContext context) {
  final store = RegionStore.instance;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('지역 선택', style: AppTheme.subheading),
            const SizedBox(height: 4),
            Text(
              store.source == 'default'
                  ? '위치를 받지 못해 서울로 보여드리고 있어요. 지역을 골라주세요.'
                  : '날씨·문화·전통시장 정보가 선택한 시도 기준으로 바뀌어요.',
              style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in kRegions)
                  _RegionChip(
                    region: r,
                    selected: r.code == store.current.code,
                    onTap: () {
                      store.choose(r);
                      Navigator.of(ctx).pop();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _RegionChip extends StatelessWidget {
  const _RegionChip({required this.region, required this.selected, required this.onTap});

  final Region region;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          region.name,
          style: TextStyle(
            fontSize: 16,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
