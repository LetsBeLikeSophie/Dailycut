import 'package:flutter/material.dart';
import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import '../widgets/components.dart';

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
List<Widget> _rankSections(Map<String, dynamic> data, List<(String, String, String)> specs) {
  return [
    for (final (key, title, trailing) in specs)
      if (data[key] is List && (data[key] as List).isNotEmpty)
        ListSection(
          title: title,
          trailing: trailing,
          stub: !_isLive(data, key),
          children: [
            for (final it in (data[key] as List).cast<Map<String, dynamic>>())
              RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
          ],
        ),
  ];
}

List<Widget> _priceRows(List<Map<String, dynamic>> items) => [for (final it in items) priceRow(it)];

/// 생활: 대표 가격(배추) 한 문장 + 큰 숫자 + 추이, 그 아래 제철 · 시세 목록.
Widget marketScreen(ApiClient api, Region region, BuildContext shellContext) => SectionScreen(
      section: Section.market,
      fetch: () => api.market(sido: region.code, sgg: region.sgg),
      contentBuilder: (context, data) {
        final trend = data['price_trend'] as Map<String, dynamic>;
        final rawPoints = (trend['series'] as List).cast<Map<String, dynamic>>();
        // 이번 달 1일~오늘 일별 값(차트 X축은 월 전체 고정)
        final nowD = DateTime.now();
        // 이번 달 데이터만 차트에 올림(X축이 이번 달 1일~말일 고정이라서)
        final points = [
          for (final e in rawPoints)
            if (DateTime.parse(e['date'] as String).month == nowD.month)
              ChartPoint(DateTime.parse(e['date'] as String).day, (e['price'] as num).toDouble()),
        ];
        final item = trend['item'] as String;
        final latest = trend['latest'] as Map<String, dynamic>?;
        final last = latest != null ? (latest['price'] as num).toDouble() : points.last.value;
        // 지난주(7일 전) 대비 — 월초에는 지난달 값이 필요해서 서버가 따로 줌
        final weekAgo = ((trend['week_ago'] as num?) ?? last).toDouble();
        final pct = (last - weekAgo) / weekAgo * 100;
        final flat = pct.abs() < 0.5;
        final emphasis = flat ? '비슷해요' : '${pct.abs().round()}% ${pct < 0 ? '내렸어요' : '올랐어요'}';
        final headline = flat ? '$item 가격은 지난주와 $emphasis' : '오늘 $item 가격, 지난주보다 $emphasis';
        final changeKey = flat ? 'flat' : (pct < 0 ? 'down' : 'up');

        final items = (data['items'] as List).cast<Map<String, dynamic>>();
        final season = (data['in_season'] as List).cast<Map<String, dynamic>>();
        final livestock = (data['livestock'] as List).cast<Map<String, dynamic>>();
        final essentials = (data['essentials'] as List).cast<Map<String, dynamic>>();
        final marketsNearby = (data['markets_nearby'] as List).cast<Map<String, dynamic>>();
        return [
          PageHero(
            section: Section.market,
            eyebrow: '생활 · ${region.label}',
            onEyebrowTap: () => showRegionPicker(shellContext),
            headline: headline,
            emphasis: emphasis,
            source: _sourceLabel(data['source'] as String?, _isLive(data, 'price_trend')),
            stub: !_isLive(data, 'price_trend'),
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
          ),
          ListSection(
            title: '지금 제철',
            trailing: '${DateTime.now().month}월 기준',
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
          ListSection(title: '채소·과일 시세', trailing: '전주 대비', stub: !_isLive(data, 'items'), children: _priceRows(items)),
          ListSection(title: '축산물 시세', trailing: '전주 대비', stub: !_isLive(data, 'livestock'), children: _priceRows(livestock)),
          ListSection(title: '생필품 물가지수', trailing: '전월 대비', stub: !_isLive(data, 'essentials'), children: _priceRows(essentials)),
          ListSection(
            title: '${data['markets_scope'] ?? region.label} 전통시장',
            trailing: _isLive(data, 'markets_nearby') ? '총 ${data['markets_total']}곳 · 시설 많은 순' : null,
            stub: !_isLive(data, 'markets_nearby'),
            children: [
              for (final it in marketsNearby.take(6)) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String),
            ],
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
        return [
          PageHero(
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
          ),
          ListSection(
            title: '박스오피스',
            trailing: '어제 기준',
            stub: !_isLive(data, 'box_office'),
            children: [
              for (final it in rest) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
            ],
          ),
          ListSection(
            title: '진행 중인 전시·공연',
            trailing: _isLive(data, 'performances') ? nearbyFor('performances') : null,
            stub: !_isLive(data, 'performances'),
            children: [for (final it in performances) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String)],
          ),
          ListSection(
            title: '곧 열리는 축제',
            trailing: _isLive(data, 'festivals') ? nearbyFor('festivals') : null,
            stub: !_isLive(data, 'festivals'),
            children: [for (final it in festivals) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String)],
          ),
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
              for (final it in spotifyTop) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
            ],
          ),
          ListSection(
            title: '유튜브 인기 급상승 음악',
            stub: !_isLive(data, 'youtube_trending'),
            children: [
              for (final it in youtubeTrending) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
            ],
          ),
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
              children: _priceRows(stats),
            ),
          ..._rankSections(data, const [
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
              for (final it in papers) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String),
            ],
          ),
          ListSection(title: '이번 달 새 모델', stub: !_isLive(data, 'new_models'), children: _priceRows(models)),
        ];
      },
    );
