import 'package:flutter/material.dart';
import '../analytics.dart';
import '../api_client.dart';
import '../local_prefs.dart';
import '../region.dart';
import '../theme.dart';
import '../boot.dart';
import '../widgets/swipe.dart';
import '../widgets/basket_hero.dart';
import '../widgets/weekend_weather.dart';
import '../widgets/benefit_feed.dart';
import '../widgets/local_currency.dart';
import '../widgets/rent_market.dart';
import '../widgets/components.dart';
import '../widgets/ad_slot.dart';
import '../widgets/outing_section.dart';
import '../widgets/place_feed.dart';
import '../widgets/reels_links.dart';
import '../widgets/culture_calendar.dart';
import '../widgets/gov_support.dart';
import '../widgets/market_list.dart';
import '../widgets/shopping_catalog.dart';
import '../widgets/sources_info.dart';

/// 생활/문화/혜택/AI 네 섹션 화면 — 모두 "future 하나 받아서 위에서
/// 아래로 보여주기" 구조가 같아서 하나의 뼈대 위젯으로 묶고, 섹션마다
/// 다른 건 contentBuilder로만 갈아끼움.
class SectionScreen extends StatefulWidget {
  const SectionScreen({
    super.key,
    required this.section,
    required this.fetch,
    required this.contentBuilder,
  });

  final Section section;
  final Future<Map<String, dynamic>> Function() fetch;
  final List<Widget> Function(BuildContext context, Map<String, dynamic> data) contentBuilder;

  @override
  State<SectionScreen> createState() => _SectionScreenState();
}

class _SectionScreenState extends State<SectionScreen> {
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.fetch();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('불러오지 못했어요\n${snapshot.error}', textAlign: TextAlign.center));
        }
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: widget.contentBuilder(context, snapshot.data!),
        );
      },
    );
  }
}

/// 서버가 실데이터로 덮어쓴 필드인지(live_keys) — 아니면 아직 스텁(예시)임.
bool _isLive(Map<String, dynamic> data, String key) => (data['live_keys'] as List?)?.contains(key) ?? false;

String? _sourceLabel(String? source, bool live) => source == null ? null : (live ? source : '$source · 예시 데이터');

List<Widget> _priceRows(List<Map<String, dynamic>> items) => [for (final it in items) priceRow(it)];

