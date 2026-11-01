import 'package:flutter/material.dart';

import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'ad_slot.dart';
import 'buy_guide.dart';
import 'components.dart';
import 'local_currency_stores.dart';
import 'paper_vouchers.dart';
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
    '월 단위로 합산했고 취소를 반영한 값이에요.\n덜 찬 이번 달은 빼고, 자료가 있는 가장 최근 달이에요.',
    '지역은 상품권을 쓴 가게가 있는 시군구, 나이대는 결제한 사람 기준이에요.',
    '지역마다 상품권 종류와 사용처가 달라 금액을 그대로 비교하기는 어려워요.',
  ];

  /// 위로 올린 통계 그래프에서 지금 보는 쪽(0 결제금액 · 1 많이 쓴 곳 · 2 나이대 · 3 동네).
  int _heroPage = 0;

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
    // 맨 위: 지난달 통계(화살표로 넘겨 보는 그래프) → 사는 법 → 종이 상품권 → 쓸 수 있는 가게 → 내 또래(통계 응답이 와야 나옴)
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _statsHero(),
        if (widget.region.sgg != null) ...[
          BuyGuideSection(api: widget.api, region: widget.region),
          PaperVoucherSection(api: widget.api, region: widget.region),
          StoreFinder(key: _finderKey, api: widget.api, region: widget.region, stats: _future),
          const AdSlot(), // 광고(2026-11-01): 가게 목록과 "내 또래" 사이 구분선 자리
        ],
        _peer(),
      ],
    );
  }

  /// 통계 그래프(2026-11-01 사용자 의견: 통계를 제목 바로 아래로 올리고 화살표로 한 장씩 시각 자료로). 결제금액 → 업종 → 나이대 → 동네.
  Widget _statsHero() {
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
        final dongs = ((d['dongs'] as List?) ?? const []).cast<Map<String, dynamic>>();
        final change = pct == null ? 'flat' : (pct.abs() < 1 ? 'flat' : (pct > 0 ? 'up' : 'down'));
        final month = _monthName(now['ym'] as String);
        final pages = <(String, Widget)>[
          ('$month 결제금액', _amountPage(now, prev, pct, change)),
          ('많이 쓴 곳', _Bars(rows: [for (final r in industries) (r['name'] as String, (r['share'] as num).toDouble(), '${r['share']}% · ${wonShort(r['amt'] as int)}')])),
          if (ages.isNotEmpty) ('많이 쓴 나이대', Align(alignment: Alignment.topCenter, child: SizedBox(height: 236, child: _Columns(rows: [for (final r in ages) (r['label'] as String, (r['share'] as num).toDouble())])))),
          if (dongs.isNotEmpty) ('동네별로 보면', _Bars(rows: [for (final r in dongs) (r['name'] as String, (r['share'] as num).toDouble(), '${r['share']}%')])),
        ];
        final page = _heroPage.clamp(0, pages.length - 1);
        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 출처·기준은 다른 화면처럼 ⓘ 안에(2026-11-01 사용자 의견: 표로 따로 늘어놓지 말고 ⓘ로 통일)
              ArrowSelector(
                label: pages[page].$1,
                index: page,
                count: pages.length,
                onChanged: (i) => setState(() => _heroPage = i),
                info: const InfoIconButton(title: '지역화폐 통계 안내', lines: _info, sources: [('한국조폐공사', 'https://www.komsco.com')]),
              ),
              const SizedBox(height: 14),
              SizedBox(height: 316, child: KeyedSubtree(key: ValueKey('hp$page'), child: pages[page].$2)),
            ],
          ),
        );
      },
    );
  }

  /// 첫 쪽: 지난달 결제금액을 큰 숫자로, 전월 대비와 건수·한 번 평균.
  Widget _amountPage(Map<String, dynamic> now, Map<String, dynamic>? prev, double? pct, String change) {
    final amt = now['amt'] as int;
    final nocs = now['nocs'] as int;
    final big = amt >= 100000000 ? amt / 100000000 : amt / 10000;
    final decimals = amt >= 10000000000 || amt < 100000000 ? 0 : 1;
    final unit = amt >= 100000000 ? '억원' : '만원';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BigNumber(key: ValueKey('amt$amt'), to: big, decimals: decimals, unit: unit),
        const SizedBox(height: 6),
        Text(
          pct == null || prev == null ? '지역사랑상품권으로 결제한 총액' : (change == 'flat' ? '${_monthName(prev['ym'] as String)}과 비슷해요' : '${_monthName(prev['ym'] as String)}보다 ${changeLabel(change, pct: pct)}'),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: pct == null ? AppColors.inkSoft : changeColor(change)),
        ),
        const SizedBox(height: 20),
        Container(height: 1, color: AppColors.hair),
        ListLine(name: '결제 건수', sub: '취소를 뺀 결제 횟수', value: countShort(nocs)),
        ListLine(name: '한 번에 평균', sub: '결제금액 ÷ 결제 건수', value: nocs == 0 ? '-' : avgShort((amt / nocs).round())),
      ],
    );
  }

  /// 맨 아래: 내 또래(통계 응답이 와야 나옴. 실패·빈 지역 안내는 위쪽 통계 자리에서 이미 보여 줌).
  Widget _peer() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null || d['live'] != true || d['empty'] == true || d['need_sgg'] == true) return const SizedBox.shrink();
        final byAge = ((d['by_age'] as Map?) ?? const {}).map((k, v) => MapEntry(k as String, (v as List).cast<Map<String, dynamic>>()));
        if (byAge.isEmpty) return const SizedBox.shrink();
        final ages = (d['ages'] as List).cast<Map<String, dynamic>>();
        final month = _monthName((d['now'] as Map<String, dynamic>)['ym'] as String);
        return _peerSection(month, ages, byAge);
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
          '나이대별로 돈이 많이 쓰인 동네와 업종이에요.\n줄을 누르면 그 동네·업종의 가게 목록이 위에 열려요.',
          '가게별 결제액은 공개 자료에 없어서\n어느 가게가 1등인지는 알 수 없어요.\n숫자는 그 나이대 결제금액 안에서의 비중이에요.',
          '"내 조건"에 생년월일을 저장하면 내 나이대로 바로 열려요.\n생년월일은 이 기기에서만 쓰고 서버로 보내지 않아요.',
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


