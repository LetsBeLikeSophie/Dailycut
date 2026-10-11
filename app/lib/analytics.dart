import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// 익명 이용 통계: "어느 탭·칩·품목이 얼마나 쓰이는지"만 모아서 앱을 고치는 데 씀.
/// 보내는 것은 (이벤트 이름, 짧은 값)뿐 — 사용자·기기 ID, 위치, 검색어, 이름 같은 개인 정보는 없음.
/// 값은 항목 이름(예: 상추)·시도 코드·탭 이름 수준. 서버는 날짜별 횟수만 올려 저장함(store.record_usage).
/// 사용자가 끌 수 있음(출처·정보 시트의 스위치, 기기에 저장).
class Analytics {
  Analytics._();
  static final Analytics instance = Analytics._();

  static const _offKey = 'analytics_off';
  static const _defaultBase = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://127.0.0.1:8010');

  final List<Map<String, String>> _buf = [];
  Timer? _timer;
  bool _off = false;
  bool _loaded = false;

  bool get enabled => !_off;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      _off = p.getBool(_offKey) ?? false;
    } catch (_) {}
  }

  Future<void> setEnabled(bool on) async {
    _off = !on;
    if (_off) _buf.clear();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_offKey, _off);
    } catch (_) {}
  }

  /// 이벤트 하나 기록(바로 보내지 않고 모아서 20초마다·10개 넘으면 보냄). 실패해도 앱 동작엔 영향 없음.
  void track(String name, [String prop = '']) {
    _load().then((_) {
      if (_off) return;
      _buf.add({'n': name, 'p': prop});
      if (_buf.length >= 10) {
        _flush();
      } else {
        _timer ??= Timer(const Duration(seconds: 20), _flush);
      }
    });
  }

  Future<void> _flush() async {
    _timer?.cancel();
    _timer = null;
    if (_buf.isEmpty || _off) return;
    final batch = List<Map<String, String>>.from(_buf);
    _buf.clear();
    try {
      await http
          .post(
            Uri.parse('$_defaultBase/events'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'events': batch}),
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // 통계는 버려도 되므로 다시 시도하지 않음
    }
  }
}
