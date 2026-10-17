import 'package:flutter/widgets.dart';

/// 웹도 모바일도 아닌 곳(테스트·데스크톱)에서는 광고를 그리지 않음.
Widget buildAdView(String unit, int width, int height) => const SizedBox.shrink();

/// 모바일 앱이 아니면 광고 한 덩어리를 직접 만들지 않음(null → ad_slot.dart가 기본 칸을 씀).
Widget? buildAdBlock(String unit, int width, int height) => null;

Future<void> initAds() async {}
