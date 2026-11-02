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

  // 같은 지역의 요청은 ApiClient가 30분 동안 기억함
  static Future<Map<String, dynamic>> fetch(ApiClient api, Region r) => api.outing(sido: r.code, sgg: r.sgg);

  @override
  State<OutingSection> createState() => _OutingSectionState();
}

class _OutingSectionState extends State<OutingSection> {
  late final Future<Map<String, dynamic>> _future = OutingSection.fetch(widget.api, widget.region);

  static const _explain =
      '이 단계는 "그 곳에서 덜 붐비는 날"로 읽어 주세요. 사람 수가 아니라, 그 관광지의 앞으로 한 달 중에서 그날이 얼마나 붐빌지를 나타내는 상대 지수(0~100)예요. '
      '30 아래는 한산, 30~60은 보통, 60~80은 붐빔, 80 이상은 매우 붐빔이에요. 같은 "한산"이어도 곳마다 실제 사람 수는 달라서, 다른 관광지와 사람 수로 비교하는 용도는 아니에요. '
      '한국관광공사 관광지 집중률 방문자 추이 예측 정보이고, 오늘부터 약 30일 뒤까지 예측해요. 한산한 순으로 보여주고, 줄을 누르면 지도에서 찾아봐요.';

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
        final spots = (d['spots'] as List).cast<Map<String, dynamic>>();
        // 그 시군구에 집중률 예측이 있는 관광지가 없으면 상위 지역으로 채우지 않고 없다고 알림(2026-10-16)
        if (d['empty'] == true || spots.isEmpty || days.isEmpty) {
          return ListSection(
            title: '이번 주말 한산한 곳',
            children: [EmptyNote('${d['region'] ?? widget.region.label}에는 집중률 예측이 있는 관광지가 없어요.\n다른 지역으로 찾아보세요 ›', vertical: 40, onTap: () => showRegionPicker(context))],
          );
        }
        // 2026-10-16: 토/일 알약으로 나눠 보던 걸 한 표로 — 날마다 열을 두고 같은 곳의 집중률을 나란히
        const colW = 56.0;
        Widget cols(Widget Function(int i) cell) => Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < days.length; i++) SizedBox(width: colW, child: cell(i))]);
        return ListSection(
          title: '이번 주말 한산한 곳',
          info: GestureDetector(
            onTap: () {
              Analytics.instance.track('sources_open');
              showSourcesSheet(context, current: _explain);
            },
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.fromLTRB(8, 4, 0, 4),
              child: Icon(Icons.info_outline, size: 15, color: AppColors.inkSoft),
            ),
          ),
          children: [
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // 범례: 색 점 + 단계 이름(숫자 대신 이걸로 읽음)
                Expanded(
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      for (final l in _levels)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: l.color)),
                            const SizedBox(width: 4),
                            Text(l.label, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                          ],
                        ),
                    ],
                  ),
                ),
                cols((i) => Text('${days[i]['label']} ${days[i]['md']}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft))),
              ],
            ),
            const SizedBox(height: 8),
            Container(height: 1, color: AppColors.hair),
            ExpandableList(
              unit: '곳',
              children: [
                for (final s in spots)
                  ListLine(
                    name: s['name'] as String,
                    sub: s['sgg'] as String?,
                    middle: cols((i) => _CrowdCell(rate: (s['rates'] as List)[i] as num?)),
                    onTap: s['pin'] == null ? null : () => openMapChooser(context, (s['pin'] as Map).cast<String, dynamic>()), // 주소·좌표는 없어서 시군구+이름으로 찾음
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// 붐비는 정도 4단계(2026-10-16). 숫자(0~100)는 그 관광지의 앞으로 한 달 안에서의 상대 지수 — 30 아래 한산 · 30~60 보통 · 60~80 붐빔 · 80 이상 매우 붐빔.
/// 색은 앱의 의미색(좋음 초록·보통 황토·붐빔 주황·매우 붐빔 빨강)과 같은 계열.
class _Level {
  const _Level(this.label, this.color);

  final String label;
  final Color color;
}

const _levels = [
  _Level('한산', Color(0xFF2F9E44)),
  _Level('보통', Color(0xFFB98600)),
  _Level('붐빔', Color(0xFFE08A3E)),
  _Level('매우 붐빔', AppColors.up),
];

_Level _levelOf(num rate) => rate < 30 ? _levels[0] : (rate < 60 ? _levels[1] : (rate < 80 ? _levels[2] : _levels[3]));

/// 한 칸: 위에 단계 이름(색), 아래에 막대(차오른 만큼 붐빔). 값이 없으면 줄표.
class _CrowdCell extends StatelessWidget {
  const _CrowdCell({required this.rate});

  final num? rate;

  @override
  Widget build(BuildContext context) {
    final r = rate;
    if (r == null) return const Text('-', textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: AppColors.inkSoft));
    final l = _levelOf(r);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l.label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: l.color)),
        const SizedBox(height: 5),
        Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(color: AppColors.hair, borderRadius: BorderRadius.circular(3)),
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: (r / 100).clamp(0.06, 1.0).toDouble(), // 아주 낮아도 보이게 최소 폭
            child: Container(decoration: BoxDecoration(color: l.color, borderRadius: BorderRadius.circular(3))),
          ),
        ),
      ],
    );
  }
}
