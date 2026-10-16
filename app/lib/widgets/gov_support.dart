import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';
import 'support_profile.dart';

/// 머니 탭 "정부 지원·혜택"(행정안전부 공공서비스 정보). 지역으로 거르고, 원하면 "내 조건"(나이·성별·소득·해당 특성)으로 더 좁힘.
/// 예시 데이터는 보여주지 않음 — 못 받았으면 못 받았다고 알림.
class GovSupportSection extends StatefulWidget {
  const GovSupportSection({super.key, required this.api});

  final ApiClient api;

  // 같은 조건으로 이미 받은(받는 중인) 요청은 다시 보내지 않음 — 구역 전환·탭 이동 때 빈 화면 없이 바로 보이게.
  static final Map<String, ({DateTime at, Future<Map<String, dynamic>> future})> _memo = {};

  static Future<Map<String, dynamic>> fetch(ApiClient api, Region region, String scope, SupportProfile prof) {
    final body = prof.isSet ? prof.toRequest() : null;
    final key = '${region.code}/${region.sgg ?? ''}/$scope/${body == null ? '' : jsonEncode(body)}';
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at).inMinutes < 10) return hit.future;
    final f = body == null
        ? api.support(sido: region.code, sgg: region.sgg, scope: scope)
        : api.supportSearch(sido: region.code, sgg: region.sgg, scope: scope, profile: body);
    _memo[key] = (at: DateTime.now(), future: f);
    f.catchError((_) {
      _memo.remove(key); // 실패는 기억하지 않음(다시 시도할 수 있게)
      return <String, dynamic>{};
    });
    return f;
  }

  /// 머니 탭이 열릴 때 미리 받아 둠(혜택 구역을 눌렀을 때 바로 보이게).
  static Future<void> prefetch(ApiClient api) async {
    await SupportProfile.instance.load();
    try {
      await fetch(api, RegionStore.instance.current, 'all', SupportProfile.instance);
    } catch (_) {}
  }

  @override
  State<GovSupportSection> createState() => _GovSupportSectionState();
}

class _GovSupportSectionState extends State<GovSupportSection> {
  String _scope = 'all'; // all | local | central
  late Future<Map<String, dynamic>> _future = _load();

  Region get _region => RegionStore.instance.current;
  SupportProfile get _prof => SupportProfile.instance;

  Future<Map<String, dynamic>> _load() => GovSupportSection.fetch(widget.api, _region, _scope, _prof);

  @override
  void initState() {
    super.initState();
    RegionStore.instance.addListener(_reload); // 지역을 바꾸면 그 지역 기준으로 다시 받음
    _prof.addListener(_reload); // "내 조건"을 바꾸면 그 조건으로 다시 받음
    _prof.load().then((_) {
      if (mounted && _prof.isSet) _reload(); // 저장된 조건이 있으면 처음부터 적용
    });
  }

  @override
  void dispose() {
    RegionStore.instance.removeListener(_reload);
    _prof.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  Widget _message(Widget child, {VoidCallback? onTap}) => ListSection(
        title: '정부 지원·혜택',
        children: [
          GestureDetector(
            onTap: onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(padding: const EdgeInsets.symmetric(vertical: 56), child: Center(child: child)),
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (snap.hasError || (d != null && d['live'] != true)) {
          return _message(
            const Text('지원 정보를 불러오지 못했어요. 눌러서 다시 시도', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            onTap: _reload,
          );
        }
        if (d == null) {
          // 처음 받는 중: 빈 화면 대신 자리를 잡고 불러오는 중임을 보여줌
          return _message(
            const LoadingNote(label: '지원 정보를 불러오는 중이에요'),
          );
        }
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        final set = _prof.isSet;
        return ListSection(
          title: '정부 지원·혜택',
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoIconButton(title: '안내', lines: ['받을 수 있는지는 대상·조건을 확인하고 해당 기관에 문의해 주세요.']),
              GestureDetector(
                onTap: () => showSupportProfileSheet(context),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text.rich(
                    const TextSpan(children: [
                      WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.tune, size: 15)),
                      TextSpan(text: ' 내 조건'),
                    ]),
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: set ? AppColors.ink : AppColors.inkSoft),
                  ),
                ),
              ),
            ],
          ),
          children: [
            const SizedBox(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (k, label) in const [('all', '전체'), ('local', '우리 지역'), ('central', '중앙부처')])
                  PillChip(
                    label: label,
                    selected: _scope == k,
                    onTap: () {
                      _scope = k;
                      _reload();
                    },
                  ),
              ],
            ),
            if (set) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(child: Text(_prof.summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                  const SizedBox(width: 10),
                  Text('${d['total']}개', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                  GestureDetector(
                    onTap: () => _prof.clear(),
                    behavior: HitTestBehavior.opaque,
                    child: const Padding(
                      padding: EdgeInsets.only(left: 14, top: 4, bottom: 4),
                      child: Text('지우기', style: TextStyle(fontSize: 13, color: AppColors.inkSoft, decoration: TextDecoration.underline)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.hair),
            if (items.isEmpty)
              const EmptyNote('맞는 지원이 없어요. 조건을 조금 넓혀 보세요.', vertical: 40),
            ExpandableList(
              key: ValueKey('$_scope/${_prof.summary}'),
              children: [for (final it in items) _line(context, it)],
            ),
          ],
        );
      },
    );
  }

  Widget _line(BuildContext context, Map<String, dynamic> it) {
    final summary = (it['summary'] as String?)?.isNotEmpty == true ? it['summary'] as String : (it['support'] as String? ?? '');
    return ListLine(
      name: it['name'] as String,
      sub: [if ((it['org'] as String).isNotEmpty) it['org'], if (summary.isNotEmpty) summary].join(' · '),
      value: it['dday'] == null ? null : (it['dday'] == 0 ? '오늘 마감' : '${it['dday']}일 남음'), // 신청기한이 한 달 안일 때만
      valueWeight: FontWeight.w700,
      onTap: () => showSupportSheet(context, it),
    );
  }
}

Future<void> showSupportSheet(BuildContext context, Map<String, dynamic> it) {
  Analytics.instance.track('life_open', 'support');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
    builder: (_) => _SupportSheet(item: it),
  );
}

class _SupportSheet extends StatelessWidget {
  const _SupportSheet({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    Widget block(String title, String? body) {
      if (body == null || body.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.subheading),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(fontSize: 16, height: 1.6)),
          ],
        ),
      );
    }

    final url = item['url'] as String?;
    return SheetFrame(
      title: item['name'] as String,
      sub: [item['org'], item['field']].where((e) => (e as String?)?.isNotEmpty ?? false).join(' · '),
      gapAfterHeader: 0,
      infoLines: const ['행정안전부 대한민국 공공서비스(혜택) 정보'],
      children: [
            block('지원 내용', item['support'] as String?),
            block('지원 대상', item['target'] as String?),
            block('신청 방법', item['method'] as String?),
            block('신청 기한', item['deadline'] as String?),
            block('문의', item['phone'] as String?),
            if (url != null && url.isNotEmpty) ...[
              const SizedBox(height: 28),
              ActionButton(label: '정부24에서 자세히 보기', onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
            ],
      ],
    );
  }
}
