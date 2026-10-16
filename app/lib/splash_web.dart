import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// web/index.html의 HTML 스플래시("데일리컷")를 걷어냄. 앱 엔진이 뜬 직후가 아니라 첫 화면 데이터가 준비된 뒤에 불러서,
/// 엔진 로딩 → 데이터 로딩의 스피너가 연달아 두 번 보이지 않게 함. 여러 번 불러도 안전함.
void hideSplash() {
  final el = web.document.getElementById('splash');
  if (el == null) return;
  el.classList.add('done');
  Future<void>.delayed(const Duration(milliseconds: 400), () => el.remove());
}

/// index.html이 앱 부팅과 별개로 미리 받아 둔 `/weather` 응답(window.__dcEarly = {key: '시도|시군구', p: Promise<본문 텍스트>})을
/// 같은 지역일 때 한 번만 꺼내 씀 — 앱이 뜬 뒤 같은 날씨를 다시 요청하지 않게. 없거나 다른 지역이면 null.
Future<Map<String, dynamic>?> takeEarlyWeather(String key) async {
  try {
    final early = globalContext.getProperty<JSAny?>('__dcEarly'.toJS);
    if (early == null || early.isUndefinedOrNull) return null;
    final o = early as JSObject;
    final k = o.getProperty<JSAny?>('key'.toJS);
    if (k == null || k.isUndefinedOrNull || (k as JSString).toDart != key) return null;
    o.setProperty('key'.toJS, ''.toJS); // 한 번만
    final p = o.getProperty<JSAny?>('p'.toJS);
    if (p == null || p.isUndefinedOrNull) return null;
    final text = await (p as JSPromise<JSAny?>).toDart;
    if (text == null || text.isUndefinedOrNull) return null;
    return jsonDecode((text as JSString).toDart) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
