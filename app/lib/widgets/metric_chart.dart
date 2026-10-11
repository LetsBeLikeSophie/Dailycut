import 'package:flutter/material.dart';

import '../analytics.dart';
import '../local_prefs.dart';
import '../theme.dart';
import 'components.dart';

/// 머니 탭 맨 위: 문장 제목 + 큰 숫자 + 추이. 아래 칩(코스피·코스닥·금·물가)으로 지표를, 기간 칩(1개월~5년)으로
/// 가로축 범위를 고름. 기간은 모든 지표가 똑같이 적용돼서 지표를 바꿔도 축이 그대로라 비교가 편함.
/// 제목 문장도 고른 지표에 맞춰 바뀜("코스피, 마지막 거래일엔 내렸어요").
class MetricHero extends StatefulWidget {
  const MetricHero({super.key, required this.items, this.source});

  final List<Map<String, dynamic>> items; // label, value, unit, decimals, change, sub, note, when, monthly?, series
  final String? source;

  @override
  State<MetricHero> createState() => _MetricHeroState();
}

class _Range {
  const _Range(this.label, this.months);

  final String label;
  final int months; // 이번 달을 포함해 몇 개월(달력 기준: 3개월 = 2개월 전 1일부터 이번 달 말일까지)
}

const _ranges = [
  _Range('1개월', 1),
  _Range('3개월', 3),
  _Range('1년', 12),
  _Range('3년', 36),
  _Range('5년', 60),
];

class _MetricHeroState extends State<MetricHero> {
  int _selected = 0;
  int _range = 2; // 기본 1년 — 월 1회 발표인 물가도 선이 보이는 가장 짧은 기간

  @override
  void initState() {
    super.initState();
    // 마지막으로 본 지표·기간을 기억해서 다음에도 그걸로 열어 줌(기기에만 저장)
    LocalPrefs.getString('money_pref').then((v) {
      if (v == null || !mounted) return;
      final parts = v.split('|');
      final i = widget.items.indexWhere((e) => e['label'] == parts[0]);
      final r = _ranges.indexWhere((e) => e.label == (parts.length > 1 ? parts[1] : ''));
      setState(() {
        if (i >= 0) _selected = i;
        if (r >= 0) _range = r;
      });
    });
  }

  void _remember() => LocalPrefs.setString('money_pref', '${widget.items[_selected]['label']}|${_ranges[_range].label}');

