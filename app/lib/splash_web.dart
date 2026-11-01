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

/// 2026-11-01: iOS 26 사파리는 주소창이 알약 모양으로 화면 아래에 떠서 페이지를 덮음 → 하단 메뉴가 알약 밑에 깔려 안 보였음(사용자 스크린샷).
/// 처음엔 고정값 52를 더했다가 너무 올라와서(폰·주소창 상태마다 다름) 같은 날 **재서 쓰는 방식**으로 바꿈:
/// 앱이 쓰는 화면 높이(visualViewport = 알약 밑까지 포함)에서 `100svh`(주소창이 펼쳐졌을 때 실제로 보이는 높이)를 뺀 만큼이 가려지는 높이.
/// iPhone 사파리 브라우저(홈 화면 앱 아님)에서만, 못 재면 0.
double iosBrowserBarPad() {
  try {
    final ua = web.window.navigator.userAgent;
    if (!ua.contains('iPhone')) return 0;
    if (web.window.matchMedia('(display-mode: standalone)').matches) return 0;
    final probe = web.document.createElement('div') as web.HTMLElement;
    probe.style.cssText = 'position:fixed;left:0;top:0;width:0;height:100svh;visibility:hidden;pointer-events:none';
    web.document.body!.append(probe);
    final svh = probe.offsetHeight;
    probe.remove();
    if (svh <= 0) return 0; // svh를 모르는 옛 사파리
    final vv = web.window.visualViewport?.height ?? web.window.innerHeight.toDouble();
    return (vv - svh).clamp(0, 140).toDouble();
  } catch (_) {
    return 0;
  }
}
