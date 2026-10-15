import 'package:flutter/material.dart';

import '../analytics.dart';
import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';
import 'map_links.dart';
import 'sources_info.dart';

/// 문화 탭 "이번 주말 한산한 곳": 한국관광공사 관광지 집중률 예측(오늘~약 30일 뒤)으로 토·일별로 예상 집중도가 낮은 관광지를 보여줌.
/// 집중률은 사람 수가 아니라 그 관광지 기준의 예상 방문 집중도(0~100, 높을수록 붐빔) — 제목 옆 ⓘ에서 설명.
/// 처음 부르는 지역은 서버가 몇 초 걸려서(그 뒤 24시간 캐시) 본문을 막지 않게 따로 불러오고, 못 받으면 조용히 숨김.
class OutingSection extends StatefulWidget {
  const OutingSection({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  static final Map<String, ({DateTime at, Future<Map<String, dynamic>> future})> _memo = {};

  static Future<Map<String, dynamic>> fetch(ApiClient api, Region r) {
    final key = '${r.code}/${r.sgg ?? ''}';
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at).inMinutes < 30) return hit.future;
    final f = api.outing(sido: r.code, sgg: r.sgg);
    _memo[key] = (at: DateTime.now(), future: f);
    f.catchError((_) {
      _memo.remove(key);
      return <String, dynamic>{};
    });
    return f;
  }

  @override
  State<OutingSection> createState() => _OutingSectionState();
}

class _OutingSectionState extends State<OutingSection> {
  late final Future<Map<String, dynamic>> _future = OutingSection.fetch(widget.api, widget.region);
  int _day = 0;

  static const _explain =
      '한국관광공사 관광지 집중률 방문자 추이 예측 정보예요. 관광지별로 예상되는 방문 집중도를 0~100으로 나타내고, 높을수록 붐빈다는 뜻이에요. '
      '사람 수가 아니라 그 관광지의 평소 방문 대비 지수라서, 서로 다른 관광지의 숫자를 그대로 비교하기보다는 "그 장소가 덜 붐비는 날"을 찾는 용도로 봐 주세요. '
      '오늘부터 약 30일 뒤까지 예측하고, 날씨는 기상청 중기예보예요.';

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (snap.hasError || (d != null && d['live'] != true)) return const SizedBox.shrink(); // 부가 구역이라 못 받으면 숨김
        if (d == null) {
          return ListSection(
            title: '이번 주말 한산한 곳',
            children: const [
              Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: LoadingNote(label: null))),
            ],
          );
        }
        final days = (d['days'] as List).cast<Map<String, dynamic>>();
        final day = days[_day.clamp(0, days.length - 1)];
        final spots = (day['spots'] as List).cast<Map<String, dynamic>>();
        return ListSection(
          title: '이번 주말 한산한 곳',
          action: GestureDetector(
            onTap: () {
              Analytics.instance.track('sources_open');
              showSourcesSheet(context, current: _explain);
            },
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Icon(Icons.info_outline, size: 15, color: AppColors.inkSoft),
            ),
          ),
          children: [
            if (days.length > 1) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < days.length; i++)
                    PillChip(
                      label: '${days[i]['label']} ${days[i]['md']}',
                      selected: _day == i,
                      onTap: () => setState(() => _day = i),
                    ),
                ],
              ),
            ],
            if (d['scope_note'] != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(d['scope_note'] as String, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6))),
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.hair),
            ExpandableList(
              key: ValueKey('outing$_day'),
              unit: '곳',
              children: [
                for (final s in spots)
                  ListLine(
                    name: s['name'] as String,
                    sub: s['sgg'] as String?,
                    value: '${s['rate']}',
                    valueSub: '집중률',
                    onTap: s['pin'] == null ? null : () => openMapChooser(context, (s['pin'] as Map).cast<String, dynamic>()), // 주소·좌표는 없어서 시군구+이름으로 찾음
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(
                '${d['region']} · 예상 집중도가 낮은 순이에요. 누르면 지도에서 찾아봐요.',
                style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6),
              ),
            ),
          ],
        );
      },
    );
  }
}
