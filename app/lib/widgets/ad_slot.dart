import 'package:flutter/material.dart';

import '../theme.dart';
import 'ad/ad_view_stub.dart' if (dart.library.js_interop) 'ad/ad_view_web.dart';

/// 광고 설정(빌드할 때 --dart-define으로 줌). 비어 있으면 광고 칸은 아예 그려지지 않음(자리도 안 차지함).
///   --dart-define=ADFIT_UNIT=DAN-xxxxxxxx   카카오 애드핏 광고 단위 ID
///   --dart-define=ADFIT_SIZE=320x100        (기본 320x100, 320x50·300x250 등 애드핏이 만든 단위 크기와 같아야 함)
const kAdfitUnit = String.fromEnvironment('ADFIT_UNIT');
const kAdfitSize = String.fromEnvironment('ADFIT_SIZE', defaultValue: '320x100');
bool get kAdsEnabled => kAdfitUnit.isNotEmpty;

/// 목록 사이에 놓는 배너 한 칸. 위에 "광고" 라벨을 붙여서 콘텐츠와 구분함. 광고 ID가 없거나 웹이 아니면 아무것도 안 그림.
class AdSlot extends StatelessWidget {
  const AdSlot({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kAdsEnabled) return const SizedBox.shrink();
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
