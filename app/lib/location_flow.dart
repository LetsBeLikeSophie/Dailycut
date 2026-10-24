import 'package:flutter/material.dart';

import 'analytics.dart';
import 'local_prefs.dart';
import 'location.dart';
import 'region.dart';
import 'theme.dart';
import 'widgets/components.dart';

/// 위치 안내 흐름(2026-10-17). 예전엔 앱을 켜자마자 시스템 권한 창이 불쑥 떴고(저장된 지역이 없으면 켤 때마다 위치도 다시 읽었음) →
///  1) 첫 화면이 뜬 뒤 **먼저 설명**("내 지역으로 시작할까요?")을 보여 주고, 눌렀을 때만 권한 창을 띄움
///  2) 찾은 지역은 기기에 저장해서 **다음 실행부턴 위치를 읽지 않음**(바꾸고 싶으면 지역 줄을 눌러 "현재 위치로 찾기")
///  3) 거부·꺼짐이면 잠깐 뜨는 안내 시트로 "지역을 직접 고르세요"(배달앱의 주소 확인처럼)
const _askedKey = 'loc_asked';

/// 첫 화면이 뜬 직후 한 번 부름. 지역이 이미 정해졌거나(저장됨) 전에 한 번 물어봤으면 아무것도 안 함.
Future<void> offerLocationOnFirstRun(BuildContext context) async {
  final store = RegionStore.instance;
  if (store.source != 'default') return;
  // 이미 허용돼 있는 기기(재설치 등)는 묻지 않고 조용히 한 번 맞춤
  if (await LocationService.access() == LocationAccess.granted) {
    await store.locate();
    return;
  }
  if (LocalPrefs.stringSync(_askedKey) == '1') return; // 한 번 물어봤음(거부 포함) — 다시 띄우지 않음. 지역 줄을 누르면 언제든 고를 수 있음
  await LocalPrefs.setString(_askedKey, '1');
  if (!context.mounted) return;
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('내 지역으로 시작할까요?', style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            const Text(
              '날씨·행사·장소를 내 동네 기준으로 보여드리려고 대략적인 위치를 한 번만 확인해요. 정확한 위치는 저장하지 않고, 기기에는 지역 이름만 기억해요.',
              style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6),
            ),
            const SizedBox(height: 20),
            ActionButton(label: '내 위치로 시작', icon: Icons.my_location, filled: true, onTap: () => Navigator.of(ctx).pop('use')),
            GestureDetector(
              onTap: () => Navigator.of(ctx).pop('manual'),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: Text('직접 고를게요', style: TextStyle(fontSize: 13, color: AppColors.inkSoft, decoration: TextDecoration.underline))),
              ),
            ),
            // 2026-10-24: 익명 통계를 처음부터 투명하게 알림(팝업을 더 늘리지 않고 이 시트 맨 아래 한 줄로). 끄는 곳은 맨 위 ⓘ의 출처 시트.
            const Center(
              child: Text('화면 사용 횟수만 익명으로 집계해요. 맨 위 ⓘ에서 끌 수 있어요.', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5)),
            ),
          ],
        ),
      ),
    ),
  );
  if (!context.mounted) return;
  if (choice == 'use') {
    Analytics.instance.track('location_ask', 'intro_use');
    await useMyLocation(context);
  } else if (choice == 'manual') {
    Analytics.instance.track('location_ask', 'intro_manual');
    await showRegionPicker(context);
  } else {
    Analytics.instance.track('location_ask', 'intro_skip');
  }
}

/// 내 위치로 지역을 맞춤(권한 요청 포함). 성공하면 true. 안 되면 이유에 맞는 안내 시트를 띄움.
Future<bool> useMyLocation(BuildContext context, {bool fromPicker = false}) async {
  var access = await LocationService.access();
  if (access == LocationAccess.askable) access = await LocationService.request();
  if (access == LocationAccess.granted) {
    if (await RegionStore.instance.locate()) {
      Analytics.instance.track('location_ask', 'granted');
      return true;
    }
    if (!context.mounted) return false;
    await _showHelp(context, access, failedToFind: true, fromPicker: fromPicker);
    return false;
  }
  Analytics.instance.track('location_ask', access.name); // askable(거부) · blocked · off
  if (!context.mounted) return false;
  await _showHelp(context, access, fromPicker: fromPicker);
  return false;
}

/// 거부·꺼짐·못 찾음일 때 잠깐 뜨는 안내: 지역을 직접 고르도록.
Future<void> _showHelp(BuildContext context, LocationAccess access, {bool failedToFind = false, bool fromPicker = false}) {
  final (title, body) = failedToFind
      ? ('내 위치를 찾지 못했어요', '잠시 뒤 다시 시도하거나 지역을 직접 골라 주세요.')
      : switch (access) {
          LocationAccess.blocked => ('위치 권한이 꺼져 있어요', '폰 설정에서 데일리컷의 위치 권한을 켜면 내 위치로 맞출 수 있어요. 지금은 지역을 직접 골라 주세요.'),
          LocationAccess.off => ('폰의 위치 서비스가 꺼져 있어요', '위치 서비스를 켜거나 지역을 직접 골라 주세요.'),
          _ => ('위치를 허용하지 않으셨어요', '지금은 서울 기준으로 보여드리고 있어요. 지역을 직접 골라 주세요.'),
        };
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(body, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6)),
            const SizedBox(height: 20),
            if (!fromPicker)
              ActionButton(
                label: '지역 직접 고르기',
                filled: true,
                onTap: () {
                  Navigator.of(ctx).pop();
                  showRegionPicker(context);
                },
              ),
            if (access == LocationAccess.blocked) ...[
              SizedBox(height: fromPicker ? 0 : 8),
              ActionButton(label: '폰 설정 열기', onTap: LocationService.openSettings),
            ],
            GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Center(child: Text('닫기', style: TextStyle(fontSize: 13, color: AppColors.inkSoft))),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
