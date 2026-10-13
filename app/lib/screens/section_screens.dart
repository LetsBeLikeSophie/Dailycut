import 'package:flutter/material.dart';
import '../analytics.dart';
import '../api_client.dart';
import '../local_prefs.dart';
import '../region.dart';
import '../theme.dart';
import '../widgets/basket_hero.dart';
import '../widgets/metric_chart.dart';
import '../widgets/components.dart';
import '../widgets/ad_slot.dart';
import '../widgets/box_office.dart';
import '../widgets/livestock_sheet.dart';
import '../widgets/reels_links.dart';
import '../widgets/culture_calendar.dart';
import '../widgets/finance_sheet.dart';
import '../widgets/gov_support.dart';
import '../widgets/market_list.dart';
import '../widgets/shopping_catalog.dart';

/// 생활/문화/머니/AI 네 섹션 화면 — 모두 "future 하나 받아서 위에서
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

/// {rank, title, meta} 목록이 들어 있는 키들을 순서대로 구간으로 만듦(없는 키는 건너뜀).
/// 금융감독원 금융상품 한눈에(예·적금·대출)처럼 같은 모양의 순위 목록 여러 개에 씀.
List<Widget> _rankSections(BuildContext context, Map<String, dynamic> data, List<(String, String, String)> specs) {
  return [
    for (final (key, title, trailing) in specs)
      if (data[key] is List && (data[key] as List).isNotEmpty)
        ListSection(
          title: title,
          trailing: trailing,
          stub: !_isLive(data, key),
          children: [
            ExpandableList(
              children: [for (final it in (data[key] as List).cast<Map<String, dynamic>>()) financeLine(context, it)],
            ),
          ],
        ),
  ];
}

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

