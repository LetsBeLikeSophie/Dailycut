import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';
import 'components.dart';

/// 문화 탭 영화: 기간(어제·지난주·지난 주말) × 구분(전체·한국·외국·독립·예술·내 지역) 박스오피스 TOP 10,
/// 줄을 누르면 영화 상세(감독·출연·장르·등급·상영 규모), 그 아래 "최근 개봉" 목록.
/// 데이터는 영화진흥위원회 KOBIS(영화관입장권통합전산망).
class BoxOfficeSection extends StatefulWidget {
  const BoxOfficeSection({super.key, required this.api, required this.data, this.stub = false});

  final ApiClient api;
  final Map<String, dynamic> data; // /culture 응답
  final bool stub;

  @override
  State<BoxOfficeSection> createState() => _BoxOfficeSectionState();
}

class _BoxOfficeSectionState extends State<BoxOfficeSection> {
  static const _periods = [('daily', '어제'), ('weekly', '지난주'), ('weekend', '지난 주말')];
  static const _filters = [('all', '전체'), ('kr', '한국'), ('foreign', '외국'), ('indie', '독립·예술')];
  String _period = 'daily';
  String _filter = 'all'; // all|kr|foreign|indie|region

  Map<String, dynamic>? get _region => widget.data['box_office_region'] as Map<String, dynamic>?;

  List<Map<String, dynamic>> get _items {
    if (_filter == 'region') {
      return ((_region?['items'] as List?) ?? const []).cast<Map<String, dynamic>>();
    }
    final sets = widget.data['box_office_sets'] as Map<String, dynamic>?;
    return ((sets?['$_period|$_filter'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  @override
  Widget build(BuildContext context) {
    final ranges = (widget.data['box_office_ranges'] as Map<String, dynamic>?) ?? const {};
    final region = _region;
    final trailing = _filter == 'region'
        ? '${region?['name']} · 어제'
        : (ranges[_period] == null ? null : '${ranges[_period]} 기준');
    final newReleases = ((widget.data['new_releases'] as List?) ?? const []).cast<Map<String, dynamic>>();
    final items = _items;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListSection(
          title: '박스오피스',
          trailing: trailing,
          stub: widget.stub,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (k, label) in _periods)
                    _Pill(
                      label: label,
                      selected: _filter != 'region' && _period == k,
                      onTap: () => setState(() {
                        _period = k;
                        if (_filter == 'region') _filter = 'all'; // 지역별은 어제 기준만 있어서 기간을 바꾸면 전국으로
                      }),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (k, label) in _filters)
                    _Pill(label: label, small: true, selected: _filter == k, onTap: () => setState(() => _filter = k)),
                  if (region != null)
                    _Pill(
                      label: '${region['name']}',
                      small: true,
                      icon: Icons.place_outlined,
                      selected: _filter == 'region',
                      onTap: () => setState(() {
                        _filter = 'region';
                        _period = 'daily';
                      }),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.hair),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('아직 집계된 순위가 없어요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
              ),
            ExpandableList(
              key: ValueKey('$_period|$_filter'),
              children: [for (final it in items) _line(context, it)],
            ),
          ],
        ),
        if (newReleases.isNotEmpty)
          ListSection(
            title: '최근 개봉',
            trailing: '개봉 예정 포함',
            stub: widget.stub,
            children: [
              ExpandableList(children: [for (final it in newReleases) _releaseLine(context, it)]),
            ],
          ),
      ],
    );
  }

