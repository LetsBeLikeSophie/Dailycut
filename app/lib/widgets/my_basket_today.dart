import 'package:flutter/material.dart';

import '../api_client.dart';
import '../my_basket.dart';
import '../region.dart';
import 'components.dart';

/// 투데이의 "내 장바구니": 생활 탭에서 담아 둔 품목이 지난주보다 얼마나 움직였는지 몇 줄로.
/// 담은 게 없으면 아무것도 안 그림(빈 칸을 보여주지 않음). 시세는 생활 탭과 같은 `/market`을 받되,
/// 투데이 첫 화면을 막지 않게 이 위젯만 따로 뒤에서 받음(같은 지역은 10분 메모).
class MyBasketToday extends StatefulWidget {
  const MyBasketToday({super.key, required this.api, required this.region});

  final ApiClient api;
  final Region region;

  @override
  State<MyBasketToday> createState() => _MyBasketTodayState();
}

class _MyBasketTodayState extends State<MyBasketToday> {
  static final _memo = <String, ({DateTime at, Future<Map<String, dynamic>> data})>{};

  final _mine = MyBasket.instance;
  Future<Map<String, dynamic>>? _future;

  @override
  void initState() {
    super.initState();
    _mine.addListener(_changed);
    _mine.load().then((_) => _changed());
  }

  @override
  void dispose() {
    _mine.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<Map<String, dynamic>> _fetch() {
    final key = '${widget.region.code}/${widget.region.sgg ?? ''}';
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at).inMinutes < 10) return hit.data;
    final f = widget.api.market(sido: widget.region.code, sgg: widget.region.sgg);
    _memo[key] = (at: DateTime.now(), data: f);
    f.catchError((_) {
      _memo.remove(key); // 실패는 기억하지 않음
      return <String, dynamic>{};
    });
    return f;
  }

  @override
  Widget build(BuildContext context) {
    if (_mine.isEmpty) return const SizedBox.shrink();
    _future ??= _fetch();
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final data = snap.data;
        final catalog = (data?['catalog'] as List?)?.cast<Map<String, dynamic>>();
        if (snap.connectionState != ConnectionState.done || catalog == null) return const SizedBox.shrink();

        final byName = {for (final e in catalog) e['name'] as String: e};
        final items = [for (final n in _mine.names) if (byName[n] != null) byName[n]!];
        if (items.isEmpty) return const SizedBox.shrink();

        // 많이 움직인 것부터(내린 것·오른 것 모두 알림 가치가 큼)
        double mag(Map<String, dynamic> e) => ((e['pct'] as num?) ?? 0).abs().toDouble();
        items.sort((a, b) => mag(b).compareTo(mag(a)));

        final asOf = DateTime.tryParse((data?['as_of'] as String?) ?? '');
        return ListSection(
          title: '내 장바구니',
          trailing: asOf == null ? '지난주 대비' : '${asOf.month}/${asOf.day} 기준 · 지난주 대비',
          children: [
            ExpandableList(children: [for (final e in items) _line(e)]),
          ],
        );
      },
    );
  }

  Widget _line(Map<String, dynamic> it) {
    final change = (it['change'] as String?) ?? 'flat';
    final pct = it['pct'] as num?;
    final series = (it['series'] as List?)?.map((e) => (e as num).toDouble()).toList();
    return ListLine(
      name: it['name'] as String,
      sub: it['sub'] as String?,
      middle: series == null ? null : MiniSpark(series: series, color: changeColor(change)),
      value: '${formatNumber(it['price'] as num)}원',
      valueSub: pct == null ? null : changeLabel(change, pct: pct),
      valueSubColor: changeColor(change),
    );
  }
}
