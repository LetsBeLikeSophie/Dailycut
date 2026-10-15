import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../local_prefs.dart';
import '../theme.dart';

/// 장소를 지도 앱으로 보냄(2026-10-16). 지도 앱이 여러 개라 사용자가 고르게 하고, 마지막으로 고른 앱을 맨 위에 둠(기기에만 저장).
/// pin = 서버가 준 {name, q, lat?, lng?}: 좌표가 있으면 그 자리 핀, 없으면 검색어(q). 지금은 웹 링크로 열고,
/// 앱(안드로이드·iOS)으로 낼 땐 각 지도 앱의 딥링크(kakaomap://, nmap://)로 바꾸면 됨.
enum MapApp { kakao, naver, google }

const _appLabels = {MapApp.kakao: '카카오맵', MapApp.naver: '네이버지도', MapApp.google: '구글지도'};
const _prefKey = 'map_app';

Uri mapUri(MapApp app, Map<String, dynamic> pin) {
  final name = (pin['name'] as String? ?? '').replaceAll(',', ' ');
  final q = (pin['q'] as String?) ?? name;
  final lat = (pin['lat'] as num?)?.toDouble();
  final lng = (pin['lng'] as num?)?.toDouble();
  final has = lat != null && lng != null;
  switch (app) {
    case MapApp.kakao:
      return Uri.parse(has ? 'https://map.kakao.com/link/map/${Uri.encodeComponent(name)},$lat,$lng' : 'https://map.kakao.com/link/search/${Uri.encodeComponent(q)}');
    case MapApp.naver:
      return Uri.parse(has ? 'https://map.naver.com/p/search/${Uri.encodeComponent(name)}?c=$lng,$lat,15,0,0,0,dh' : 'https://map.naver.com/p/search/${Uri.encodeComponent(q)}');
    case MapApp.google:
      return Uri.parse('https://www.google.com/maps/search/?api=1&query=${has ? '$lat%2C$lng' : Uri.encodeComponent(q)}');
  }
}

Future<void> openMapChooser(BuildContext context, Map<String, dynamic> pin) async {
  final last = await LocalPrefs.getString(_prefKey);
  if (!context.mounted) return;
  final apps = [...MapApp.values]..sort((a, b) => (a.name == last ? 0 : 1).compareTo(b.name == last ? 0 : 1));
  await showModalBottomSheet<void>(
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
            Text('지도에서 보기', style: AppTheme.subheading),
            const SizedBox(height: 4),
            Text(pin['name'] as String? ?? '', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.ink),
            for (final a in apps)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Analytics.instance.track('life_open', 'map-${a.name}');
                  LocalPrefs.setString(_prefKey, a.name);
                  launchUrl(mapUri(a, pin), mode: LaunchMode.externalApplication);
                  Navigator.of(ctx).pop();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hair))),
                  child: Row(
                    children: [
                      Expanded(child: Text(_appLabels[a]!, style: const TextStyle(fontSize: 16))),
                      if (a.name == last) const Text('최근에 쓴 지도', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
