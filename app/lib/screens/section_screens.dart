import 'package:flutter/material.dart';
import '../analytics.dart';
import '../api_client.dart';
import '../local_prefs.dart';
import '../region.dart';
import '../theme.dart';
import '../widgets/basket_hero.dart';
import '../widgets/benefit_feed.dart';
import '../widgets/components.dart';
import '../widgets/ad_slot.dart';
import '../widgets/livestock_sheet.dart';
import '../widgets/reels_links.dart';
import '../widgets/culture_calendar.dart';
import '../widgets/gov_support.dart';
import '../widgets/market_list.dart';
import '../widgets/shopping_catalog.dart';

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
        final livestock = (data['livestock'] as List).cast<Map<String, dynamic>>();
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
            ShoppingCatalog(
              catalog: catalogRaw.cast<Map<String, dynamic>>(),
              guide: (data['guide'] as Map<String, dynamic>?) ?? const {},
              asOf: data['as_of'] as String?,
            ),
            const AdSlot(), // 광고(ADFIT_UNIT을 빌드에 줬을 때만 보임)
            // 축산물(소·돼지 부위별 소비자가격, 평년 대비) — 키가 있고 수집이 되면 보임
            if (_isLive(data, 'livestock'))
              ListSection(
                title: '축산물 시세',
                trailing: data['livestock_date'] == null
                    ? '평년 대비'
                    : '${DateTime.parse(data['livestock_date'] as String).month}/${DateTime.parse(data['livestock_date'] as String).day} 기준 · 지난주 대비',
                children: [
                  ExpandableList(
                    children: [for (final it in (data['livestock'] as List).cast<Map<String, dynamic>>()) livestockLine(context, it)],
                  ),
                ],
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
          // 실데이터(소·돼지)는 위 listing 안의 "축산물 시세"가 보여주므로, 예시 구간은 실데이터가 없을 때만
          if (!_isLive(data, 'livestock'))
            ListSection(title: '축산물 시세(계란·돼지고기)', trailing: '지난주 대비', stub: true, children: [ExpandableList(children: _priceRows(livestock))]),
          ListSection(title: '생필품 물가지수', trailing: '전월 대비', stub: !_isLive(data, 'essentials'), children: [ExpandableList(children: _priceRows(essentials))]),
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

/// 문화: 이번 주말 행사 수 + 행사 달력 / 음악(예시). 영화(KOBIS) 구역은 광고 약관 때문에 뺌(2026-10-13).
Widget cultureScreen(ApiClient api, Region region, BuildContext shellContext) => SectionScreen(
      section: Section.culture,
      fetch: () => api.culture(sido: region.code, sgg: region.sgg),
      contentBuilder: (context, data) {
        final spotifyTop = (data['spotify_top'] as List).cast<Map<String, dynamic>>();
        final youtubeTrending = (data['youtube_trending'] as List).cast<Map<String, dynamic>>();

        final events = (data['events'] as List?)?.cast<Map<String, dynamic>>();
        // 맨 위는 "이번 주말 N개 행사"
        Widget weekendHero(List<Map<String, dynamic>> events, bool useLocal, [Widget? toggle]) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final sat = today.weekday == DateTime.sunday ? today : today.add(Duration(days: (DateTime.saturday - today.weekday) % 7));
          final sun = today.weekday == DateTime.sunday ? today : sat.add(const Duration(days: 1));
          String iso(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
          final inWeekend = events.where((e) => (e['start'] as String).compareTo(iso(sun)) <= 0 && (e['end'] as String).compareTo(iso(sat)) >= 0).toList();
          final list = inWeekend;
          final scopeName = useLocal ? region.label : region.name;
          final label = today.weekday == DateTime.sunday ? '오늘' : '이번 주말(${sat.month}/${sat.day}~${sun.day})';
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
        // 문화 탭이 길어져서 큰 구역을 전환으로 나눔: 행사·전시 / 음악(예시)
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
        return [
          SegmentedHost(
            labels: const ['행사·전시', '음악'],
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

/// 혜택(옛 머니 탭): 정부 지원 / 청약 / 공공임대 / 대출을 구역 전환으로. 모두 공공데이터포털 "제한 없음" 데이터.
/// 2026-10-13: 금융위 지수·상품, 금감원 금리는 광고(상업 이용) 약관 때문에 뺌 — 허락을 받으면 다시 붙일 수 있음(CLAUDE.md 참고).
Widget benefitsScreen(ApiClient api, Region region, BuildContext shellContext) => SectionScreen(
      section: Section.money,
      fetch: () async => <String, dynamic>{},
      contentBuilder: (context, data) {
        GovSupportSection.prefetch(api); // 정부 지원 구역이 바로 보이게 미리 받아 둠(같은 요청은 다시 안 보냄)
        return [
        SegmentedHost(
          labels: const ['정부 지원', '청약', '공공임대', '대출'],
          prefKey: 'benefit_seg',
          trackName: 'benefit_seg',
          builder: (context, index, toggle) {
            final (headline, emphasis, source) = switch (index) {
              1 => ('곧 접수하는 청약, 한눈에 봐요', '청약', '한국부동산원 청약홈'),
              2 => ('신청할 수 있는 공공임대 공고', '공공임대', '국토교통부 마이홈포털 · 한국토지주택공사'),
              3 => ('내가 쓸 수 있는 서민 대출', '서민 대출', '서민금융진흥원 대출상품 한눈에'),
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
                switch (index) {
                  1 => BenefitFeed(key: ValueKey('apply${region.code}${region.sgg}'), api: api, region: region, kind: BenefitKind.apply),
                  2 => BenefitFeed(key: ValueKey('rent${region.code}${region.sgg}'), api: api, region: region, kind: BenefitKind.rent),
                  3 => BenefitFeed(key: ValueKey('loan${region.code}'), api: api, region: region, kind: BenefitKind.loan),
                  _ => GovSupportSection(api: api),
                },
                const AdSlot(),
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

  final List<String> labels;
  final String prefKey;
  final String trackName; // 통계 이벤트 이름(허용 목록에 있는 것)
  final Widget Function(BuildContext context, int index, Widget toggle) builder;

  @override
  State<SegmentedHost> createState() => _SegmentedHostState();
}

class _SegmentedHostState extends State<SegmentedHost> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    LocalPrefs.getString(widget.prefKey).then((v) {
      final i = v == null ? -1 : widget.labels.indexOf(v);
      if (i >= 0 && mounted) setState(() => _index = i);
    });
  }

  @override
  Widget build(BuildContext context) {
    final toggle = SegmentToggle(
      labels: widget.labels,
      index: _index,
      onChanged: (i) {
        setState(() => _index = i);
        LocalPrefs.setString(widget.prefKey, widget.labels[i]);
        Analytics.instance.track(widget.trackName, 'seg-${widget.labels[i]}');
      },
    );
    return widget.builder(context, _index, toggle);
  }
}
