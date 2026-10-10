import 'package:flutter/material.dart';
import '../api_client.dart';
import '../theme.dart';
import '../widgets/components.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.api});

  final ApiClient api;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  late Future<({Map<String, dynamic> today, Map<String, dynamic> weather})> _future;

  @override
  void initState() {
    super.initState();
    // 날씨는 전용 탭이 없고 투데이 맨 위에만 있어서, today()의 요약
    // 필드 말고 weather()의 전체 데이터(시간대별·주간·지수)를 같이 받아옴.
    _future = () async {
      final results = await Future.wait([widget.api.today(), widget.api.weather()]);
      return (today: results[0], weather: results[1]);
    }();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('불러오지 못했어요\n${snapshot.error}', textAlign: TextAlign.center));
        }
        final data = snapshot.data!.today;
        final weather = snapshot.data!.weather;
        final t = sectionThemes[Section.weather]!;
        final others = (data['cards'] as List).cast<Map<String, dynamic>>().where((c) => c['section'] != 'weather').toList();

        final today = weather['today'] as Map<String, dynamic>;
        final hourly = (weather['hourly'] as List).cast<Map<String, dynamic>>();
        final weekly = (weather['weekly'] as List).cast<Map<String, dynamic>>();
        final goodFor = (weather['good_for'] as List).cast<Map<String, dynamic>>();
        final air = weather['air_quality'] as Map<String, dynamic>;
        final weatherLive = (weather['live_keys'] as List?)?.contains('today') ?? false;
        final holiday = weather['next_holiday'] as Map<String, dynamic>?;
        final weekend = (weather['weekend'] as String?) ?? '';

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            PageHero(
              section: Section.weather,
              eyebrow: '오늘',
              headline: data['headline'] as String,
              source: weatherLive ? weather['source'] as String? : '${weather['source']} · 예시 데이터',
              body: [
                BigNumber(to: today['temp'] as num, suffix: '°', unit: today['condition'] as String),
                const SizedBox(height: 4),
                Text(
                  '체감 ${today['feels_like']}° · 최고 ${today['high']}° · 최저 ${today['low']}°',
                  style: const TextStyle(fontSize: 13, color: AppColors.inkSoft),
                ),
                const SizedBox(height: 18),
                // 시간대별 가로 스크롤.
                SizedBox(
                  height: 76,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: hourly.length,
                    separatorBuilder: (context, i) => const SizedBox(width: 20),
                    itemBuilder: (context, i) {
                      final h = hourly[i];
                      final pop = h['pop'] as int;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(h['time'] as String, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                          const SizedBox(height: 6),
                          Text(
                            '${h['temp']}°',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pop > 0 ? '$pop%' : '',
                            style: const TextStyle(fontSize: 11, color: AppColors.down),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                HighlightText(
                  text: weather['outfit'] as String,
                  emphasis: weather['outfit'] as String,
                  color: t.highlight,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.6),
                ),
                if (weekend.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    weekend,
                    style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5),
                  ),
                ],
              ],
            ),
            ListSection(
              title: '이번 주 날씨',
              stub: !weatherLive,
              children: [
                for (final w in weekly)
                  ListLine(
                    leading: SizedBox(
                      width: 20,
                      child: Text(w['day'] as String, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    ),
                    name: w['condition'] as String,
                    sub: w['date'] as String,
                    middle: (w['pop'] as int) > 0
                        ? Text('${w['pop']}%', style: const TextStyle(fontSize: 13, color: AppColors.down))
                        : null,
                    value: '${w['low']}° / ${w['high']}°',
                  ),
              ],
            ),
            ListSection(
              title: '오늘의 생활 지수',
              stub: !weatherLive,
              children: [
                if (holiday != null)
                  RankRow(rank: 0, title: '다음 공휴일', meta: 'D-${holiday['d_day']} ${holiday['name']}'),
                for (final g in goodFor)
                  RankRow(
                    rank: 0,
                    title: g['label'] as String,
                    meta: g['good'] == true ? '하기 좋아요' : '별로예요',
                  ),
                RankRow(rank: 0, title: '미세먼지', meta: '${air['pm10']}'),
                RankRow(rank: 0, title: '초미세먼지', meta: '${air['pm25']}'),
              ],
            ),
            ListSection(
              title: '오늘의 섹션',
              children: [
                for (final c in others)
                  ListLine(
                    name: (c['title'] ?? c['label'] ?? '') as String,
                    sub: sectionThemes[Section.values.byName(c['section'] as String)]!.label,
                    value: (c['highlight'] ?? c['meta'] ?? c['value'] ?? '').toString(),
                    valueSub: c['highlight'] != null ? (c['meta'] ?? c['value'])?.toString() : null,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
