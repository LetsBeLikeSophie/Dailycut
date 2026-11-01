/// 웹이 아닌 곳에는 HTML 스플래시가 없음.
void hideSplash() {}

/// 웹이 아니면 미리 받아 둔 날씨가 없음.
Future<Map<String, dynamic>?> takeEarlyWeather(String key) async => null;

/// 웹이 아니면 사파리 주소창이 화면을 덮지 않음.
double iosBrowserBarPad() => 0;
