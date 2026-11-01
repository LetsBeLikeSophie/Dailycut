import 'package:flutter/material.dart';

import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';
import 'local_currency_stores.dart';
import 'support_profile.dart';

/// 혜택 탭 "지역화폐" 구역(2026-10-31): 한국조폐공사 지역사랑상품권 가맹점 업종별 결제정보로 우리 동네 상품권이 지난달 얼마나·어디서·누가 쓰였는지.
/// 시군구를 골라야 보임. 상품권이 없는 지역은 자료가 없다고 안내. 처음 부르는 지역은 서버가 뒤에서 계산해서(큰 도시 30~50초) 로딩이 길 수 있음.
/// 가맹점 목록은 일부러 안 보여 줌(가맹점 기본정보 API가 2022년 기준이 섞여 있고 폐업자가 많아서) — docs/data-sources.md.
class LocalCurrencySection extends StatefulWidget {
  const LocalCurrencySection({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  @override
  State<LocalCurrencySection> createState() => _LocalCurrencySectionState();
}

/// 원 단위 → "117억원" / "11.7억원" / "3,450만원".
String wonShort(int won) {
  if (won >= 10000000000) return '${formatNumber((won / 100000000).round())}억원';
  if (won >= 100000000) return '${(won / 100000000).toStringAsFixed(1)}억원';
  return '${formatNumber((won / 10000).round())}만원';
}

/// 건수 → "28.2만건" / "9,500건".
String countShort(int n) => n >= 10000 ? '${(n / 10000).toStringAsFixed(1)}만건' : '${formatNumber(n)}건';

/// 한 번 결제 평균 → "2.1만원" / "9,500원".
String avgShort(int won) {
  if (won < 10000) return '${formatNumber(won)}원';
  final s = (won / 10000).toStringAsFixed(1);
  return '${s.endsWith('.0') ? s.substring(0, s.length - 2) : s}만원';
}

/// 만 나이 → 지역화폐 자료의 연령 코드(01 19세 이하 … 06 60대 이상).
String ageCodeOf(int age) => age < 20 ? '01' : '0${(age ~/ 10).clamp(2, 6)}';

class _LocalCurrencySectionState extends State<LocalCurrencySection> {
  late Future<Map<String, dynamic>> _future = _load();
  final _finderKey = GlobalKey<StoreFinderState>();

  /// 내 또래로 볼 연령대. "내 조건"에 생년월일이 있으면 그 나이로 시작하고(기기 안에서만 계산, 서버엔 안 보냄), 없으면 직접 고름.
  late String? _ageCode = SupportProfile.instance.age == null ? null : ageCodeOf(SupportProfile.instance.age!);

  Future<Map<String, dynamic>> _load() => widget.api.localCurrency(sido: widget.region.code, sgg: widget.region.sgg);

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  static const _title = '지난달 우리 동네 상품권';
  static const _info = [
    '한국조폐공사가 전국 지역사랑상품권 운영대행사들로부터 모은 "가맹점 업종별 결제정보"를 월 단위로 합산한 값이에요. 취소 내역을 반영한 결제금액·건수예요.',
    '아직 덜 찬 이번 달은 빼고, 자료가 있는 가장 최근 달을 보여 줘요. 상품권을 막 시작했거나 쓸 수 있는 곳이 적은 지역은 달마다 값이 크게 달라질 수 있어요.',
    '연령대는 결제한 사람의 나이대 기준이고, 지역은 상품권을 쓴 가게가 있는 시군구예요. 지역마다 상품권 종류(카드·모바일·지류)와 사용처가 달라서 다른 지역과 금액을 그대로 비교하기는 어려워요.',
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
    // 위: 쓸 수 있는 가게 찾기(통계를 기다리지 않고 바로 뜸), 아래: 통계(처음 보는 지역은 30초쯤 걸림)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.region.sgg != null) StoreFinder(key: _finderKey, api: widget.api, region: widget.region, stats: _future),
        _stats(),
      ],
    );
  }

