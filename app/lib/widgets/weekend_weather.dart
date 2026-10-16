import 'package:flutter/material.dart';

import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';

/// 나들이 탭 히어로 안의 "이번 주말 날씨" 한 문장(2026-10-16): 투데이의 옷차림 문장처럼 16 굵게 + 형광펜.
/// 예전엔 토·일 날씨를 줄 목록으로 따로 보였음. 한산한 곳·캠핑·반려동물·웰니스·걷기길이 같이 쓰는 한 곳.
/// 문장은 서버가 만든 주말 요약(`weekend`: "토요일은 맑음 13~25°, 일요일은 비 16~21°예요")에,
/// 야외 활동에 필요한 사실(비 50%↑ → 우산, 밤 5° 이하 → 추움)을 덧붙임.
class WeekendWeatherLine extends StatefulWidget {
  const WeekendWeatherLine({super.key, required this.api, required this.region});

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
  State<WeekendWeatherLine> createState() => _WeekendWeatherLineState();
}

class _WeekendWeatherLineState extends State<WeekendWeatherLine> {
  late final Future<Map<String, dynamic>> _future = WeekendWeatherLine.fetch(widget.api, widget.region);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        final weekend = (d?['weekend'] as String?) ?? '';
        if (d == null || weekend.isEmpty) return const SizedBox.shrink(); // 부가 정보라 못 받으면 숨김
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final sat = today.weekday == DateTime.sunday ? today : today.add(Duration(days: (DateTime.saturday - today.weekday) % 7));
        final wanted = today.weekday == DateTime.sunday ? [today] : [sat, sat.add(const Duration(days: 1))];
        const names = ['월', '화', '수', '목', '금', '토', '일'];
        final weekly = (d['weekly'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
        final hints = <String>[];
        for (final day in wanted) {
          for (final w in weekly) {
            if (w['date'] != '${day.month}/${day.day}' || w['high'] == null) continue;
            final n = names[day.weekday - 1];
            if (w['pop'] is num && (w['pop'] as num) >= 50) hints.add('$n요일엔 우산을 챙기세요');
            if (w['low'] is num && (w['low'] as num) <= 5) hints.add('$n요일 밤엔 많이 추워요');
          }
        }
        final text = [weekend, ...hints].join(' · ');
        return Padding(
          padding: const EdgeInsets.only(top: 4),
          child: HighlightText(
            text: text,
            emphasis: text,
            color: sectionThemes[Section.place]!.highlight,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, height: 1.6),
          ),
        );
      },
    );
  }
}
