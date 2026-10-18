import 'package:flutter/foundation.dart';

import 'analytics.dart';
import 'local_prefs.dart';
import 'widget_bridge.dart';

/// 내 장바구니: 생활 탭 맨 위 차트에 올릴 품목. 기본값 없음(비어 있음) — 사용자가 장보기 시세에서
/// 밀어서 담은 것만 들어감. 로그인이 없어서 기기에만 저장함(shared_preferences).
class MyBasket extends ChangeNotifier {
  MyBasket._();
  static final MyBasket instance = MyBasket._();

  static const _key = 'my_basket_v2'; // v1은 "기본 8품목이 이미 담긴" 방식이라 버림

  List<String> suggestions = const []; // 서버가 알려준 대표 품목("대표 품목으로 시작" 버튼용)
  List<String> _names = [];
  bool _loaded = false;

  List<String> get names => List.unmodifiable(_names);
  bool get isEmpty => _names.isEmpty;
  bool contains(String name) => _names.contains(name);

  /// 앱이 뜨기 전에 한 번(main) — 첫 프레임부터 저장된 품목이 보이게(예전엔 비동기로 읽어 "비었음 → 채워짐"으로 두 번 그렸음).
  void loadSync() {
    if (_loaded) return;
    _loaded = true;
    _names = [...LocalPrefs.listSync(_key)];
  }

  Future<void> load() async {
    if (_loaded) return;
    await LocalPrefs.init();
    loadSync();
    notifyListeners();
  }

  Future<void> _save() async {
    notifyListeners();
    await LocalPrefs.setList(_key, _names);
    WidgetBridge.refresh(); // 홈 화면 장바구니 위젯도 바뀐 품목 기준으로(저장이 끝난 뒤)
  }

  /// 담았으면 true, 뺐으면 false
  Future<bool> toggle(String name) async {
    final added = !_names.contains(name);
    Analytics.instance.track(added ? 'basket_add' : 'basket_remove', name);
    added ? _names.add(name) : _names.remove(name);
    await _save();
    return added;
  }

  Future<void> addAll(Iterable<String> items) async {
    for (final n in items) {
      if (!_names.contains(n)) _names.add(n);
    }
    await _save();
  }
}
