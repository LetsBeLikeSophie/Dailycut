import 'package:flutter/material.dart';

import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';
import 'weather_icon.dart';

/// 장소 탭의 "이번 주말 날씨"(토·일, 일요일이면 오늘만) — 한산한 곳·캠핑·반려동물·웰니스·걷기길이 같이 쓰는 한 곳(2026-10-16).
/// 예전엔 한산한 곳과 캠핑이 따로 같은 날씨를 다른 모양으로 보여줬음. 투데이의 주간 날씨와 같은 줄 모양(`weeklyRow`)에,
/// 야외 활동에 필요한 사실만 줄 밑에 덧붙임(밤 5° 이하 / 강수 50%↑).
class WeekendWeather extends StatefulWidget {
  const WeekendWeather({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  static final Map<String, ({DateTime at, Future<Map<String, dynamic>> future})> _memo = {};

  static Future<Map<String, dynamic>> fetch(ApiClient api, Region r) {
    final key = '${r.code}/${r.sgg ?? ''}';
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at).inMinutes < 10) return hit.future;
    final f = api.weather(sido: r.code, sgg: r.sgg);
    _memo[key] = (at: DateTime.now(), future: f);
    f.catchError((_) {
      _memo.remove(key);
      return <String, dynamic>{};
    });
    return f;
  }

  @override
  State<WeekendWeather> createState() => _WeekendWeatherState();
}

class _WeekendWeatherState extends State<WeekendWeather> {
  late final Future<Map<String, dynamic>> _future = WeekendWeather.fetch(widget.api, widget.region);

  String? _hint(Map<String, dynamic> w) {
    final hints = <String>[
      if (w['low'] is num && (w['low'] as num) <= 5) '밤엔 많이 추워요',
      if (w['pop'] is num && (w['pop'] as num) >= 50) '비 예보가 있어요',
    ];
    return hints.isEmpty ? null : hints.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final weekly = (snap.data?['weekly'] as List?)?.cast<Map<String, dynamic>>();
        if (weekly == null) return const SizedBox.shrink(); // 부가 정보라 못 받으면 숨김
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final sat = today.weekday == DateTime.sunday ? today : today.add(Duration(days: (DateTime.saturday - today.weekday) % 7));
        final wanted = today.weekday == DateTime.sunday ? [today] : [sat, sat.add(const Duration(days: 1))];
        final days = [
          for (final d in wanted)
            for (final w in weekly)
              if (w['date'] == '${d.month}/${d.day}' && w['high'] != null) w,
        ];
        if (days.isEmpty) return const SizedBox.shrink();
        return ListSection(
          title: '이번 주말 날씨',
          trailing: '기상청',
          children: [for (final w in days) weeklyRow(w, hint: _hint(w))],
        );
      },
    );
  }
}

/// 주간 한 줄: 왼쪽에 요일(오늘은 강조)과 그 아래 날짜, 가운데 날씨, 오른쪽 최저/최고.
/// 기상청이 안 주는 날(단기·중기예보 사이)은 "예보 없음"으로 비워둠.
Widget weeklyRow(Map<String, dynamic> w, {String? hint}) {
  final high = w['high'];
  final has = high != null;
  final pop = (w['pop'] as num?)?.toInt() ?? 0;
  final today = w['is_today'] == true;
  return ListLine(
    leading: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                w['day'] as String,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: today ? AppColors.ink : AppColors.ink,
                ),
              ),
              Text(
                w['date'] as String,
                style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 22,
          child: has ? WeatherIcon(w['condition'] as String?, size: 20) : null,
        ),
      ],
    ),
    name: has ? (w['condition'] as String? ?? '') : '예보 없음',
    sub: has ? hint : '기상청이 이 날은 제공하지 않아요',
    middle: pop > 0
        ? Text(
            '$pop%',
            style: const TextStyle(fontSize: 13, color: AppColors.down),
          )
        : null,
    value: has ? '${w['low']}° / $high°' : '–',
  );
}