/// 문화: 어제 박스오피스 1위를 한 문장 + 큰 관객 수로, 눌러 뒤집으면 TOP 3.
Widget cultureScreen(ApiClient api, Region region, BuildContext shellContext) => SectionScreen(
      section: Section.culture,
      fetch: () => api.culture(sido: region.code, sgg: region.sgg),
      contentBuilder: (context, data) {
        final hero = data['hero'] as Map<String, dynamic>;
        final allBoxOffice = (data['box_office'] as List).cast<Map<String, dynamic>>();
        final rest = allBoxOffice.where((it) => it['rank'] != 1).toList();
        final performances = (data['performances'] as List).cast<Map<String, dynamic>>();
        final festivals = (data['festivals'] as List).cast<Map<String, dynamic>>();
        final spotifyTop = (data['spotify_top'] as List).cast<Map<String, dynamic>>();
        final youtubeTrending = (data['youtube_trending'] as List).cast<Map<String, dynamic>>();

        final scope = data['culture_scope'] as Map<String, dynamic>?;
        String nearbyFor(String key) {
          final n = scope?[key] as Map<String, dynamic>?;
          if (scope == null || n == null) return '${region.label} 기준';
          if (scope['sgg'] == null) return '${scope['sido']} 전체';
          final local = n['local'] as int;
          return local == 0 ? '${scope['sgg']}엔 없어서 ${scope['sido']} 전체' : '${scope['sgg']} $local곳 · 나머지는 ${scope['sido']}';
        }
        final title = '‘${hero['title']}’';
        // "182만 명" → 숫자 182 + 단위 "만 명"
        final stat = hero['stat'] as String;
        final m = RegExp(r'^([\d,\.]+)\s*(.*)$').firstMatch(stat);
        final poster = hero['poster'] as String?;
        final Widget legacyHero = PageHero(
            section: Section.culture,
            eyebrow: '문화 · ${region.label}',
            onEyebrowTap: () => showRegionPicker(shellContext),
            headline: '${hero['label'] ?? '어제 박스오피스 1위'}는 $title',
            emphasis: title,
            source: _sourceLabel(hero['source'] as String?, _isLive(data, 'hero')),
            stub: !_isLive(data, 'hero'),
            backTitle: '박스오피스 TOP 3',
            backHint: '눌러서 TOP 3 보기',
            back: Column(
              children: [
                for (final it in allBoxOffice.take(3))
                  RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
              ],
            ),
            body: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (poster != null) ...[
                    ClipRect(child: Image.network(poster, width: 64, height: 96, fit: BoxFit.cover)),
                    const SizedBox(width: 16),
                  ],
                  Expanded(
                    child: m == null
                        ? Text(stat, style: AppTheme.displaySerif(size: 24))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BigNumber(
                                to: num.parse(m.group(1)!.replaceAll(',', '')),
                                unit: m.group(2)!.isEmpty ? null : m.group(2),
                              ),
                              const SizedBox(height: 4),
                              Text('${hero['stat_label']}', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          );
        final events = (data['events'] as List?)?.cast<Map<String, dynamic>>();
        Map<String, dynamic> eventFor(Map<String, dynamic> it) =>
            events?.firstWhere((e) => e['id'] == it['id'], orElse: () => const {}) ??
            {'id': it['id'], 'kind': '행사', 'title': it['title'], 'start': '', 'end': '', 'place': it['meta'], 'local': it['local']};
        Widget listLine(Map<String, dynamic> it) {
          final full = eventFor(it);
          final e = full.isEmpty ? {'id': it['id'], 'kind': '행사', 'title': it['title'], 'start': '', 'end': '', 'place': it['meta'], 'local': it['local']} : full;
          return ListLine(
            name: it['title'] as String,
            badge: it['local'] == true ? '우리 동네' : null,
            sub: it['meta'] as String,
            onTap: it['id'] == null ? null : () => showEventSheet(context, api, e),
          );
        }

        // 행사 달력이 실데이터로 들어오면 맨 위는 "이번 주말 N개 행사"(박스오피스는 KOBIS 키 전까지 예시라 아래로)
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
        // 문화 탭이 길어져서 큰 구역을 전환으로 나눔: 행사·전시 / 영화 / 음악(예시)
        Widget movieHero(Widget toggle) {
          final stat = hero['stat'] as String;
          final sm = RegExp(r'^([\d,\.]+)\s*(.*)$').firstMatch(stat);
          final title = '‘${hero['title']}’';
          return PageHero(
            section: Section.culture,
            eyebrow: '문화 · ${region.label}',
            onEyebrowTap: () => showRegionPicker(shellContext),
            headline: '${hero['label'] ?? '어제 박스오피스 1위'}는 $title',
            emphasis: title,
            headlineLines: 2,
            source: _sourceLabel(hero['source'] as String?, _isLive(data, 'hero')),
            topExtra: toggle,
            body: [
              if (sm != null)
                BigNumber(to: num.parse(sm.group(1)!.replaceAll(',', '')), unit: sm.group(2)!.isEmpty ? null : sm.group(2))
              else
                Text(stat, style: AppTheme.displaySerif(size: 24)),
              const SizedBox(height: 4),
              Text('${hero['stat_label']}', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            ],
          );
        }

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

        if (events != null && data['box_office_sets'] != null) {
          return [
            SegmentedHost(
              labels: const ['행사·전시', '영화', '음악'],
              prefKey: 'culture_seg',
              builder: (context, index, toggle) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: switch (index) {
                  1 => [
                      LicenseFlag(
                        label: 'KOBIS 약관 - 결과 저장·복제 금지(제6조), 승낙 없는 제3자 제공 금지(제8조)',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [movieHero(toggle), BoxOfficeSection(api: api, data: data, stub: !_isLive(data, 'box_office'))],
                        ),
                      ),
                      const AdSlot(),
                    ],
                  2 => [musicHero(toggle), ...musicSections],
                  _ => [scopedCulture(toggle), const AdSlot()],
                },
              ),
            ),
          ];
        }
        return [
          events == null ? legacyHero : scopedCulture(),
          if (data['box_office_sets'] != null)
            BoxOfficeSection(api: api, data: data, stub: !_isLive(data, 'box_office'))
          else
            ListSection(
              title: '박스오피스',
              trailing: '어제 기준',
              stub: !_isLive(data, 'box_office'),
              children: [ExpandableList(children: [for (final it in (events != null ? allBoxOffice : rest)) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String)])],
            ),
          if (events == null) ...[
            ListSection(
              title: '진행 중인 전시·공연',
              trailing: _isLive(data, 'performances') ? nearbyFor('performances') : null,
              stub: !_isLive(data, 'performances'),
              children: [ExpandableList(children: [for (final it in performances) listLine(it)])],
            ),
            ListSection(
              title: '곧 열리는 축제',
              trailing: _isLive(data, 'festivals') ? nearbyFor('festivals') : null,
              stub: !_isLive(data, 'festivals'),
              children: [ExpandableList(children: [for (final it in festivals) listLine(it)])],
            ),
          ],
          ...musicSections,
        ];
      },
    );

