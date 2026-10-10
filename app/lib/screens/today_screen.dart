import 'package:flutter/material.dart';
import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import '../widgets/components.dart';
import '../widgets/hourly_strip.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

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
    // 지역(시도)은 앱 전체가 공유함(region.dart). 지역이 바뀌면 이 화면이 새로 만들어져서 다시 받아옴.
    _future = () async {
      final results = await Future.wait([
        widget.api.today(sido: widget.region.code, sgg: widget.region.sgg),
        widget.api.weather(sido: widget.region.code, sgg: widget.region.sgg),
      ]);
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
        final eyebrow = '오늘 · ${RegionStore.instance.label}';
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
        final life = (weather['life'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final liveSections = (data['live_sections'] as List?)?.cast<String>() ?? const <String>[];

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            PageHero(
              section: Section.weather,
              eyebrow: eyebrow,
              onEyebrowTap: () => showRegionPicker(context),
              stub: !weatherLive,
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
                // 시간대별: 오늘 0시~모레 0시 가로 스크롤(지금 칸에서 시작)
                HourlyStrip(hours: hourly),
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
              trailing: weather['weekly_range'] as String?,
              stub: !weatherLive,
              children: [for (final w in weekly) _weeklyRow(w)],
            ),
            ListSection(
              title: '오늘의 생활 지수',
              stub: !weatherLive,
              children: [
                if (holiday != null)
                  ListLine(
                    name: '다음 공휴일',
                    sub: '한국천문연구원 특일정보',
                    value: 'D-${holiday['d_day']}',
                    valueSub: holiday['name'] as String?,
                  ),
                for (final g in goodFor)
                  ListLine(
                    name: g['label'] as String,
                    sub: [if (g['basis'] != null) g['basis'], if (g['source'] != null) g['source']].join(' · '),
                    value: g['good'] == true ? '하기 좋아요' : '별로예요',
                  ),
                ListLine(
                  name: '미세먼지',
                  sub: _airBasis(air, 'pm10_value', 'PM10', '30/80/150'),
                  value: '${air['pm10']}',
                ),
                ListLine(
                  name: '초미세먼지',
                  sub: _airBasis(air, 'pm25_value', 'PM2.5', '15/35/75'),
                  value: '${air['pm25']}',
                ),
                for (final r in life)
                  ListLine(
                    name: r['title'] as String,
                    sub: r['basis'] as String?,
                    value: r['meta'] as String,
                  ),
              ],
            ),
            ListSection(
              title: '오늘의 섹션',
              children: [
                for (final c in others)
                  ListLine(
                    stub: !liveSections.contains(c['section']),
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

/// 미세먼지 줄 설명: 에어코리아 시도 내 측정소 평균값과 등급 기준(환경부).
String? _airBasis(Map<String, dynamic> air, String valueKey, String name, String cuts) {
  final v = air[valueKey];
  if (v == null) return null;
  return '$name $v㎍/㎥ · 에어코리아 ${air['scope'] ?? ''} 측정소 ${air['stations'] ?? '여러'}곳 평균 · 환경부 기준($cuts)';
}

/// 주간 한 줄: 왼쪽에 요일(오늘은 강조)과 그 아래 날짜, 가운데 날씨, 오른쪽 최저/최고.
/// 기상청이 안 주는 날(단기·중기예보 사이)은 "예보 없음"으로 비워둠.
Widget _weeklyRow(Map<String, dynamic> w) {
  final high = w['high'];
  final has = high != null;
  final pop = (w['pop'] as num?)?.toInt() ?? 0;
  final today = w['is_today'] == true;
  return ListLine(
    leading: SizedBox(
      width: 40,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            w['day'] as String,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: today ? AppColors.ink : AppColors.ink),
          ),
          Text(w['date'] as String, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
        ],
      ),
    ),
    name: has ? (w['condition'] as String? ?? '') : '예보 없음',
    sub: has ? null : '기상청이 이 날은 제공하지 않아요',
    middle: pop > 0 ? Text('$pop%', style: const TextStyle(fontSize: 13, color: AppColors.down)) : null,
    value: has ? '${w['low']}° / $high°' : '–',
  );
}