  @override
  Widget build(BuildContext context) {
    final it = widget.items[_selected];
    final unit = it['unit'] as String;
    final decimals = (it['decimals'] as num?)?.toInt() ?? 0;
    final monthly = it['monthly'] == true;
    final change = it['change'] as String;
    final rg = _ranges[_range];
    final today = DateTime.now();
    // 달력 기준 축: 시작 = (이번 달 포함 N개월)의 첫날, 끝 = 이번 달 말일(아직 안 온 날은 비워 둠)
    final start = DateTime(today.year, today.month - (rg.months - 1), 1);
    final end = DateTime(today.year, today.month + 1, 0);
    final totalX = end.difference(start).inDays + 1;
    final series = (it['series'] as List).cast<Map<String, dynamic>>();

    int xOf(DateTime d) => d.difference(start).inDays + 1;
    DateTime dateOf(int x) => start.add(Duration(days: x - 1));
    final points = <ChartPoint>[];
    DateTime? firstDate;
    for (final e in series) {
      final d = DateTime.parse(e['date'] as String);
      if (d.isBefore(start) || d.isAfter(end)) continue;
      firstDate ??= d;
      points.add(ChartPoint(xOf(d), (e['value'] as num).toDouble()));
    }
    // 고른 기간에 점이 하나도 없으면(월초·연휴 등) 가장 최근 한 점이라도
    if (points.isEmpty && series.isNotEmpty) {
      final d = DateTime.parse(series.last['date'] as String);
      points.add(ChartPoint(xOf(d).clamp(1, totalX), (series.last['value'] as num).toDouble()));
    }

    String shortLabel(int x) {
      final d = dateOf(x);
      if (rg.months <= 3) return '${d.month}/${d.day}';
      if (rg.months <= 12) return '${d.month}월';
      return "'${(d.year % 100).toString().padLeft(2, '0')}.${d.month}";
    }

    String fullLabel(int x) {
      final d = dateOf(x);
      return monthly ? '${d.year}년 ${d.month}월' : '${d.year}.${d.month}.${d.day}';
    }

    // 눈금: 1개월은 1·8·15·22·말일, 그보다 길면 달의 첫날(최대 5개, 같은 간격)
    final List<int> ticks;
    if (rg.months == 1) {
      ticks = [1, 8, 15, 22, totalX];
    } else {
      final step = (rg.months / 4).ceil();
      ticks = [for (var m = 0; m < rg.months; m += step) xOf(DateTime(start.year, start.month + m, 1))];
      // 축 끝(이번 달 말일)도 눈금으로 — 아직 오지 않은 날도 축은 끝까지 보여줌
      if (totalX - ticks.last > totalX * 0.08) ticks.add(totalX);
    }
    final diff = points.length >= 2 ? points.last.value - points.first.value : 0.0;
    final diffKey = diff.abs() < 1e-9 ? 'flat' : (diff > 0 ? 'up' : 'down');
    final diffDecimals = decimals == 0 && diff.abs() < 10 ? 1 : decimals;
    final suffix = unit == 'pt' ? '' : (unit == '원/g' ? '원' : unit);
    final partial = firstDate != null && points.length >= 2 && firstDate.difference(start).inDays > totalX * 0.15;
    final agoText = firstDate == null
        ? ''
        : (rg.months <= 3 ? '${firstDate.month}/${firstDate.day}' : "${firstDate.year}.${firstDate.month}");
    final deltaText = points.length < 2
        ? '이 기간엔 기록이 하나뿐이에요'
        : '${changeLabel(diffKey)} $agoText보다 ${diff >= 0 ? '+' : '-'}${formatNumber(diff.abs(), decimals: diffDecimals)}${unit == '%' ? '%p' : suffix}';

    final verb = switch (change) { 'up' => '올랐어요', 'down' => '내렸어요', _ => '그대로예요' };
    final when = (it['when'] as String?) ?? '마지막 거래일엔';
    final emphasis = monthly ? '${formatNumber((it['value'] as num).abs(), decimals: decimals)}% $verb' : verb;
    final headline = monthly ? '물가는 $when $emphasis' : '${it['label']}, $when $verb';

    return PageHero(
      section: Section.money,
      headline: headline,
      emphasis: emphasis,
      headlineLines: 2,
      source: widget.source,
      body: [
        ArrowSelector(label: it['label'] as String, index: _selected, count: widget.items.length, onChanged: (i) {
          setState(() => _selected = i);
          _remember();
          Analytics.instance.track('money_metric', widget.items[i]['label'] as String);
        }),
        const SizedBox(height: 10),
        BigNumber(key: ValueKey('m${it['label']}'), to: it['value'] as num, decimals: decimals, unit: unit),
        const SizedBox(height: 4),
        Text(deltaText, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: changeColor(diffKey))),
        const SizedBox(height: 14),
        TrendChart(
          key: ValueKey('mc${it['label']}$_range'),
          section: Section.money,
          points: points,
          format: (v) => '${formatNumber(v, decimals: decimals)}$suffix',
          xMax: totalX,
          ticks: ticks,
          xLabel: shortLabel,
          selLabel: fullLabel,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < _ranges.length; i++) ...[
              _Pill(label: _ranges[i].label, selected: _range == i, small: true, onTap: () {
                setState(() => _range = i);
                _remember();
                Analytics.instance.track('money_range', _ranges[i].label);
              }),
              if (i < _ranges.length - 1) const SizedBox(width: 6),
            ],
          ],
        ),
        const SizedBox(height: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 11 * 1.5 * 2), // 설명 길이가 달라도 2줄 자리(아래가 안 움직이게)
          child: Text(
            '${it['sub']}${partial ? ' · 데이터는 ${firstDate.year}.${firstDate.month}부터 있어요' : ''}',
            style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.5),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap, this.small = false});

  final String label;
  final bool selected;
  final bool small;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 10 : 12, vertical: small ? 5 : 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(small ? 8 : 999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: small ? 12 : 13,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : AppColors.ink,
          ),
        ),
      ),
    );
  }
}
