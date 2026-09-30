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
    // 2026-09-30: "날씨는 따로 볼 페이지가 없으니 투데이 카드에 정보를
    // 더 실어달라" 요청 — 다른 섹션과 같은 3줄짜리 HeroCard 대신, 날씨만
    // WeatherHero(오늘 기온+시간대별+주간+옷차림+빨래·세차+미세먼지)를
    // 그대로 씀. 그러려면 today()의 요약 필드 말고 weather()의 전체
    // 데이터가 따로 필요해서 같이 받아옴.
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
        final cards = (data['cards'] as List).cast<Map<String, dynamic>>();
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
          children: [
            // "섹션 대제목에만 세리프" 규칙 — 이 헤드라인은 생활/문화/머니/AI
            // 중 하나가 아니라서 세리프 대신 Noto Sans KR 볼드로 씀.
            Text(
              data['headline'] as String,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink),
            ),
            const SizedBox(height: 20),
            for (final c in cards) ...[
              if (c['section'] == 'weather')
                WeatherHero(section: Section.weather, data: weather)
              else
                HeroCard(
                  section: Section.values.byName(c['section'] as String),
                  title: (c['title'] ?? c['label'] ?? '') as String,
                  highlight: c['highlight'] as String?,
                  meta: (c['meta'] ?? c['value']?.toString()) as String?,
                ),
              const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}
