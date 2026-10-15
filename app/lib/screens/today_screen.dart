import 'package:flutter/material.dart';

import '../splash_stub.dart' if (dart.library.js_interop) '../splash_web.dart';

import '../api_client.dart';
import '../boot.dart';
import '../region.dart';
import '../theme.dart';
import '../widgets/components.dart';
import '../widgets/hourly_strip.dart';
import '../widgets/life_index.dart';
import '../widgets/my_basket_today.dart';
import '../widgets/weekend_weather.dart';
import '../widgets/weather_icon.dart';

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  // 2026-10-15: 날씨(맨 위 히어로·주간·생활지수)만 오면 먼저 그림. `/today`(오늘의 섹션 카드)는 따로 받아서
  // 느려도 화면을 막지 않고, 실패하면 그 구역만 안 보임.
  late Future<Map<String, dynamic>> _weather;
  late Future<Map<String, dynamic>?> _today;

  @override
  void initState() {
    super.initState();
    // 날씨는 전용 탭이 없고 투데이 맨 위에만 있어서, today()의 요약
    // 필드 말고 weather()의 전체 데이터(시간대별·주간·지수)를 같이 받아옴.
    // 지역(시도)은 앱 전체가 공유함(region.dart).
    _load();
  }

  void _load() {
    _weather = widget.api.weather(sido: widget.region.code, sgg: widget.region.sgg);
    _today = widget.api
        .today(sido: widget.region.code, sgg: widget.region.sgg)
        .then<Map<String, dynamic>?>((v) => v, onError: (_) => null);
  }

  // 2026-10-16: 첫 방문은 서울로 먼저 그리고 위치를 알아낸 뒤 지역이 바뀌는데, 예전엔 그때 이 화면이 통째로 새로 만들어져서
  // 스플래시가 걷힌 뒤 1초쯤 뒤에 로딩 원이 2~3초 다시 돌았음 → 이제 화면을 그대로 두고 새 지역 데이터만 받아 바꿔 끼움
  // (받는 동안은 이전 내용 위에 가는 진행 막대만).
  @override
  void didUpdateWidget(TodayScreen old) {
    super.didUpdateWidget(old);
    if (old.region.code != widget.region.code || old.region.sgg != widget.region.sgg) {
      setState(_load);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _weather,
      builder: (context, snapshot) {
        final waiting = snapshot.connectionState != ConnectionState.done;
        if (waiting && !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        // 첫 화면 데이터가 준비됐으니 웹 스플래시를 걷음(받는 동안은 스플래시가 덮고 있어서 스피너가 또 보이지 않음)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          hideSplash();
          kFirstScreenReady.value = true; // 이제 다른 탭을 뒤에서 만들어 둠(main.dart)
        });
        if (snapshot.hasError) {
          return Center(
            child: Text(
              '불러오지 못했어요\n${snapshot.error}',
              textAlign: TextAlign.center,
            ),
          );
        }
        final weather = snapshot.data!;
        final eyebrow = '오늘 · ${RegionStore.instance.label}';
        final t = sectionThemes[Section.weather]!;

        final today = weather['today'] as Map<String, dynamic>;
        final hourly = (weather['hourly'] as List).cast<Map<String, dynamic>>();
        final weekly = (weather['weekly'] as List).cast<Map<String, dynamic>>();
        final goodFor = (weather['good_for'] as List)
            .cast<Map<String, dynamic>>();
        final air = weather['air_quality'] as Map<String, dynamic>;
        final weatherLive =
            (weather['live_keys'] as List?)?.contains('today') ?? false;
        final holiday = weather['next_holiday'] as Map<String, dynamic>?;
        final weekend = (weather['weekend'] as String?) ?? '';
        final life =
            (weather['life'] as List?)?.cast<Map<String, dynamic>>() ??
            const [];
        final indexes = (weather['indexes'] as List?)
            ?.cast<Map<String, dynamic>>();

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          children: [
            if (waiting) const LinearProgressIndicator(minHeight: 2, color: AppColors.ink, backgroundColor: AppColors.hair),
            PageHero(
              section: Section.weather,
              eyebrow: eyebrow,
              onEyebrowTap: () => showRegionPicker(context),
              stub: !weatherLive,
              headline: (weather['headline'] as String?) ?? '오늘의 날씨',
              source: weatherLive
                  ? weather['source'] as String?
                  : '${weather['source']} · 예시 데이터',
              body: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: BigNumber(
                        to: today['temp'] as num,
                        suffix: '°',
                        unit: today['condition'] as String,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: WeatherIcon(
                        today['condition'] as String?,
                        size: 52,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '체감 ${today['feels_like']}° · 최고 ${today['high']}° · 최저 ${today['low']}°',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.inkSoft,
                  ),
                ),
                const SizedBox(height: 18),
                // 시간대별: 오늘 0시~모레 0시 가로 스크롤(지금 칸에서 시작)
                HourlyStrip(hours: hourly),
                const SizedBox(height: 18),
                HighlightText(
                  text: weather['outfit'] as String,
                  emphasis: weather['outfit'] as String,
                  color: t.highlight,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    height: 1.6,
                  ),
                ),
                if (weekend.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    weekend,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkSoft,
                      height: 1.5,
                    ),
                  ),
                ],
              ],
            ),
            ListSection(
              title: '이번 주 날씨',
              trailing: weather['weekly_range'] as String?,
              stub: !weatherLive,
              children: [for (final w in weekly) weeklyRow(w)],
            ),
            if (indexes != null)
              LifeIndexSection(indexes: indexes, stub: !weatherLive)
            else
            ListSection(
              title: '오늘의 생활 지수',
              trailing: indexes != null ? '눌러서 근거 보기' : null,
              stub: !weatherLive,
              children: indexes != null
                  ? [for (final it in indexes) lifeIndexLine(context, it)]
                  : [
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
                          sub: [
                            if (g['basis'] != null) g['basis'],
                            if (g['source'] != null) g['source'],
                          ].join(' · '),
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
            // 생활 탭에서 담아 둔 품목이 있을 때만 보임(없으면 아무것도 안 그림)
            MyBasketToday(api: widget.api, region: widget.region),
            FutureBuilder<Map<String, dynamic>?>(
              future: _today,
              builder: (context, snap) {
                final data = snap.data;
                if (data == null) return const SizedBox.shrink(); // 받는 중이거나 실패 — 이 구역만 비움
                final liveSections = (data['live_sections'] as List?)?.cast<String>() ?? const <String>[];
                // 예시(스텁) 카드는 뺌
                final others = (data['cards'] as List)
                    .cast<Map<String, dynamic>>()
                    .where((c) => c['section'] != 'weather' && liveSections.contains(c['section']))
                    .toList();
                if (others.isEmpty) return const SizedBox.shrink();
                return ListSection(
                              title: '오늘의 섹션',
                              children: [
                                for (final c in others)
                                  ListLine(
                                    stub: !liveSections.contains(c['section']),
                                    name: (c['title'] ?? c['label'] ?? '') as String,
                                    sub:
                                        sectionThemes[Section.values.byName(
                                              c['section'] as String,
                                            )]!
                                            .label,
                                    value: (c['highlight'] ?? c['meta'] ?? c['value'] ?? '')
                                        .toString(),
                                    valueSub: c['highlight'] != null
                                        ? (c['meta'] ?? c['value'])?.toString()
                                        : null,
                                  ),
                              ],
                            );
              },
            ),
          ],
        );
      },
    );
  }
}

/// 미세먼지 줄 설명: 에어코리아 시도 내 측정소 평균값과 등급 기준(환경부).
String? _airBasis(
  Map<String, dynamic> air,
  String valueKey,
  String name,
  String cuts,
) {
  final v = air[valueKey];
  if (v == null) return null;
  return '$name $v㎍/㎥ · 에어코리아 ${air['scope'] ?? ''} 측정소 ${air['stations'] ?? '여러'}곳 평균 · 환경부 기준($cuts)';
}