/// 생활: 장바구니 지수(대표 품목 묶음의 지난주 대비) + 품목 칩으로 보는 추이, 그 아래 카테고리별 장보기 시세
/// (제철 표시·상세 포함), 전통시장. 서버가 아직 실데이터를 못 주면(스텁) 예전 화면(배추 + 제철 목록)으로 보임.
Widget marketScreen(ApiClient api, Region region, BuildContext shellContext) => SectionScreen(
      section: Section.market,
      fetch: () => api.market(sido: region.code, sgg: region.sgg),
      contentBuilder: (context, data) {
        final essentials = (data['essentials'] as List).cast<Map<String, dynamic>>();
        final marketsNearby = (data['markets_nearby'] as List).cast<Map<String, dynamic>>();

        final basket = data['basket'] as Map<String, dynamic>?;
        final catalogRaw = data['catalog'] as List?;
        final Widget hero;
        final List<Widget> listing;

        if (basket != null && catalogRaw != null) {
          hero = BasketHero(
            chartItems: (data['chart_items'] as Map<String, dynamic>?) ?? const {},
            suggestions: (basket['items'] as List).cast<String>(),
            eyebrow: '생활 · ${region.label}',
            onEyebrowTap: () => showRegionPicker(shellContext),
            source: _sourceLabel(data['source'] as String?, true),
          );
          listing = [
            // 광고(2026-10-19): 위젯에서 들어온 사람이 먼저 보는 장바구니 지수·차트 바로 다음, 장보기 시세 앞 — 내용을 가리지 않는 자연스러운 경계
            // (앱에서 ADMOB_BANNER_ID를 빌드에 줬을 때만 보임)
            const AdSlot(),
            ShoppingCatalog(
              catalog: catalogRaw.cast<Map<String, dynamic>>(),
              guide: (data['guide'] as Map<String, dynamic>?) ?? const {},
              asOf: data['as_of'] as String?,
            ),
          ];
        } else {
          // 예시 데이터(서버에 키가 없을 때): 예전 화면
          final trend = data['price_trend'] as Map<String, dynamic>;
          final nowD = DateTime.now();
          final points = [
            for (final e in (trend['series'] as List).cast<Map<String, dynamic>>())
              if (DateTime.parse(e['date'] as String).month == nowD.month)
                ChartPoint(DateTime.parse(e['date'] as String).day, (e['price'] as num).toDouble()),
          ];
          final item = trend['item'] as String;
          final latest = trend['latest'] as Map<String, dynamic>?;
          final last = latest != null ? (latest['price'] as num).toDouble() : points.last.value;
          final weekAgo = ((trend['week_ago'] as num?) ?? last).toDouble();
          final pct = (last - weekAgo) / weekAgo * 100;
          final flat = pct.abs() < 0.5;
          final emphasis = flat ? '비슷해요' : '${pct.abs().round()}% ${pct < 0 ? '내렸어요' : '올랐어요'}';
          final changeKey = flat ? 'flat' : (pct < 0 ? 'down' : 'up');
          final items = (data['items'] as List).cast<Map<String, dynamic>>();
          final season = (data['in_season'] as List).cast<Map<String, dynamic>>();
          hero = PageHero(
            section: Section.market,
            eyebrow: '생활 · ${region.label}',
            onEyebrowTap: () => showRegionPicker(shellContext),
            headline: flat ? '$item 가격은 지난주와 $emphasis' : '오늘 $item 가격, 지난주보다 $emphasis',
            emphasis: emphasis,
            source: _sourceLabel(data['source'] as String?, false),
            stub: true,
            body: [
              BigNumber(to: last, unit: trend['unit'] as String),
              const SizedBox(height: 4),
              Text(
                '${changeLabel(changeKey)} 지난주 ${formatNumber(weekAgo)}원',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: changeColor(changeKey)),
              ),
              const SizedBox(height: 14),
              TrendChart(section: Section.market, points: points),
            ],
          );
          listing = [
            ListSection(
              title: '지금 제철',
              trailing: '${DateTime.now().month}월 기준',
              stub: true,
              children: [
                for (final e in season)
                  SeasonRow(
                    section: Section.market,
                    name: e['name'] as String,
                    tip: (e['tip'] as String?) ?? '',
                    startMonth: e['start_month'] as int,
                    endMonth: e['end_month'] as int,
                  ),
                const SeasonLegend(),
              ],
            ),
            ListSection(title: '채소·과일 시세', trailing: '지난주 대비', stub: true, children: [ExpandableList(children: _priceRows(items))]),
          ];
        }

        return [
          hero,
          ...listing,
          // 2026-10-14: 예시(스텁) 구간은 광고 심사 전에 화면에서 뺌 — 실데이터가 붙으면 자동으로 나타남
          if (_isLive(data, 'essentials'))
            ListSection(title: '생필품 물가지수', trailing: '전월 대비', children: [ExpandableList(children: _priceRows(essentials))]),
          MarketList(
            api: api,
            markets: marketsNearby,
            scope: (data['markets_scope'] as String?) ?? region.label,
            total: (data['markets_total'] as num?)?.toInt() ?? marketsNearby.length,
            stub: !_isLive(data, 'markets_nearby'),
          ),
        ];
      },
    );

