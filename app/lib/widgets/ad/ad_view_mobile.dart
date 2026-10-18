import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../theme.dart';

/// 안드로이드·iOS 앱: 구글 애드몹 배너(2026-10-18).
/// 앱 시작 때 한 번 초기화하고, 광고가 실제로 불러와졌을 때만 칸(라벨 "광고" 포함)을 보임 — 못 받으면 빈 칸이 남지 않음.
Future<void> initAds() async {
  try {
    await MobileAds.instance.initialize();
  } catch (_) {}
}

Widget? buildAdBlock(String unit, int width, int height) => _AdmobBanner(unit: unit, width: width, height: height);

class _AdmobBanner extends StatefulWidget {
  const _AdmobBanner({required this.unit, required this.width, required this.height});

  final String unit;
  final int width;
  final int height;

  @override
  State<_AdmobBanner> createState() => _AdmobBannerState();
}

class _AdmobBannerState extends State<_AdmobBanner> with AutomaticKeepAliveClientMixin {
  BannerAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = BannerAd(
      adUnitId: widget.unit,
      size: widget.width == 320 && widget.height == 100 ? AdSize.largeBanner : AdSize(width: widget.width, height: widget.height),
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, _) {
          ad.dispose();
          _ad = null;
        },
      ),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  /// 목록을 위아래로 밀어도 광고를 지우지 않음(2026-10-18: 안 그러면 스크롤할 때마다 광고를 새로 요청함 — 애드몹은 잦은 새로고침을 싫어함)
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    // 다른 탭이 앞에 있을 땐(IndexedStack이 TickerMode를 꺼 줌) 네이티브 광고 뷰를 그리지 않고 같은 크기의 빈 칸만 둠 —
    // 광고는 플러터 화면 위에 따로 얹히는 네이티브 뷰라 탭을 바꿀 때 비쳐 보일 수 있었음(폰 테스트 피드백).
    final active = TickerMode.valuesOf(context).enabled;
    return Padding(
      padding: const EdgeInsets.only(top: 32, bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('광고', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
          const SizedBox(height: 6),
          Center(child: SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: active ? AdWidget(ad: ad) : null)),
        ],
      ),
    );
  }
}
