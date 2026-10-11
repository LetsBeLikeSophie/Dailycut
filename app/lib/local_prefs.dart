import 'package:shared_preferences/shared_preferences.dart';

/// 기기 안에만 저장하는 개인 설정(로그인 없음). 마지막으로 고른 칩, 숨긴 생활지수 같은 것.
/// 저장소가 막혀 있어도(시크릿 창 등) 예외 없이 기본값으로 동작.
class LocalPrefs {
  static Future<String?> getString(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getString(key);
    } catch (_) {
      return null;
    }
  }

  static Future<void> setString(String key, String value) async {
    try {
      await (await SharedPreferences.getInstance()).setString(key, value);
    } catch (_) {}
  }

  static Future<List<String>> getList(String key) async {
    try {
      return (await SharedPreferences.getInstance()).getStringList(key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> setList(String key, List<String> value) async {
    try {
      await (await SharedPreferences.getInstance()).setStringList(key, value);
    } catch (_) {}
  }
}