/// 가로 막대 한 묶음(이름 · 막대 · 오른쪽 값). 막대 길이는 가장 큰 값을 100%로 한 비율. 색은 잉크 한 가지(색은 형광펜·도형에만 쓰는 규칙).
class _Bars extends StatelessWidget {
  const _Bars({required this.rows});

  final List<(String, double, String)> rows; // (이름, 비중 %, 오른쪽에 쓸 글)

  @override
  Widget build(BuildContext context) {
    final top = rows.fold<double>(0, (m, r) => r.$2 > m ? r.$2 : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final r in rows.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(r.$1, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                    Text(r.$3, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 6),
                LayoutBuilder(
                  builder: (context, c) => Stack(
                    children: [
                      Container(height: 6, color: AppColors.hair),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: top == 0 ? 0 : r.$2 / top),
                        duration: const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Container(height: 6, width: c.maxWidth * v, color: AppColors.ink),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}


/// 나이대처럼 순서가 있는 짧은 이름 몇 개를 세로 막대로(왼쪽이 어린 쪽). 가장 큰 막대 끝에만 섹션 색 점(색은 차트 끝점에만 쓰는 규칙).
class _Columns extends StatelessWidget {
  const _Columns({required this.rows});

  final List<(String, double)> rows; // (이름, 비중 %)

  @override
  Widget build(BuildContext context) {
    final top = rows.fold<double>(0, (m, r) => r.$2 > m ? r.$2 : m);
    final accent = sectionThemes[Section.money]!.color;
    return LayoutBuilder(
      builder: (context, c) {
        const labelBox = 22.0; // 아래 이름 칸
        const valueBox = 22.0; // 막대 위 값 칸
        final maxBar = c.maxHeight - labelBox - valueBox - 12;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final r in rows)
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    SizedBox(
                      height: valueBox,
                      child: Align(alignment: Alignment.bottomCenter, child: Text('${r.$2 % 1 == 0 ? r.$2.toInt() : r.$2}%', style: TextStyle(fontSize: 13, fontWeight: r.$2 == top ? FontWeight.w700 : FontWeight.w400))),
                    ),
                    const SizedBox(height: 4),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: top == 0 ? 0 : r.$2 / top),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => Container(
                        width: 28,
                        height: maxBar * v < 3 ? 3 : maxBar * v,
                        alignment: Alignment.topCenter,
                        color: AppColors.ink,
                        child: r.$2 == top ? Transform.translate(offset: const Offset(0, -4), child: Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle))) : null,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(height: labelBox - 8, child: Text(r.$1, maxLines: 1, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft))),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