  Widget _stats() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (snap.hasError) {
          return _message(const Text('상품권 정보를 불러오지 못했어요. 눌러서 다시 시도', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)), onTap: _reload);
        }
        if (d == null) return _message(const LoadingNote(label: '불러오는 중이에요\n처음 보는 지역은 30초쯤 걸릴 수 있어요'));
        if (d['need_sgg'] == true) {
          return _message(
            const Text('시군구를 고르면 우리 동네 상품권 사용 현황을 보여 드려요.\n눌러서 지역 고르기', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6)),
            onTap: () => showRegionPicker(context),
          );
        }
        if (d['live'] != true) {
          return _message(const Text('이 지역 정보를 불러오지 못했어요. 눌러서 다시 시도', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)), onTap: _reload);
        }
        if (d['empty'] == true) {
          return _message(const Text('이 지역은 지역사랑상품권 결제 자료가 없어요.\n다른 시군구를 골라 보세요', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6)));
        }
        final now = d['now'] as Map<String, dynamic>;
        final prev = d['prev'] as Map<String, dynamic>?;
        final pct = (d['pct'] as num?)?.toDouble();
        final industries = (d['industries'] as List).cast<Map<String, dynamic>>();
        final ages = (d['ages'] as List).cast<Map<String, dynamic>>();
        final byAge = ((d['by_age'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as List).cast<Map<String, dynamic>>()));
        final dongs = ((d['dongs'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final change = pct == null ? 'flat' : (pct.abs() < 1 ? 'flat' : (pct > 0 ? 'up' : 'down'));
        final month = _monthName(now['ym'] as String);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (byAge.isNotEmpty) _peerSection(month, ages, byAge),
            ListSection(
              title: _title,
              trailing: d['region'] as String?,
              info: const InfoIconButton(title: '지역화폐 안내', lines: _info),
              children: [
                ListLine(
                  name: '$month 결제금액',
                  sub: '지역사랑상품권으로 결제한 총액',
                  value: wonShort(now['amt'] as int),
                  valueSub: pct == null || prev == null ? null : (change == 'flat' ? '${_monthName(prev['ym'] as String)}과 비슷해요' : '${_monthName(prev['ym'] as String)}보다 ${changeLabel(change, pct: pct)}'),
                  valueSubColor: changeColor(change),
                ),
                ListLine(name: '$month 결제 건수', sub: '취소를 뺀 결제 횟수', value: countShort(now['nocs'] as int)),
              ],
            ),
            ListSection(
              title: '많이 쓴 곳',
              trailing: '$month 업종별 비중',
              children: [
                for (final r in industries)
                  ListLine(
                    name: r['name'] as String,
                    sub: r['avg'] == null ? null : '한 번에 평균 ${avgShort(r['avg'] as int)}',
                    value: '${r['share']}%',
                    valueSub: wonShort(r['amt'] as int),
                  ),
              ],
            ),
            if (dongs.isNotEmpty)
              ListSection(
                title: '동네별로 보면',
                trailing: '$month 결제금액 비중',
                children: [
                  for (final r in dongs) ListLine(name: r['name'] as String, value: '${r['share']}%'),
                ],
              ),
            if (ages.isNotEmpty)
              ListSection(
                title: '많이 쓴 나이대',
                trailing: '$month 결제금액 비중',
                children: [
                  for (final r in ages) ListLine(name: r['label'] as String, value: '${r['share']}%'),
                ],
              ),
          ],
        );
      },
    );
  }

  /// "내 또래는 어디서 쓸까" — 고른 나이대가 쓴 돈이 많은 동네×업종 순위. 가게별 결제액은 자료에 없어서 가장 잘게 쪼갠 단위가 이거고,
  /// 줄을 누르면 위의 "상품권 쓸 수 있는 가게"가 그 동네·업종으로 맞춰짐(2026-11-01 사용자 의견: 통계보다 실제 가게로 이어져야 도움이 됨).
  Widget _peerSection(String month, List<Map<String, dynamic>> ages, Map<String, List<Map<String, dynamic>>> byAge) {
    final labels = {for (final a in ages) a['code'] as String: a['label'] as String};
    final codes = labels.keys.where(byAge.containsKey).toList();
    final code = codes.contains(_ageCode) ? _ageCode : null;
    return ListSection(
      title: '내 또래는 어디서 쓸까',
      trailing: code == null ? '나이대를 골라 보세요' : '${labels[code]}이 많이 쓴 동네·업종',
      info: const InfoIconButton(
        title: '내 또래 안내',
        lines: [
          '결제한 사람의 나이대별로, 돈이 많이 쓰인 동네와 업종을 순서대로 보여 줘요. 줄을 누르면 그 동네·업종의 상품권 가게 목록이 위에 열려요.',
          '가게별 결제액은 공개 자료에 없어서 "어느 가게가 1등인지"는 알 수 없어요. 숫자는 그 나이대 결제금액 안에서의 비중이에요.',
          '"내 조건"에 생년월일을 저장해 두면 내 나이대로 바로 열려요. 생년월일은 이 기기 안에서만 쓰고 서버로 보내지 않아요.',
        ],
      ),
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final c in codes) PillChip(label: labels[c]!, selected: c == code, onTap: () => setState(() => _ageCode = c)),
            ],
          ),
        ),
        if (code == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text('위에서 나이대를 고르면 또래가 많이 쓰는 곳을 보여 드려요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
          )
        else
          ...[
            for (final r in byAge[code]!)
              ListLine(
                name: '${r['dong']} · ${r['cat']}',
                sub: r['avg'] == null ? '눌러서 가게 보기' : '한 번에 평균 ${avgShort(r['avg'] as int)} · 눌러서 가게 보기',
                value: '${r['share']}%',
                onTap: () => _finderKey.currentState?.focus(emd: r['emd'] as String, dong: r['dong'] as String, ksic: r['ksic'] as String, catName: r['cat'] as String),
              ),
          ],
      ],
    );
  }

  String _monthName(String ym) => '${int.parse(ym.substring(4))}월';
}
