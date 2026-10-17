import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../theme.dart';
import 'ad/ad_view_stub.dart' if (dart.library.js_interop) 'ad/ad_view_web.dart' if (dart.library.io) 'ad/ad_view_mobile.dart';

/// 광고 설정(빌드할 때 --dart-define으로 줌). 비어 있으면 광고 칸은 아예 그려지지 않음(자리도 안 차지함).
///  웹(카카오 애드핏): --dart-define=ADFIT_UNIT=DAN-xxxxxxxx  --dart-define=ADFIT_SIZE=320x100
///  앱(구글 애드몹):   --dart-define=ADMOB_BANNER_ID=ca-app-pub-xxxxxxxxxxxxxxxx/yyyyyyyyyy  (배너 광고 단위 ID, 320x100)
///     개발 중엔 구글 공식 테스트 배너 ID ca-app-pub-3940256099942544/6300978111 을 넣으면 "Test Ad"가 뜸(실제 ID로 테스트하면 계정이 정지될 수 있음 — 내 광고를 직접 누르지 말 것).
const kAdfitUnit = String.fromEnvironment('ADFIT_UNIT');
const kAdfitSize = String.fromEnvironment('ADFIT_SIZE', defaultValue: '320x100');
const kAdmobBanner = String.fromEnvironment('ADMOB_BANNER_ID');
bool get kAdsEnabled => kIsWeb ? kAdfitUnit.isNotEmpty : kAdmobBanner.isNotEmpty;

/// 앱 시작 때 한 번(앱이면 애드몹 초기화, 웹이면 아무 일 없음). 기다리지 않고 불러도 됨.
Future<void> initAdsIfEnabled() => kIsWeb || !kAdsEnabled ? Future.value() : initAds();

/// 목록 사이에 놓는 배너 한 칸. 위에 "광고" 라벨을 붙여서 콘텐츠와 구분함. 광고 ID가 없거나 웹이 아니면 아무것도 안 그림.
class AdSlot extends StatelessWidget {
  const AdSlot({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kAdsEnabled) return const SizedBox.shrink();
    if (!kIsWeb) return buildAdBlock(kAdmobBanner, 320, 100) ?? const SizedBox.shrink(); // 앱: 애드몹(광고가 와야 칸이 보임)
    final parts = kAdfitSize.split('x');
    final w = double.tryParse(parts.first) ?? 320;
    final h = double.tryParse(parts.length > 1 ? parts[1] : '100') ?? 100;
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('광고', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
          const SizedBox(height: 6),
          Center(child: SizedBox(width: w, height: h, child: buildAdView(kAdfitUnit, w.toInt(), h.toInt()))),
        ],
      ),
    );
  }
}
