import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// 웹: 같은 사이트의 ad.html(카카오 애드핏 스크립트가 들어 있는 작은 페이지)을 iframe으로 띄움.
/// 광고 단위 ID·크기는 쿼리로 넘김. 같은 도메인이라야 애드핏이 등록된 사이트로 인식함.
Widget buildAdView(String unit, int width, int height) {
  return HtmlElementView.fromTagName(
    tagName: 'iframe',
    onElementCreated: (Object el) {
      final f = el as web.HTMLIFrameElement;
      final base = web.document.baseURI;
      f.src = '${base}ad.html?unit=${Uri.encodeQueryComponent(unit)}&w=$width&h=$height';
      f.style.border = '0';
      f.style.width = '100%';
      f.style.height = '100%';
      f.setAttribute('scrolling', 'no');
      f.setAttribute('title', '광고');
    },
  );
}
