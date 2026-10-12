import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';

/// 머니 탭 "정부 지원·혜택"(행정안전부 공공서비스 정보). 선택한 지역만으로 걸러 보여주고 개인 조건은 받지 않음.
/// 서버가 아직 데이터를 못 받았으면(키 승인 전 등) 섹션 전체를 숨김 — 예시 데이터는 보여주지 않음.
class GovSupportSection extends StatefulWidget {
  const GovSupportSection({super.key, required this.api});

  final ApiClient api;

  @override
  State<GovSupportSection> createState() => _GovSupportSectionState();
}

class _GovSupportSectionState extends State<GovSupportSection> {
  String _scope = 'all'; // all | local | central
  late Future<Map<String, dynamic>> _future = _load();

  Region get _region => RegionStore.instance.current;

  Future<Map<String, dynamic>> _load() => widget.api.support(sido: _region.code, sgg: _region.sgg, scope: _scope);

  @override
  void initState() {
    super.initState();
    RegionStore.instance.addListener(_regionChanged); // 지역을 바꾸면 그 지역 기준으로 다시 받음
  }

  @override
  void dispose() {
    RegionStore.instance.removeListener(_regionChanged);
    super.dispose();
  }

  void _regionChanged() {
    if (mounted) setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        final d = snap.data;
        if (d == null || d['live'] != true) return const SizedBox.shrink();
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        final regionName = (d['region'] as String?) ?? _region.label;
        return ListSection(
          title: '정부 지원·혜택',
          trailing: '$regionName 기준',
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (k, label) in const [('all', '전체'), ('local', '우리 지역'), ('central', '중앙부처')])
                    GestureDetector(
                      onTap: () => setState(() {
                        _scope = k;
                        _future = _load();
                      }),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: _scope == k ? AppColors.ink : AppColors.background,
                          border: Border.all(color: _scope == k ? AppColors.ink : AppColors.line),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: _scope == k ? FontWeight.w700 : FontWeight.w500, color: _scope == k ? Colors.white : AppColors.ink)),
                      ),
                    ),
                ],
              ),
            ),
            Container(height: 1, color: AppColors.hair),
            if (items.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('해당하는 지원이 없어요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft))),
            ExpandableList(
              key: ValueKey(_scope),
              children: [for (final it in items) _line(context, it)],
            ),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('받을 수 있는지는 대상·조건을 확인하고 해당 기관에 문의해 주세요.', style: TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6)),
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
        padding: const EdgeInsets.only(top: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.subheading),
            const SizedBox(height: 6),
            Text(body, style: const TextStyle(fontSize: 15, height: 1.6)),
          ],
        ),
      );
    }

    final url = item['url'] as String?;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['name'] as String, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text([item['org'], item['field']].where((e) => (e as String?)?.isNotEmpty ?? false).join(' · '), style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            block('지원 내용', item['support'] as String?),
            block('지원 대상', item['target'] as String?),
            block('신청 방법', item['method'] as String?),
            block('신청 기한', item['deadline'] as String?),
            block('문의', item['phone'] as String?),
            if (url != null && url.isNotEmpty) ...[
              const SizedBox(height: 22),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(8)),
                  child: const Text('정부24에서 자세히 보기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text('출처: 행정안전부 대한민국 공공서비스(혜택) 정보', style: TextStyle(fontSize: 11, color: AppColors.inkSoft)),
          ],
        ),
      ),
    );
  }
}