  Widget _line(BuildContext context, Map<String, dynamic> it) {
    return ListLine(
      leading: SizedBox(
        width: 28,
        child: Text('${it['rank']}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
      ),
      name: it['title'] as String,
      badge: it['new'] == true ? '신규' : null,
      sub: it['meta'] as String,
      onTap: it['code'] == null ? null : () => showMovieSheet(context, widget.api, it),
    );
  }

  Widget _releaseLine(BuildContext context, Map<String, dynamic> it) {
    final open = DateTime.tryParse((it['open'] as String?) ?? '');
    final future = open != null && open.isAfter(DateTime.now());
    return ListLine(
      name: it['title'] as String,
      sub: '누적 ${_man(it['acc'] as int)}명 · 스크린 ${_num(it['scrn'] as int)}개',
      value: open == null ? null : '${open.month}/${open.day}',
      valueSub: future ? '개봉 예정' : '개봉',
      onTap: it['code'] == null ? null : () => showMovieSheet(context, widget.api, it),
    );
  }
}

String _num(num n) => formatNumber(n);

String _man(int n) {
  if (n >= 10000) {
    final v = n / 10000;
    return v < 100 ? '${formatNumber(v, decimals: 1)}만' : '${formatNumber(v)}만';
  }
  return formatNumber(n);
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap, this.small = false, this.icon});

  final String label;
  final bool selected;
  final bool small;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 11 : 14, vertical: small ? 6 : 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          border: Border.all(color: selected ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(small ? 8 : 999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[Icon(icon, size: 14, color: selected ? Colors.white : AppColors.ink), const SizedBox(width: 3)],
            Text(
              label,
              style: TextStyle(fontSize: small ? 12 : 13, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// 영화 상세 시트: 서버(KOBIS 영화 상세)에서 감독·출연·장르·등급·상영시간을 받고, 목록의 관객·스크린 수 같은 숫자는 바로 보여줌.
Future<void> showMovieSheet(BuildContext context, ApiClient api, Map<String, dynamic> it) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
    builder: (_) => _MovieSheet(api: api, item: it),
  );
}

class _MovieSheet extends StatelessWidget {
  const _MovieSheet({required this.api, required this.item});

  final ApiClient api;
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[Section.culture]!;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height * 0.55),
          child: FutureBuilder<Map<String, dynamic>>(
            future: api.movieDetail(item['code'] as String),
            builder: (context, snap) {
              final d = snap.data;
              final ok = d != null && d['found'] == true;
              Widget row(String label, String? value) {
                if (value == null || value.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 56, child: Text(label, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                      Expanded(child: Text(value, style: const TextStyle(fontSize: 16, height: 1.5))),
                    ],
                  ),
                );
              }

              final facts = <String>[
                if (ok && (d['grade'] as String).isNotEmpty) d['grade'] as String,
                if (ok && d['runtime'] != null) '${d['runtime']}분',
                if (ok) ...(d['genres'] as List).cast<String>().take(2),
                if (ok) ...(d['nations'] as List).cast<String>().take(1),
              ];
              final open = (ok ? d['open'] : item['open']) as String?;
              final unit = (item['meta'] as String).split(' ').first; // 어제 / 주간 / 주말 / 날짜
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item['title'] as String, style: AppTheme.displaySerif(size: 26, fontWeight: FontWeight.w700)),
                  if (ok && (d['title_en'] as String).isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(d['title_en'] as String, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                  ],
                  if (facts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < facts.length; i++)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: i == 0 ? t.color : null,
                              border: i == 0 ? null : Border.all(color: AppColors.line),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(facts[i], style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: i == 0 ? Colors.white : AppColors.ink)),
                          ),
                      ],
                    ),
                  ],
                  if (ok) row('감독', (d['directors'] as List).cast<String>().join(', ')),
                  if (ok) row('출연', (d['actors'] as List).cast<String>().take(5).join(', ')),
                  row('개봉', open == null || open.length < 10 ? null : '${open.substring(0, 4)}.${int.parse(open.substring(5, 7))}.${int.parse(open.substring(8, 10))}'),
                  if (snap.connectionState != ConnectionState.done)
                    const Padding(padding: EdgeInsets.only(top: 20), child: Center(child: CircularProgressIndicator())),
                  const SizedBox(height: 24),
                  Text('박스오피스', style: AppTheme.subheading),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 28,
                    runSpacing: 14,
                    children: [
                      _stat('$unit 관객', '${_man(item['audi'] as int)}명'),
                      _stat('누적 관객', '${_man(item['acc'] as int)}명'),
                      _stat('스크린 수', '${_num(item['scrn'] as int)}개'),
                      _stat('상영 횟수', '${_num(item['show'] as int)}회'),
                      _stat('매출 점유율', '${(item['share'] as num).toStringAsFixed(1)}%'),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text('출처: 영화진흥위원회 영화관입장권통합전산망', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.inkSoft)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFeatures: [FontFeature.tabularFigures()])),
        ],
      );
}
