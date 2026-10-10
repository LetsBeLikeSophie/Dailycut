import 'package:flutter/material.dart';
import '../api_client.dart';
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

List<Widget> _priceRows(List<Map<String, dynamic>> items) => [for (final it in items) priceRow(it)];

/// 생활: 대표 가격(배추) 한 문장 + 큰 숫자 + 추이, 그 아래 제철 · 시세 목록.
Widget marketScreen(ApiClient api) => SectionScreen(
      section: Section.market,
      fetch: api.market,
      contentBuilder: (context, data) {
        final trend = data['price_trend'] as Map<String, dynamic>;
        final points = (trend['series'] as List).cast<Map<String, dynamic>>();
        final series = points.map((e) => (e['price'] as num).toDouble()).toList();
        final item = trend['item'] as String;
        final last = series.last;
        // 지난주(7일 전) 대비
        final weekAgo = series.length > 7 ? series[series.length - 8] : series.first;
        final pct = (last - weekAgo) / weekAgo * 100;
        final flat = pct.abs() < 0.5;
        final emphasis = flat ? '비슷해요' : '${pct.abs().round()}% ${pct < 0 ? '내렸어요' : '올랐어요'}';
        final headline = flat ? '$item 가격은 지난주와 $emphasis' : '오늘 $item 가격, 지난주보다 $emphasis';
        final firstDate = DateTime.tryParse(points.first['date'] as String);
        final changeKey = flat ? 'flat' : (pct < 0 ? 'down' : 'up');

        final items = (data['items'] as List).cast<Map<String, dynamic>>();
        final season = (data['in_season'] as List).cast<Map<String, dynamic>>();
        final livestock = (data['livestock'] as List).cast<Map<String, dynamic>>();
        final essentials = (data['essentials'] as List).cast<Map<String, dynamic>>();
        final marketsNearby = (data['markets_nearby'] as List).cast<Map<String, dynamic>>();
        return [
          PageHero(
            section: Section.market,
            headline: headline,
            emphasis: emphasis,
            source: data['source'] as String?,
            body: [
              BigNumber(to: last, unit: trend['unit'] as String),
              const SizedBox(height: 4),
              Text(
                '${changeLabel(changeKey)} 지난주 ${formatNumber(weekAgo)}원',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: changeColor(changeKey)),
              ),
              const SizedBox(height: 14),
              TrendChart(
                section: Section.market,
                series: series,
                leftLabel: firstDate == null ? null : '${firstDate.month}월 ${firstDate.day}일',
              ),
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
          ListSection(title: '채소 시세', trailing: '전주 대비', children: _priceRows(items)),
          ListSection(title: '축산물 시세', trailing: '전주 대비', children: _priceRows(livestock)),
          ListSection(title: '생필품 물가지수', trailing: '전월 대비', children: _priceRows(essentials)),
          ListSection(
            title: '우리 동네 전통시장',
            children: [
              for (final it in marketsNearby) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String),
            ],
          ),
        ];
      },
    );

/// 문화: 어제 박스오피스 1위를 한 문장 + 큰 관객 수로, 눌러 뒤집으면 TOP 3.
Widget cultureScreen(ApiClient api) => SectionScreen(
      section: Section.culture,
      fetch: api.culture,
      contentBuilder: (context, data) {
        final hero = data['hero'] as Map<String, dynamic>;
        final allBoxOffice = (data['box_office'] as List).cast<Map<String, dynamic>>();
        final rest = allBoxOffice.where((it) => it['rank'] != 1).toList();
        final performances = (data['performances'] as List).cast<Map<String, dynamic>>();
        final festivals = (data['festivals'] as List).cast<Map<String, dynamic>>();
        final spotifyTop = (data['spotify_top'] as List).cast<Map<String, dynamic>>();
        final youtubeTrending = (data['youtube_trending'] as List).cast<Map<String, dynamic>>();

        final title = '‘${hero['title']}’';
        // "182만 명" → 숫자 182 + 단위 "만 명"
        final stat = hero['stat'] as String;
        final m = RegExp(r'^([\d,\.]+)\s*(.*)$').firstMatch(stat);
        final poster = hero['poster'] as String?;
        return [
          PageHero(
            section: Section.culture,
            headline: '${hero['label'] ?? '어제 박스오피스 1위'}는 $title',
            emphasis: title,
            source: hero['source'] as String?,
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
            children: [
              for (final it in rest) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
            ],
          ),
          ListSection(
            title: '이번 주 개막 공연',
            children: [for (final it in performances) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String)],
          ),
          ListSection(
            title: '주말 축제',
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
            children: [
              for (final it in spotifyTop) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
            ],
          ),
          ListSection(
            title: '유튜브 인기 급상승 음악',
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
        final stats = (data['stats'] as List).cast<Map<String, dynamic>>();
        final deposits = (data['deposits'] as List).cast<Map<String, dynamic>>();
        final fxOthers = (data['fx_others'] as List? ?? const []).cast<Map<String, dynamic>>();
        final series = (hero['series'] as List).map((e) => (e as num).toDouble()).toList();
        final change = hero['change'] as String;
        final emphasis = switch (change) { 'up' => '올랐어요', 'down' => '내렸어요', _ => '그대로예요' };
        final diff = series.last - series.first;
        return [
          PageHero(
            section: Section.money,
            headline: '${hero['label']}, 오늘은 $emphasis',
            emphasis: emphasis,
            source: hero['source'] as String?,
            backTitle: '주요 통화 환율',
            backHint: fxOthers.isEmpty ? null : '눌러서 다른 통화 보기',
            back: fxOthers.isEmpty
                ? null
                : Column(
                    children: [
                      for (final it in fxOthers) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String),
                    ],
                  ),
            body: [
              BigNumber(to: hero['value'] as num, decimals: 1, unit: '원'),
              const SizedBox(height: 4),
              Text(
                '${changeLabel(change)} 최근 ${series.length}일 ${diff >= 0 ? '+' : '-'}${formatNumber(diff.abs(), decimals: 1)}원',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: changeColor(change)),
              ),
              const SizedBox(height: 14),
              TrendChart(section: Section.money, series: series, leftLabel: '${series.length}일 전'),
            ],
          ),
          ListSection(title: '기준 지표', children: _priceRows(stats)),
          ListSection(
            title: '예·적금 금리 순위',
            children: [
              for (final it in deposits) RankRow(rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
            ],
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
            children: [
              for (final it in papers) RankRow(rank: 0, title: it['title'] as String, meta: it['meta'] as String),
            ],
          ),
          ListSection(title: '이번 달 새 모델', children: _priceRows(models)),
        ];
      },
    );
