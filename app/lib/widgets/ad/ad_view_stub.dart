import 'package:flutter/widgets.dart';

/// 웹이 아닌 곳(안드로이드·iOS·테스트)에서는 애드핏 웹 광고를 못 쓰므로 아무것도 그리지 않음.
/// (앱 출시 때는 애드몹 같은 앱용 광고로 이 자리를 대체)
Widget buildAdView(String unit, int width, int height) => const SizedBox.shrink();
