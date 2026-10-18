import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 홈 화면 위젯(안드로이드 네이티브, `android/.../WeatherWidget.kt`)과의 다리. 위젯은 앱이 저장한 지역을 직접 읽어 날씨를 받으므로
/// 앱이 하는 일은 "지역을 바꿨으니 다시 그려라"는 신호뿐(2026-10-18). 웹·iOS·위젯이 없을 때는 아무 일도 안 함.
class WidgetBridge {
  static const _channel = MethodChannel('dailycut/widget');

  static Future<void> refresh() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {}
  }
}
