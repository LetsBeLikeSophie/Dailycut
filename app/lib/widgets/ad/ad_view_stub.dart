import 'package:flutter/widgets.dart';

/// 모바일 앱이 아닌 곳(웹·테스트·데스크톱)에서는 광고를 그리지 않음.
Widget? buildAdBlock(String unit, int width, int height) => null;

Future<void> initAds() async {}