/// 문화: 이번 주말 행사 수 + 행사 달력(+ 음악이 실데이터일 때만 구역 전환). 나들이는 주말 탭으로 나감(2026-10-15). 영화(KOBIS) 구역은 광고 약관 때문에 뺌(2026-10-13).
Widget cultureScreen(ApiClient api, Region region, BuildContext shellContext) => SectionScreen(
      section: Section.culture,
      fetch: () => api.culture(sido: region.code, sgg: region.sgg),
      contentBuilder: (context, data) {
        final spotifyTop = (data['spotify_top'] as List).cast<Map<String, dynamic>>();
        final youtubeTrending = (data['youtube_trending'] as List).cast<Map<String, dynamic>>();

        final events = (data['events'] as List?)?.cast<Map<String, dynamic>>();
        final musicLive = _isLive(data, 'spotify_top') || _isLive(data, 'youtube_trending');
        // 맨 위는 "이번 주말 N개 행사"
        Widget weekendHero(List<Map<String, dynamic>> events, bool useLocal, [Widget? toggle]) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          // 2026-10-16: 주말만이 아니라 "이번 주"(월~일)에 열리는 행사로 — 주말은 장소 탭이 맡음
          final mon = today.subtract(Duration(days: today.weekday - 1));
          final sun = mon.add(const Duration(days: 6));
          String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          final inWeekend = events.where((e) => (e['start'] as String).compareTo(iso(sun)) <= 0 && (e['end'] as String).compareTo(iso(mon)) >= 0).toList();
          final list = inWeekend;
          final scopeName = useLocal ? region.label : region.name;
          const label = '이번 주';
          final emphasis = '${list.length}개 행사';
          return PageHero(
            section: Section.culture,
            eyebrow: '문화 · ${region.label}',
            onEyebrowTap: () => showRegionPicker(shellContext),
            headline: list.isEmpty ? '$label $scopeName에는 열리는 행사가 없어요' : '$label $scopeName에서 $emphasis가 열려요',
            emphasis: list.isEmpty ? null : emphasis,
            source: '한국관광공사 · 한국문화정보원',
            headlineLines: 2,
            topExtra: toggle,
            body: [
              BigNumber(to: list.length, unit: '개 행사'),
              const SizedBox(height: 14),
              // 범위(시군구/시도 전체)를 바꿔도 화면이 팍팍 움직이지 않게 목록 3줄 + 안내 한 줄 자리를 고정으로 잡아 둠(행사가 없으면 안내만)
              ConstrainedBox(
                constraints: BoxConstraints(minHeight: list.isEmpty ? 0 : 2 * 72 + 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in list.take(2)) eventLine(context, api, e),
                    if (list.length > 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text('외 ${list.length - 2}개', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                      ),
                  ],
                ),
              ),
            ],
          );
        }

        // 지역은 맨 위 "문화 · ○○ ▾"에서만 고름: 시군구를 골랐고 거기 행사가 있으면 그 시군구만, 아니면 시도 전체
        final hasLocal = events != null && region.sgg != null && events.any((e) => e['local'] == true);
        Widget scopedCulture([Widget? toggle]) => events == null
            ? const SizedBox.shrink()
            : Builder(builder: (context) {
                final scoped = hasLocal ? events.where((e) => e['local'] == true).toList() : events;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    weekendHero(scoped, hasLocal, toggle),
                    if (region.sgg != null && !hasLocal)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 14, 0, 0),
                        child: Text(
                          '${region.sgg}에는 등록된 행사가 없어서 ${region.name} 전체를 보여드려요.',
                          style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
                        ),
                      ),
                    CultureCalendar(api: api, events: scoped),
                  ],
                );
              });
        // 음악은 아직 예시 데이터라 실데이터가 있을 때만 `행사 / 음악` 구역 전환을 둠
        Widget musicHero(Widget toggle) => PageHero(
              section: Section.culture,
              eyebrow: '문화 · ${region.label}',
              onEyebrowTap: () => showRegionPicker(shellContext),
              headline: '요즘 많이 듣는 음악',
              emphasis: '음악',
              headlineLines: 2,
              stub: !_isLive(data, 'spotify_top'),
              topExtra: toggle,
              body: const [],
            );

        Widget reelsLinks() => const ReelsLinksSection();

        final musicSections = <Widget>[
          // 2026-09-29: 국내 3대 차트(멜론/지니/벅스)·가온(써클차트) 전부
          // 공식 오픈 API가 없어서 못 넣음(스크래핑은 이용약관 위반 소지) —
          // 공식 API가 있는 Spotify·유튜브만 근사치로 넣고, "국내 차트"가
          // 아니라는 걸 라벨에서 명확히 함(Spotify는 국내 점유율이 낮아서
          // 실제 국내 인기 순위와 차이 날 수 있음).
          ListSection(
            title: '오늘의 음악',
            trailing: 'Spotify 기준',
            stub: !_isLive(data, 'spotify_top'),
            children: [
              ExpandableList(children: [for (final it in spotifyTop) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String)]),
            ],
          ),
          ListSection(
            title: '유튜브 인기 급상승 음악',
            stub: !_isLive(data, 'youtube_trending'),
            children: [
              ExpandableList(children: [for (final it in youtubeTrending) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String)]),
            ],
          ),
          reelsLinks(),
        ];

        // 2026-10-13: 영화(KOBIS) 구역은 광고(상업 이용) 약관 때문에 뺌. 행사 정보를 아직 못 받았으면 안내만 보임(예시 카드 없음).
        if (events == null) {
          return [
            ListSection(
              title: '행사·전시',
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 56),
                  child: Center(child: Text('행사 정보를 아직 받지 못했어요. 잠시 뒤에 다시 열어 주세요', style: TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                ),
              ],
            ),
          ];
        }
        // 2026-10-15: 나들이는 별도 탭(주말)으로 나감. 음악이 실데이터가 될 때까지는 행사 화면만.
        if (!musicLive) return [scopedCulture(), const AdSlot()];
        return [
          SegmentedHost(
            labels: const ['행사', '음악'],
            prefKey: 'culture_seg',
            builder: (context, index, toggle) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: switch (index) {
                1 => [musicHero(toggle), ...musicSections],
                _ => [scopedCulture(toggle), const AdSlot()],
              },
            ),
          ),
        ];
      },
    );