/// 머니: 환율 한 문장 + 큰 숫자 + 추이, 눌러 뒤집으면 다른 통화.
Widget moneyScreen(ApiClient api) => SectionScreen(
      section: Section.money,
      fetch: api.money,
      contentBuilder: (context, data) {
        final hero = data['hero'] as Map<String, dynamic>;
        final heroLive = _isLive(data, 'hero');
        final stats = (data['stats'] as List).cast<Map<String, dynamic>>();
        // 뒤집으면 보이는 면: 실데이터면 서버가 준 back, 아니면 스텁의 다른 통화
        final backRows = ((data['back'] ?? data['fx_others']) as List? ?? const []).cast<Map<String, dynamic>>();
        final chartItems = ((data['chart_items'] as List?) ?? const []).cast<Map<String, dynamic>>();
        if (heroLive && chartItems.isNotEmpty) {
          // 실데이터: 뒤집는 카드 대신 칩(코스피·코스닥·금·물가)으로 차트를 고름
          final chartLabels = {for (final c in chartItems) c['label']};
          final others = [for (final s in stats) if (!chartLabels.contains(s['label']) && s['label'] != '소비자물가') s];
          GovSupportSection.prefetch(api); // 혜택 구역을 눌렀을 때 바로 보이게 미리 받아 둠(같은 요청은 다시 안 보냄)
          return [
            LicenseFlag(
              label: '금융위 4유형(상업이용·제3자 제공 금지): 코스피·코스닥·금 (물가는 KOSIS라 가능)',
              child: MetricHero(items: chartItems, source: _sourceLabel(hero['source'] as String?, heroLive)),
            ),
            if (others.isNotEmpty)
              LicenseFlag(
                label: '금융위 일반상품시세(4유형) - 기름값',
                child: ListSection(title: '기름값', trailing: '리터당', stub: !_isLive(data, 'stats'), children: _priceRows(others)),
              ),
            // 2026-10-12: 문화 탭처럼 아래쪽을 "금리·대출 / 정부 혜택" 두 구역으로 나눠 한 번에 하나만 보임
            SegmentedHost(
              labels: const ['금리·대출', '정부 혜택'],
              prefKey: 'money_seg',
              trackName: 'money_metric',
              builder: (context, index, toggle) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(padding: const EdgeInsets.only(top: 36), child: toggle),
                  if (index == 0)
                    LicenseFlag(
                      level: LicenseLevel.check,
                      label: '금감원 금융상품한눈에 - 수익(광고) 시 사전 협의·허락 필요, 출처 금감원 명시',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _rankSections(context, data, const [
                          ('deposits', '정기예금 최고금리', '12개월 · 우대 포함'),
                          ('savings', '적금 최고금리', '12개월 · 우대 포함'),
                          ('loans_mortgage', '주택담보대출 최저금리', '낮은 순'),
                          ('loans_rent', '전세자금대출 최저금리', '낮은 순'),
                          ('loans_credit', '신용대출 금리', '신용등급 평균 · 낮은 순'),
                        ]),
                      ),
                    )
                  else
                    GovSupportSection(api: api), // 키 승인 전·수집 전에는 스스로 숨음
                  const AdSlot(),
                ],
              ),
            ),
          ];
        }
        final points = [
          for (final e in (hero['series'] as List).cast<Map<String, dynamic>>())
            ChartPoint(DateTime.parse(e['date'] as String).day, (e['value'] as num).toDouble()),
        ];
        final change = hero['change'] as String;
        final emphasis = switch (change) { 'up' => '올랐어요', 'down' => '내렸어요', _ => '그대로예요' };
        final diff = points.last.value - points.first.value;
        final diffKey = diff.abs() < 1e-9 ? 'flat' : (diff > 0 ? 'up' : 'down');
        final unit = (hero['unit'] as String?) ?? '원';
        final when = heroLive ? '마지막 거래일엔' : '오늘은';
        return [
          PageHero(
            section: Section.money,
            headline: '${hero['label']}, $when $emphasis',
            emphasis: emphasis,
            source: _sourceLabel(hero['source'] as String?, heroLive),
            stub: !heroLive,
            backTitle: (data['back_title'] as String?) ?? '주요 통화 환율',
            backHint: backRows.isEmpty ? null : '눌러서 다른 지표 보기',
            back: backRows.isEmpty
                ? null
                : Column(
                    children: [
                      for (final it in backRows) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String),
                    ],
                  ),
            body: [
              BigNumber(to: hero['value'] as num, decimals: 1, unit: unit),
              const SizedBox(height: 4),
              Text(
                points.length < 2
                    ? '이번 달 첫 기록이에요'
                    : '${changeLabel(diffKey)} 이번 달 ${diff >= 0 ? '+' : '-'}${formatNumber(diff.abs(), decimals: 1)}$unit',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: changeColor(diffKey)),
              ),
              const SizedBox(height: 14),
              TrendChart(section: Section.money, points: points),
            ],
          ),
          // 실데이터면 시장 지표는 위 카드를 뒤집으면 보임(여기서 반복하지 않음). 예시 데이터일 때만 목록으로.
          if (!heroLive || backRows.isEmpty)
            ListSection(
              title: '기준 지표',
              stub: !_isLive(data, 'stats'),
              children: [ExpandableList(children: _priceRows(stats))],
            ),
          ..._rankSections(context, data, const [
            ('deposits', '정기예금 최고금리', '12개월 · 우대 포함'),
            ('savings', '적금 최고금리', '12개월 · 우대 포함'),
            ('loans_mortgage', '주택담보대출 최저금리', '낮은 순'),
            ('loans_rent', '전세자금대출 최저금리', '낮은 순'),
            ('loans_credit', '신용대출 금리', '신용등급 평균 · 낮은 순'),
          ]),
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
