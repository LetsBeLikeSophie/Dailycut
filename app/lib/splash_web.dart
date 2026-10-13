import 'package:web/web.dart' as web;

/// web/index.html의 HTML 스플래시("데일리컷")를 걷어냄. 앱 엔진이 뜬 직후가 아니라 첫 화면 데이터가 준비된 뒤에 불러서,
/// 엔진 로딩 → 데이터 로딩의 스피너가 연달아 두 번 보이지 않게 함. 여러 번 불러도 안전함.
void hideSplash() {
  final el = web.document.getElementById('splash');
  if (el == null) return;
  el.classList.add('done');
  Future<void>.delayed(const Duration(milliseconds: 400), () => el.remove());
}