/// 장소(2026-10-16; 처음엔 문화 탭의 "나들이", 10-15에 "주말" 탭으로 뺐다가 이름·구조를 바꿈): 갈 만한 곳을 구분별로.
/// 한산한 곳(주말 관광지 집중률 예측) · 도서관(열람실 빈자리) · 박물관·미술관 · 문예회관·문화센터(문화정보원 총람, 2026-10-31) · 캠핑 · 반려동물 동반 · 웰니스 · 걷기길.
/// 구역 전환(SegmentedHost)은 문화 탭의 행사/음악, 혜택 탭의 4구역과 같은 방식. 각 구역이 자기 데이터를 받음(시도·시군구 반영).
Widget placesScreen(ApiClient api, Region region, BuildContext shellContext) => SectionScreen(
      section: Section.place,
      fetch: () async => <String, dynamic>{},
      contentBuilder: (context, data) => [
        SegmentedHost(
          labels: const ['한산한 곳', '도서관', '박물관·미술관', '문예회관·문화센터', '캠핑', '반려동물', '웰니스', '걷기길'],
          prefKey: 'place_seg',
          builder: (context, index, toggle) {
            final (headline, emphasis, source) = switch (index) {
              1 => ('지금 자리 있는 도서관', '자리 있는', '지역정보개발원 공공도서관 열람실'),
              2 => ('가까운 박물관·미술관, 둘러볼까요?', '박물관·미술관', '한국문화정보원 전국문화기반시설총람'),
              3 => ('공연도 보고 배우기도 하는 문화 공간', '문화 공간', '한국문화정보원 전국문화기반시설총람'),
              4 => ('이번 주말 캠핑, 어디로 갈까요?', '캠핑', '한국관광공사 고캠핑'),
              5 => ('반려동물과 함께 갈 수 있는 곳', '함께', '한국관광공사 반려동물 동반여행'),
              6 => ('몸과 마음이 쉬어 가는 웰니스 관광지', '웰니스', '한국관광공사 웰니스관광'),
              7 => ('걷기 좋은 길, 걷기 코스', '걷기 좋은 길', '한국관광공사 두루누비'),
              _ => ('이번 주말, 한산한 곳은 어디일까요?', '한산한 곳', '한국관광공사 관광지 집중률 예측'),
            };
            const kinds = [PlaceKind.library, PlaceKind.museum, PlaceKind.hall, PlaceKind.camp, PlaceKind.pet, PlaceKind.wellness, PlaceKind.trail];
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHero(
                  section: Section.place,
                  eyebrow: '나들이 · ${region.label}',
                  onEyebrowTap: () => showRegionPicker(shellContext),
                  headline: headline,
                  emphasis: emphasis,
                  headlineLines: 2,
                  source: source,
                  topExtra: toggle,
                  // 이번 주말 날씨 한 문장 — 구분을 바꿔도 항상 같은 자리(도서관 포함)라 다시 만들어지지 않음
                  body: [WeekendWeatherLine(key: ValueKey('wk${region.code}${region.sgg}'), api: api, region: region)],
                ),
                if (index == 0)
                  OutingSection(api: api, region: region)
                else
                  PlaceFeed(key: ValueKey('place${kinds[index - 1].name}${region.code}${region.sgg}'), api: api, region: region, kind: kinds[index - 1]),
                const AdSlot(),
              ],
            );
          },
        ),
      ],
    );

