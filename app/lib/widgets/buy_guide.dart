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

  static const _info = [
    '지자체·운영사 공식 페이지를 직접 열어 확인한 것만 모았어요.',
    '발행 일정·할인율·구매 한도는 회차마다 바뀌어서, 기준 날짜가 적힌 값만 보여 줘요.',
    '아래 "확인"은 데일리컷이 공식 페이지를 마지막으로 본 날이에요.',
  ];

  Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

  /// 출처 URL의 사이트 주소만 중복 없이(글 제목은 길어서 안 씀).
  String _hosts(List<Map<String, dynamic>> sources) {
    final hosts = <String>{for (final s in sources) ?Uri.tryParse(s['url'] as String? ?? '')?.host};
    return hosts.take(4).join(' · ') + (hosts.length > 4 ? ' 외 ${hosts.length - 4}곳' : '');
  }

  /// 사는 곳 한 줄. 이름이 짧으면 그대로, 설명 문장이면 종류(앱·카드·지류)를 이름으로 하고 문장은 작은 글로.
  Widget _channelLine(Map<String, dynamic> c) {
    final name = c['name'] as String;
    final kind = c['kind'] as String? ?? '';
    final url = c['url'] as String?;
    final long = name.length > 18;
    return ListLine(
      name: long ? (kind == '지류' ? '지류(종이)로 사기' : '$kind 안내') : name,
      sub: long ? name : kind,
      value: url == null ? null : '열기',
      onTap: url == null ? null : () => _open(url),
    );
  }

  /// 조건 한 줄(할인율·한도). 값이 짧으면 오른쪽에 크게, 길면 작은 글로 내리고, 기준일은 항상 함께.
  Widget _termLine(Map<String, dynamic> t) {
    final value = t['value'] as String;
    final asof = t['asof'] as String?;
    final date = '기준 ${dotDate(asof)}${(_ageDays(asof) ?? 0) >= _termStaleDays ? ' · 오래됨' : ''}';
    final until = dotDate(t['until'] as String?);
    final tail = until.isEmpty ? date : '$date · ~$until까지';
    final short = value.length <= 14;
    final url = t['url'] as String?;
    return ListLine(
      name: t['label'] as String,
      sub: short ? null : '$value\n$tail',
      value: short ? value : null,
      valueSub: short ? tail : null,
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
        final kinds = (d['kinds'] as List?)?.cast<String>();
        final name = d['name'] as String?;
        return ListSection(
          title: '상품권 사는 법',
          trailing: dotDate(checked).isEmpty ? null : '확인 ${dotDate(checked)}',
          info: const InfoIconButton(title: '사는 법 안내', lines: _info),
          children: [
            if (name != null) ListLine(name: name, sub: kinds == null ? '이 지역 상품권' : kinds.join(' · ')),
            for (final c in channels) _channelLine(c),
            if (official != null) ListLine(name: '발행 일정·공지', sub: official['label'] as String?, value: '열기', onTap: () => _open(official['url'] as String)),
            if (phone != null)
              ListLine(
                name: phone['label'] as String? ?? '문의',
                value: phone['number'] as String,
                onTap: () => launchUrl(Uri.parse('tel:${(phone['number'] as String).replaceAll(RegExp(r'[^0-9]'), '')}')),
              ),
            if (showNotice)
              ListLine(
                name: notice['title'] as String,
                sub: '최근 공지 · 게시 ${dotDate(notice['date'] as String?)}',
                onTap: (notice['url'] as String?) == null ? null : () => _open(notice['url'] as String),
              ),
            if (terms.isNotEmpty) ExpandableList(unit: '개', limit: 4, children: [for (final t in terms) _termLine(t)]),
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
