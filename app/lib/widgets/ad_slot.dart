import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'ad/ad_view_stub.dart' if (dart.library.io) 'ad/ad_view_mobile.dart';

/// 광고는 **안드로이드·iOS 앱에서만, 구글 애드몹**으로 나옴(2026-10-18). 웹은 광고 없음 — 카카오 애드핏은 심사에서 탈락해 코드를 걷어냈고,
/// 애드몹은 앱 전용이라 웹사이트엔 붙일 수 없음(웹 광고가 필요해지면 구글 애드센스를 따로 신청해야 함).
///
/// 광고 단위 ID는 빌드할 때 `--dart-define=ADMOB_BANNER_ID=ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy`(배너, 320x100)로 줌. 비어 있으면 광고 칸이 아예 안 그려짐.
/// 개발 중엔 구글 공식 테스트 배너 ID `ca-app-pub-3940256099942544/6300978111`을 넣으면 "Test Ad"가 뜸
/// (실제 ID로 테스트하면서 내 광고를 누르면 계정이 정지될 수 있음). 앱 ID는 android/gradle.properties의 ADMOB_APP_ID(없으면 구글 공식 테스트 앱 ID).
const kAdmobBanner = String.fromEnvironment('ADMOB_BANNER_ID');
bool get kAdsEnabled => !kIsWeb && kAdmobBanner.isNotEmpty;

/// 앱 시작 때 한 번 애드몹 초기화(웹이거나 광고 ID가 없으면 아무 일 없음). 기다리지 않고 불러도 됨.
Future<void> initAdsIfEnabled() => kAdsEnabled ? initAds() : Future.value();

/// 목록 아래에 놓는 배너 한 칸(위에 "광고" 라벨). 광고가 실제로 불러와졌을 때만 보이고, 웹이거나 ID가 없으면 아무것도 안 그림.
class AdSlot extends StatelessWidget {
  const AdSlot({super.key});

  @override
  Widget build(BuildContext context) => kAdsEnabled ? (buildAdBlock(kAdmobBanner, 320, 100) ?? const SizedBox.shrink()) : const SizedBox.shrink();
}
