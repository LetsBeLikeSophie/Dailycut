import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../theme.dart';

/// 안드로이드·iOS 앱: 구글 애드몹 배너(2026-10-18). 웹의 카카오 애드핏과 달리 앱은 애드몹을 씀.
/// 앱 시작 때 한 번 초기화하고, 광고가 실제로 불러와졌을 때만 칸(라벨 "광고" 포함)을 보임 — 못 받으면 빈 칸이 남지 않음.
Future<void> initAds() async {
  try {
    await MobileAds.instance.initialize();
  } catch (_) {}
}

Widget buildAdView(String unit, int width, int height) => const SizedBox.shrink();

Widget? buildAdBlock(String unit, int width, int height) => _AdmobBanner(unit: unit, width: width, height: height);

class _AdmobBanner extends StatefulWidget {
  const _AdmobBanner({required this.unit, required this.width, required this.height});

  final String unit;
  final int width;
  final int height;

  @override
  State<_AdmobBanner> createState() => _AdmobBannerState();
}

class _AdmobBannerState extends State<_AdmobBanner> {
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

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('광고', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
          const SizedBox(height: 6),
          Center(child: SizedBox(width: ad.size.width.toDouble(), height: ad.size.height.toDouble(), child: AdWidget(ad: ad))),
        ],
      ),
    );
  }
}
