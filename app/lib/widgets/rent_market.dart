import 'package:flutter/material.dart';

import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';

/// 혜택 탭 "전월세" 구역(2026-10-31): 국토교통부 아파트·오피스텔 전월세 실거래가로 우리 동네 시세 "체감" — 아파트 전세·아파트 월세·오피스텔 월세의
/// 가장 최근 완결된 달 중위값과 한 달 전 대비, 그리고 최근 계약. 시군구를 골라야 보임(시도 전체는 호출이 너무 많아서 서버가 안 줌).
/// 우리가 거래를 모아 계산한 참고 통계이고 원본은 국토교통부 실거래가 공개시스템이라고 화면에 밝힘.
class RentMarketSection extends StatefulWidget {
  const RentMarketSection({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  @override
  State<RentMarketSection> createState() => _RentMarketSectionState();
}

/// 만원 단위 정수 → "15억 5,000만원" / "3,000만원".
String wonLabel(int manwon) {
  if (manwon >= 10000) {
    final eok = manwon ~/ 10000;
    final rest = manwon % 10000;
    return rest == 0 ? '$eok억원' : '$eok억 ${formatNumber(rest)}만원';
  }
  return '${formatNumber(manwon)}만원';
}

class _RentMarketSectionState extends State<RentMarketSection> {
  late Future<Map<String, dynamic>> _future = _load();

  Future<Map<String, dynamic>> _load() => widget.api.rentMarket(sido: widget.region.code, sgg: widget.region.sgg);

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  static const _title = '우리 동네 전월세 시세';
  static const _info = [
    '국토교통부 실거래가 공개시스템에 신고된 아파트·오피스텔 전월세 계약을 데일리컷이 모아 중위값(가운데 값)으로 계산한 참고 통계예요.',
    '계약 신고는 늦게 들어와서 이번 달은 늘 덜 찬 상태예요. 그래서 거래가 충분히 쌓인 가장 최근 달을 기준으로 그 전 달과 비교해요.',
    '단지·면적 구성에 따라 값이 크게 움직일 수 있어요. 한 달에 5건 미만이면 계산하지 않아요. 실제 계약은 공인중개사·원본 기록으로 꼭 확인해 주세요.',
  ];

  Widget _message(Widget child, {VoidCallback? onTap}) => ListSection(
        title: _title,
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 56), child: Center(child: child)),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (snap.hasError) {
          return _message(const Text('시세를 불러오지 못했어요. 눌러서 다시 시도', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)), onTap: _reload);
        }
        if (d == null) return _message(const LoadingNote());
        if (d['need_sgg'] == true) {
          return _message(
            const Text('시군구를 고르면 우리 동네 전월세 시세를 보여 드려요.\n눌러서 지역 고르기', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6)),
            onTap: () => showRegionPicker(context),
          );
        }
        if (d['live'] != true) {
          return _message(const Text('이 지역 시세를 불러오지 못했어요. 눌러서 다시 시도', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)), onTap: _reload);
        }
        final sections = (d['sections'] as List).cast<Map<String, dynamic>>();
        final recent = (d['recent'] as List).cast<Map<String, dynamic>>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListSection(
              title: _title,
              trailing: d['region'] as String?,
              info: const InfoIconButton(title: '전월세 시세 안내', lines: _info),
              children: [for (final s in sections) _summary(s)],
            ),
            ListSection(
              title: '최근 계약',
              trailing: '신고된 순',
              children: [
                ExpandableList(children: [for (final r in recent) _contract(r)]),
              ],
            ),
          ],
        );
      },
    );
  }

  String _monthName(String ym) => '${int.parse(ym.substring(4))}월';

  Widget _summary(Map<String, dynamic> s) {
    final now = s['now'] as Map<String, dynamic>?;
    final title = s['title'] as String;
    if (now == null) {
      return ListLine(name: title, sub: '거래가 적어 계산하지 않았어요', value: '-');
    }
    final isRent = s['key'] != 'apt_jeonse';
    final dep = now['dep'] as int;
    final rent = now['rent'] as int?;
    final pct = (s['pct'] as num?)?.toDouble();
    final String value = isRent ? '월 ${formatNumber(rent ?? 0)}만원' : wonLabel(dep);
    final change = pct == null ? 'flat' : (pct.abs() < 1 ? 'flat' : (pct > 0 ? 'up' : 'down'));
    final prev = s['prev'] as Map<String, dynamic>?;
    return ListLine(
      name: title,
      sub: '${s['basis']} · ${_monthName(now['ym'] as String)} ${now['n']}건${isRent ? ' · 보증금 ${wonLabel(dep)}' : ''}',
      value: value,
      valueSub: pct == null || prev == null ? null : (change == 'flat' ? '${_monthName(prev['ym'] as String)}과 비슷해요' : '${_monthName(prev['ym'] as String)}보다 ${changeLabel(change, pct: pct)}'),
      valueSubColor: changeColor(change),
    );
  }

  Widget _contract(Map<String, dynamic> r) {
    final rent = r['rent'] as int;
    final dep = r['dep'] as int;
    final value = rent == 0 ? '전세 ${wonLabel(dep)}' : '${formatNumber(dep)}/${formatNumber(rent)}만원';
    final floor = (r['floor'] as String?)?.isNotEmpty ?? false ? ' · ${r['floor']}층' : '';
    return ListLine(
      name: r['name'] as String,
      sub: '${r['kind']} · 전용 ${r['area']}㎡$floor · ${r['umd']}',
      value: value,
      valueSub: '${r['date']} 계약',
    );
  }
}
