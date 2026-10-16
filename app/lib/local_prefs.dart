import 'package:shared_preferences/shared_preferences.dart';

/// 기기 안에만 저장하는 개인 설정(로그인 없음). 마지막으로 고른 칩, 숨긴 생활지수, 내 장바구니 같은 것.
/// 저장소가 막혀 있어도(시크릿 창 등) 예외 없이 기본값으로 동작.
///
/// 2026-10-16: 화면마다 저장값을 비동기로 읽어서 "기본값으로 한 번 그리고 → 저장값으로 다시 그리는" 두 번 그리기(와 그 사이의
/// 불필요한 요청)가 있었음 → 앱이 뜨기 전(main)에 [init]으로 한 번 읽어 두고, 화면은 `*Sync`로 첫 프레임부터 저장값을 씀.
class LocalPrefs {
  static SharedPreferences? _p;

  static Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {}
  }

  static String? stringSync(String key) {
    try {
      return _p?.getString(key);
    } catch (_) {
      return null;
    }
  }

  static List<String> listSync(String key) {
    try {
      return _p?.getStringList(key) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  static bool? boolSync(String key) {
    try {
      return _p?.getBool(key);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getString(String key) async {
    if (_p == null) await init();
    return stringSync(key);
  }

  static Future<void> setString(String key, String value) async {
    try {
      if (_p == null) await init();
      await _p?.setString(key, value);
    } catch (_) {}
  }

  static Future<List<String>> getList(String key) async {
    if (_p == null) await init();
    return listSync(key);
  }

  static Future<void> setList(String key, List<String> value) async {
    try {
      if (_p == null) await init();
      await _p?.setStringList(key, value);
    } catch (_) {}
  }

  static Future<void> remove(String key) async {
    try {
      if (_p == null) await init();
      await _p?.remove(key);
    } catch (_) {}
  }

  static Future<void> setBool(String key, bool value) async {
    try {
      if (_p == null) await init();
      await _p?.setBool(key, value);
    } catch (_) {}
  }
}
