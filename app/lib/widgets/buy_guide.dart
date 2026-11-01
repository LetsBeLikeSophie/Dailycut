import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';
import '../region.dart';
import 'components.dart';

/// 상품권 사는 법(2026-11-01): 이 지역 상품권 이름, 사는 앱·곳, 공식 공지 페이지, 고객센터, 최근 공지.
/// 값은 사람이 지자체·운영사 공식 페이지를 직접 열어 확인해 모은 것(backend/data/localcurrency_guide.json)이라
/// 항목마다 출처와 확인일이 붙음. 발행 일정·할인율은 회차마다 바뀌어서, 기준 날짜가 적힌 값만 보여 주고
/// 날짜가 오래되면 "오래됨"을 붙임. 이 지역 자료가 없으면 구역을 통째로 숨김(예전엔 네이버 검색 줄을 뒀지만 폐기).
class BuyGuideSection extends StatefulWidget {
  const BuyGuideSection({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  @override
  State<BuyGuideSection> createState() => _BuyGuideSectionState();
}

/// 확인일(YYYY-MM-DD)로부터 며칠 지났는지(못 읽으면 null).
int? _ageDays(String? iso) {
  final t = DateTime.tryParse(iso ?? '');
  return t == null ? null : DateTime.now().difference(t).inDays;
}

/// 종료일(until)이 오늘보다 앞이면 끝난 혜택.
bool _ended(String? until) {
  final t = DateTime.tryParse(until ?? '');
  return t != null && DateTime.now().isAfter(t.add(const Duration(days: 1)));
}

class _BuyGuideSectionState extends State<BuyGuideSection> {
  late final Future<Map<String, dynamic>> _future = widget.api.localCurrencyGuide(sido: widget.region.code, sgg: widget.region.sgg);

  static const _staleDays = 90; // 확인한 지 이만큼 지나면 "오래됨"
  static const _termStaleDays = 120; // 조건의 기준일이 이만큼 지나면 "오래됨"
  static const _termDropDays = 300; // 이만큼 지나면 아예 안 보여 줌
  static const _noticeDays = 180; // 최근 공지는 이보다 오래되면 보여 주지 않음(옛 회차 공지를 지금 것처럼 보이지 않게)

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// 출처 URL의 사이트 주소만 중복 없이(글 제목은 길어서 안 씀).
  String _hosts(List<Map<String, dynamic>> sources) {
    final hosts = <String>{for (final s in sources) ?Uri.tryParse(s['url'] as String? ?? '')?.host};
    return hosts.take(4).join(' · ') + (hosts.length > 4 ? ' 외 ${hosts.length - 4}곳' : '');
  }

  static final _storeSuffix = RegExp(r'\s*\((아이폰|안드로이드)\)$');

  /// 사는 곳 줄들. 앱은 지금 쓰는 기기에 맞는 스토어 링크 하나만(안드로이드는 Play, 아이폰은 App Store, 컴퓨터는 둘 다).
  /// 그 기기용 링크가 자료에 없으면 안드로이드는 Play 스토어 검색으로 돌려 줌. 카드·지류는 설명 문장을 작은 글로.
  List<Widget> _channelLines(List<Map<String, dynamic>> channels, String? product) {
    bool isApple(Map c) => ((c['url'] as String?) ?? '').contains('apps.apple.com');
    bool isPlay(Map c) => ((c['url'] as String?) ?? '').contains('play.google.com');
    final platform = defaultTargetPlatform;
    final apps = <String, List<Map<String, dynamic>>>{};
    final others = <Map<String, dynamic>>[];
    for (final c in channels) {
      if (c['kind'] == '앱' && (isApple(c) || isPlay(c))) {
        apps.putIfAbsent((c['name'] as String).replaceAll(_storeSuffix, ''), () => []).add(c);
      } else {
        others.add(c);
      }
    }
    final lines = <Widget>[];
    apps.forEach((name, list) {
      final play = list.where(isPlay).toList();
      final apple = list.where(isApple).toList();
      final shown = <(String, String)>[]; // (이름 뒤 표시, 주소)
      if (platform == TargetPlatform.android) {
        shown.add(('', play.isNotEmpty ? play.first['url'] as String : Uri.https('play.google.com', '/store/search', {'q': name, 'c': 'apps'}).toString()));
      } else if (platform == TargetPlatform.iOS) {
        shown.add(('', (apple.isNotEmpty ? apple : play).first['url'] as String));
      } else {
        if (apple.isNotEmpty) shown.add((' (App Store)', apple.first['url'] as String));
        if (play.isNotEmpty) shown.add((' (Google Play)', play.first['url'] as String));
      }
      for (final (tag, url) in shown) {
        lines.add(ListLine(name: '$name$tag', sub: product == null ? '앱' : '앱 · $product', value: '앱 받기', onTap: () => _open(url)));
      }
    });
    for (final c in others) {
      final text = c['name'] as String;
      final kind = c['kind'] as String? ?? '';
      final url = c['url'] as String?;
      final long = text.length > 18;
      lines.add(ListLine(
        name: long ? (kind == '지류' ? '지류(종이)로 사기' : kind == '카드' ? '카드 발급·충전' : '$kind 안내') : text,
        sub: long ? text : kind,
        value: url == null ? null : '열기',
        onTap: url == null ? null : () => _open(url),
      ));
    }
    return lines;
  }

  /// 조건 값에서 숫자만 뽑아 오른쪽에 크게(예: 할인율 "10%", 한도 "월 50만원"). 데이터에 short가 있으면 그걸 씀.
  String? _shortOf(Map<String, dynamic> t) {
    final given = t['short'] as String?;
    if (given != null) return given;
    final label = t['label'] as String;
    final value = t['value'] as String;
    if (RegExp(r'할인|캐시백|인센티브|적립|페이백').hasMatch(label)) {
      final m = RegExp(r'\d+(?:\.\d+)?%').firstMatch(value);
      if (m != null) return m.group(0);
    }
    if (label.contains('한도')) {
      final m = RegExp(r'\d[\d,]*(?:만|천)?원').firstMatch(value);
      if (m != null) return '${label.contains('월') ? '월 ' : ''}${m.group(0)}';
    }
    return value.length <= 10 ? value : null;
  }

  /// 조건 한 줄(할인율·한도). 숫자는 오른쪽에 크게, 자세한 값은 작은 글로, 기준일은 항상 함께. 누르면 공식 공지로.
  Widget _termLine(Map<String, dynamic> t) {
    final value = t['value'] as String;
    final asof = t['asof'] as String?;
    final date = '기준 ${dotDate(asof)}${(_ageDays(asof) ?? 0) >= _termStaleDays ? ' · 오래됨' : ''}';
    final until = dotDate(t['until'] as String?);
    final tail = until.isEmpty ? date : '$date · ~$until까지';
    final short = _shortOf(t);
    final url = t['url'] as String?;
    return ListLine(
      name: t['label'] as String,
      sub: short == null ? '$value\n$tail' : (short == value ? null : '$value\n$tail'),
      value: short,
      valueSub: short != null && short == value ? tail : null,
      onTap: url == null ? null : () => _open(url),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null || d['found'] != true) return const SizedBox.shrink();
        final checked = d['checked'] as String?;
        final age = _ageDays(checked);
        final stale = age != null && age >= _staleDays;
        final channels = ((d['channels'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final official = d['official'] as Map<String, dynamic>?;
        final phone = d['phone'] as Map<String, dynamic>?;
        final notice = d['notice'] as Map<String, dynamic>?;
        final noticeAge = _ageDays(notice?['date'] as String?);
        final showNotice = notice != null && (noticeAge == null || noticeAge <= _noticeDays);
        // 한시 혜택은 until(종료일)이 지나면 숨기고, 기준일이 너무 오래된 조건도 뺌(옛 회차 값을 지금 것처럼 보이지 않게)
        final terms = [
          for (final t in ((d['terms'] as List?) ?? const []).cast<Map<String, dynamic>>())
            if (!_ended(t['until'] as String?) && (_ageDays(t['asof'] as String?) ?? 0) <= _termDropDays) t,
        ];
        final sources = ((d['sources'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final name = d['name'] as String?;
        final others = _channelLines(channels, name);
        final rows = <Widget>[
          ...others.where((w) => w is ListLine && w.value == '앱 받기'),
          if (official != null) ListLine(name: '발행 일정·공지', sub: official['label'] as String?, value: '열기', onTap: () => _open(official['url'] as String)),
          if (showNotice)
            ListLine(
              name: notice['title'] as String,
              sub: '최근 공지 · 게시 ${dotDate(notice['date'] as String?)}',
              onTap: (notice['url'] as String?) == null ? null : () => _open(notice['url'] as String),
            ),
          for (final t in terms) _termLine(t),
          ...others.where((w) => !(w is ListLine && w.value == '앱 받기')),
          if (phone != null)
            ListLine(
              name: phone['label'] as String? ?? '문의',
              value: phone['number'] as String,
              onTap: () => launchUrl(Uri.parse('tel:${(phone['number'] as String).replaceAll(RegExp(r'[^0-9]'), '')}')),
            ),
        ];
        return ListSection(
          title: '상품권 사는 법',
          trailing: dotDate(checked).isEmpty ? null : '업데이트 ${dotDate(checked)}',
          info: InfoIconButton(title: '사는 법 안내', lines: [
            '데일리컷이 공식 홈페이지를 직접 확인해서 업데이트해요.',
            if (dotDate(checked).isNotEmpty) '마지막 업데이트 ${dotDate(checked)}',
          ]),
          children: [
            ExpandableList(unit: '개', children: rows),
            DataMeta(rows: [
              DataMetaRow('출처', _hosts(sources)),
              DataMetaRow('확인일', dotDate(checked), stale: stale),
            ]),
          ],
        );
      },
    );
  }
}