/// 혜택(옛 머니 탭): 정부 지원 / 청약 / 공공임대 / 대출을 구역 전환으로. 모두 공공데이터포털 "제한 없음" 데이터.
/// 2026-10-13: 금융위 지수·상품, 금감원 금리는 광고(상업 이용) 약관 때문에 뺌 — 허락을 받으면 다시 붙일 수 있음(docs/licensing.md 참고).
Widget benefitsScreen(ApiClient api, Region region, BuildContext shellContext) => SectionScreen(
      section: Section.money,
      fetch: () async => <String, dynamic>{},
      contentBuilder: (context, data) {
        GovSupportSection.prefetch(api); // 정부 지원 구역이 바로 보이게 미리 받아 둠(같은 요청은 다시 안 보냄)
        return [
        SegmentedHost(
          labels: const ['정부 지원', '청약', '공공임대', '전월세', '지역화폐', '대출'],
          prefKey: 'benefit_seg',
          trackName: 'benefit_seg',
          builder: (context, index, toggle) {
            final (headline, emphasis, source) = switch (index) {
              1 => ('곧 접수하는 청약, 한눈에 봐요', '청약', '한국부동산원 청약홈'),
              2 => ('신청할 수 있는 공공임대 공고', '공공임대', '국토교통부 마이홈포털 · 한국토지주택공사'),
              3 => ('우리 동네 전월세, 요즘 얼마일까요', '전월세', '국토교통부 아파트·오피스텔 전월세 실거래가'),
              4 => ('우리 동네 상품권, 어디서 많이 쓸까요', '상품권', '한국조폐공사 지역사랑상품권 업종별 결제정보'),
              5 => ('내가 쓸 수 있는 서민 대출', '서민 대출', '서민금융진흥원 대출상품 한눈에'),
              _ => ('받을 수 있는 혜택, 한 번에 찾아봐요', '혜택', '행정안전부 공공서비스(혜택) 정보'),
            };
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PageHero(
                  section: Section.money,
                  eyebrow: '혜택 · ${region.label}',
                  onEyebrowTap: () => showRegionPicker(shellContext),
                  headline: headline,
                  emphasis: emphasis,
                  headlineLines: 2,
                  source: source,
                  topExtra: toggle,
                  body: const [],
                ),
                // 광고(2026-10-19): 청약·공공임대·대출은 공고 맨 위 3개를 먼저 보여 준 다음에(BenefitFeed 안), 정부 지원은 목록 맨 아래
                switch (index) {
                  1 => BenefitFeed(key: ValueKey('apply${region.code}${region.sgg}'), api: api, region: region, kind: BenefitKind.apply),
                  2 => BenefitFeed(key: ValueKey('rent${region.code}${region.sgg}'), api: api, region: region, kind: BenefitKind.rent),
                  3 => RentMarketSection(key: ValueKey('rentm${region.code}${region.sgg}'), api: api, region: region),
                  4 => LocalCurrencySection(key: ValueKey('localcur${region.code}${region.sgg}'), api: api, region: region),
                  5 => BenefitFeed(key: ValueKey('loan${region.code}'), api: api, region: region, kind: BenefitKind.loan),
                  _ => GovSupportSection(api: api),
                },
                if (index == 0) const AdSlot(),
                // 2026-10-21: 플레이 "혼동을 야기하는 주장" 검토(정부 정보의 원본 출처 링크 누락) 대응 — 구역마다 공식 사이트 링크를 눈에 보이게 둠
                OfficialSourceLinks(links: switch (index) {
                  1 => const [('청약홈', 'https://www.applyhome.co.kr'), ('공공데이터포털', 'https://www.data.go.kr')],
                  2 => const [('마이홈포털', 'https://www.myhome.go.kr'), ('LH청약플러스', 'https://apply.lh.or.kr')],
                  3 => const [('국토교통부 실거래가 공개시스템', 'https://rt.molit.go.kr'), ('공공데이터포털', 'https://www.data.go.kr')],
                  4 => const [('한국조폐공사', 'https://www.komsco.com'), ('공공데이터포털', 'https://www.data.go.kr')],
                  5 => const [('서민금융진흥원', 'https://www.kinfa.or.kr'), ('공공데이터포털', 'https://www.data.go.kr')],
                  _ => const [('정부24', 'https://www.gov.kr'), ('공공데이터포털', 'https://www.data.go.kr')],
                }),
              ],
            );
          },
        ),
        ];
      },
    );

