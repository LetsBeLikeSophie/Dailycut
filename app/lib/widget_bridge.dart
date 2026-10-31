import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 홈 화면 위젯(안드로이드 네이티브, `android/.../WeatherWidget.kt`)과의 다리(2026-10-18). 위젯은 앱이 저장한 지역·내 장바구니를 직접 읽어 서버에서
/// 받으므로 앱이 하는 일은 둘: ①지역·장바구니를 바꿨으니 다시 그려라(refresh) ②위젯을 눌러 들어왔으니 그 탭을 열어라(initialTab/openTab).
/// 웹·iOS·위젯이 없을 때는 아무 일도 안 함.
class WidgetBridge {
  static const _channel = MethodChannel('dailycut/widget');
  /// 안드로이드 앱에서만 true(웹·iOS엔 위젯도 아침 알림도 없음)
  static bool get supported => _supported;
  static bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> refresh() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('refresh');
    } catch (_) {}
  }

  /// 아침 날씨 알림(2026-10-31): `brief_time`을 저장한 뒤 불러서 안드로이드 쪽 일정을 다시 걺(없으면 꺼짐).
  static Future<void> briefApply() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<void>('briefApply');
    } catch (_) {}
  }

  /// 알림 허용 요청(안드로이드 13+는 시스템 창). 허용돼 있으면 true.
  static Future<bool> notifRequest() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('notifRequest') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> notifGranted() async {
    if (!_supported) return false;
    try {
      return await _channel.invokeMethod<bool>('notifGranted') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 위젯을 눌러 앱이 켜졌을 때의 탭 키('life'·'money' 등). 없으면 null. 한 번 꺼내면 비워짐.
  static Future<String?> initialTab() async {
    if (!_supported) return null;
    try {
      return await _channel.invokeMethod<String>('initialTab');
    } catch (_) {
      return null;
    }
  }

  /// 앱이 이미 떠 있을 때 위젯을 눌러 탭을 바꾸라는 신호를 받음.
  static void listen(void Function(String tab) onTab) {
    if (!_supported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openTab' && call.arguments is String) onTab(call.arguments as String);
    });
  }
}
