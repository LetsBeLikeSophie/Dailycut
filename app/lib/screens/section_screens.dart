import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';
import '../widgets/components.dart';

/// 시세/문화/머니/AI 네 섹션 화면 — 모두 "future 하나 받아서 리스트로
/// 보여주기" 구조가 같아서 하나의 뼈대 위젯으로 묶고, 섹션마다 다른 건
/// contentBuilder로만 갈아끼움.
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
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            SectionHeader(section: widget.section),
            const SizedBox(height: 16),
            ...widget.contentBuilder(context, snapshot.data!),
          ],
        );
      },
    );
  }
}

Widget _statGrid(List<Map<String, dynamic>> items) => GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.25,
      children: [
        for (final it in items)
          StatTile(label: it['label'] as String, value: it['value'] as String, change: it['change'] as String),
      ],
    );

/// 2026-09-29: "시세"를 품목 가격 순위만 보여주는 좁은 지표가 아니라
/// "장 볼 때 필요한 생활 물가" 전체로 넓히자는 피드백으로, 제철 과일·채소를
/// 캡션 한 줄에서 카드 목록으로 승격하고 축산물/생필품/전통시장을 추가함.
Widget marketScreen(ApiClient api) => SectionScreen(
      section: Section.market,
      fetch: api.market,
      contentBuilder: (context, data) {
        final hero = data['hero'] as Map<String, dynamic>;
        final items = (data['items'] as List).cast<Map<String, dynamic>>();
        final season = (data['in_season'] as List).cast<Map<String, dynamic>>();
        final livestock = (data['livestock'] as List).cast<Map<String, dynamic>>();
        final essentials = (data['essentials'] as List).cast<Map<String, dynamic>>();
        final marketsNearby = (data['markets_nearby'] as List).cast<Map<String, dynamic>>();
        return [
          HeroCard(
            section: Section.market,
            title: hero['title'] as String,
            highlight: hero['highlight'] as String?,
            meta: hero['meta'] as String?,
          ),
          const SizedBox(height: 16),
          _statGrid(items),
          const SizedBox(height: 24),
          Text('제철 과일·채소', style: AppTheme.displaySerif(size: 16)),
          for (final it in season)
            RankRow(section: Section.market, rank: 0, title: it['name'] as String, meta: it['meta'] as String),
          const SizedBox(height: 24),
          Text('축산물 시세', style: AppTheme.displaySerif(size: 16)),
          const SizedBox(height: 8),
          _statGrid(livestock),
          const SizedBox(height: 24),
          Text('생필품 물가지수', style: AppTheme.displaySerif(size: 16)),
          const SizedBox(height: 8),
          _statGrid(essentials),
          const SizedBox(height: 24),
          Text('우리 동네 전통시장', style: AppTheme.displaySerif(size: 16)),
          for (final it in marketsNearby)
            RankRow(section: Section.market, rank: 0, title: it['title'] as String, meta: it['meta'] as String),
        ];
      },
    );

Widget cultureScreen(ApiClient api) => SectionScreen(
      section: Section.culture,
      fetch: api.culture,
      contentBuilder: (context, data) {
        final boxOffice = (data['box_office'] as List).cast<Map<String, dynamic>>();
        final performances = (data['performances'] as List).cast<Map<String, dynamic>>();
        final festivals = (data['festivals'] as List).cast<Map<String, dynamic>>();
        return [
          for (final it in boxOffice)
            RankRow(section: Section.culture, rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
          const SizedBox(height: 16),
          Text('이번 주 개막 공연', style: AppTheme.displaySerif(size: 16)),
          for (final it in performances) RankRow(section: Section.culture, rank: 0, title: it['title'] as String, meta: it['meta'] as String),
          const SizedBox(height: 16),
          Text('주말 축제', style: AppTheme.displaySerif(size: 16)),
          for (final it in festivals) RankRow(section: Section.culture, rank: 0, title: it['title'] as String, meta: it['meta'] as String),
        ];
      },
    );

Widget moneyScreen(ApiClient api) => SectionScreen(
      section: Section.money,
      fetch: api.money,
      contentBuilder: (context, data) {
        final hero = data['hero'] as Map<String, dynamic>;
        final stats = (data['stats'] as List).cast<Map<String, dynamic>>();
        final deposits = (data['deposits'] as List).cast<Map<String, dynamic>>();
        return [
          HeroCard(section: Section.money, title: hero['label'] as String, meta: '${hero['value']}'),
          const SizedBox(height: 16),
          _statGrid(stats),
          const SizedBox(height: 16),
          Text('예·적금 금리 순위', style: AppTheme.displaySerif(size: 16)),
          for (final it in deposits)
            RankRow(section: Section.money, rank: it['rank'] as int, title: it['title'] as String, meta: it['meta'] as String),
        ];
      },
    );

Widget aiScreen(ApiClient api) => SectionScreen(
      section: Section.ai,
      fetch: api.ai,
      contentBuilder: (context, data) {
        final article = data['weekly_article'] as Map<String, dynamic>;
        final papers = (data['papers'] as List).cast<Map<String, dynamic>>();
        final models = (data['new_models'] as List).cast<Map<String, dynamic>>();
        return [
          HeroCard(
            section: Section.ai,
            title: article['title'] as String,
            highlight: article['highlight'] as String?,
            meta: article['meta'] as String?,
          ),
          const SizedBox(height: 16),
          Text('이번 주 인기 논문', style: AppTheme.displaySerif(size: 16)),
          for (final it in papers) RankRow(section: Section.ai, rank: 0, title: it['title'] as String, meta: it['meta'] as String),
          const SizedBox(height: 16),
          _statGrid(models),
        ];
      },
    );