/// AI: 이번 주 글 제목이 곧 한 문장 제목, 핵심 한 줄은 그 아래.
Widget aiScreen(ApiClient api) => SectionScreen(
      section: Section.ai,
      fetch: api.ai,
      contentBuilder: (context, data) {
        final article = data['weekly_article'] as Map<String, dynamic>;
        final papers = (data['papers'] as List).cast<Map<String, dynamic>>();
        final models = (data['new_models'] as List).cast<Map<String, dynamic>>();
        final t = sectionThemes[Section.ai]!;
        return [
          PageHero(
            section: Section.ai,
            headline: article['title'] as String,
            stub: !_isLive(data, 'weekly_article'),
            body: [
              if (article['highlight'] != null)
                HighlightText(
                  text: article['highlight'] as String,
                  emphasis: article['highlight'] as String,
                  color: t.highlight,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.6),
                ),
              if (article['meta'] != null) ...[
                const SizedBox(height: 10),
                Text(article['meta'] as String, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
              ],
            ],
          ),
          ListSection(
            title: '이번 주 인기 논문',
            stub: !_isLive(data, 'papers'),
            children: [
              ExpandableList(children: [for (final it in papers) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String)]),
            ],
          ),
          ListSection(title: '이번 달 새 모델', stub: !_isLive(data, 'new_models'), children: [ExpandableList(children: _priceRows(models))]),
        ];
      },
    );


/// 큰 구역 전환(분할 버튼)을 한 줄 위에 두고, 고른 구역의 내용을 builder가 그림. 마지막으로 고른 구역은 기기에 기억함.
class SegmentedHost extends StatefulWidget {
  const SegmentedHost({super.key, required this.labels, required this.prefKey, required this.builder, this.trackName = 'culture_kind'});

  /// 바깥(홈 화면 위젯)에서 특정 구역으로 열어 달라는 요청. 아직 안 만들어진 화면은 저장값(prefKey)으로 그 구역에서 시작하고,
  /// 이미 떠 있는 화면은 [_ticks]를 듣고 바로 바꿈.
  static void request(String prefKey, String label) {
    LocalPrefs.setString(prefKey, label);
    _pending[prefKey] = label;
    _ticks.value++;
  }

  static final Map<String, String> _pending = {};
  static final ValueNotifier<int> _ticks = ValueNotifier(0);

  final List<String> labels;
  final String prefKey;
  final String trackName; // 통계 이벤트 이름(허용 목록에 있는 것)
  final Widget Function(BuildContext context, int index, Widget toggle) builder;

  @override
  State<SegmentedHost> createState() => _SegmentedHostState();
}

class _SegmentedHostState extends State<SegmentedHost> {
  // 마지막으로 고른 구역으로 첫 프레임부터 엶(예전엔 첫 구역으로 그리고 요청까지 보낸 뒤 바꿔서 두 번 그렸음)
  late int _index = () {
    final v = LocalPrefs.stringSync(widget.prefKey);
    final i = v == null ? -1 : widget.labels.indexOf(v);
    return i >= 0 ? i : 0;
  }();

  @override
  void initState() {
    super.initState();
    SegmentedHost._ticks.addListener(_onRequest);
  }

  @override
  void dispose() {
    SegmentedHost._ticks.removeListener(_onRequest);
    super.dispose();
  }

  void _onRequest() {
    final label = SegmentedHost._pending.remove(widget.prefKey);
    final i = label == null ? -1 : widget.labels.indexOf(label);
    if (i >= 0 && mounted) _select(i);
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() => _index = i);
    LocalPrefs.setString(widget.prefKey, widget.labels[i]);
    Analytics.instance.track(widget.trackName, 'seg-${widget.labels[i]}');
  }

  // 본문에서 옆으로 밀면 이웃 구분으로. 첫 구분에서 오른쪽으로·마지막에서 왼쪽으로 밀면 이웃 탭으로 이어짐
  void _swipe(int step) {
    final next = _index + step;
    if (next < 0 || next >= widget.labels.length) {
      swipeToTab?.call(step);
    } else {
      _select(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final toggle = SegmentToggle(labels: widget.labels, index: _index, onChanged: _select);
    return SwipeDetector(onSwipe: _swipe, child: widget.builder(context, _index, toggle));
  }
}
