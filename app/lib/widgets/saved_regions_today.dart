import 'package:flutter/material.dart';

import '../api_client.dart';
import '../region.dart';
import 'components.dart';

/// 투데이의 "저장한 지역 날씨"(2026-10-31): 지역 시트에서 저장해 둔 다른 지역(부모님 댁·직장 등)의 날씨를 한 줄씩.
/// 줄을 누르면 그 지역으로 바뀜. 저장한 다른 지역이 없으면 아무것도 안 그림. 날씨는 투데이와 같은 `/weather`(10분 메모)를 지역마다 뒤에서 받음.
class SavedRegionsToday extends StatelessWidget {
  const SavedRegionsToday({super.key, required this.api, required this.current});

  final ApiClient api;
  final Region current;

  @override
  Widget build(BuildContext context) {
    final others = [for (final r in RegionStore.instance.saved) if (!r.same(current)) r];
    if (others.isEmpty) return const SizedBox.shrink();
    return ListSection(
      title: '저장한 지역 날씨',
      children: [for (final r in others) _SavedRegionLine(key: ValueKey(r.label), api: api, region: r)],
    );
  }
}

class _SavedRegionLine extends StatefulWidget {
  const _SavedRegionLine({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  @override
  State<_SavedRegionLine> createState() => _SavedRegionLineState();
}

class _SavedRegionLineState extends State<_SavedRegionLine> {
  late final Future<Map<String, dynamic>> _weather = widget.api.weather(sido: widget.region.code, sgg: widget.region.sgg);

  @override
  Widget build(BuildContext context) {
    final r = widget.region;
    return FutureBuilder<Map<String, dynamic>>(
      future: _weather,
      builder: (context, snap) {
        final today = snap.data?['today'] as Map<String, dynamic>?;
        if (today == null) {
          return ListLine(
            name: r.label,
            sub: snap.hasError ? '불러오지 못했어요' : '불러오는 중',
            onTap: () => RegionStore.instance.choose(r),
          );
        }
        return ListLine(
          name: r.label,
          sub: '${today['condition']} · 최고 ${today['high']}° / 최저 ${today['low']}°',
          value: '${today['temp']}°',
          onTap: () => RegionStore.instance.choose(r),
        );
      },
    );
  }
}
