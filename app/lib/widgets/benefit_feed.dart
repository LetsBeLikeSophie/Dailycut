import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'ad_slot.dart';
import 'components.dart';
import 'map_links.dart';

/// 혜택 탭의 주거·금융 목록: 청약(청약홈), 공공임대(마이홈·LH), 서민 대출(서민금융진흥원).
/// 서버가 줄여서 준 항목({name, sub, tag, span, detail[[라벨,값]], url, link_label})을 한 모양으로 보여주고,
/// 누르면 상세 시트가 열림. 받는 동안은 자리를 잡고 "불러오는 중", 못 받으면 다시 시도 안내(예시 데이터 없음).
enum BenefitKind { apply, rent, loan }

class BenefitFeed extends StatefulWidget {
  const BenefitFeed({super.key, required this.api, required this.region, required this.kind});

  final ApiClient api;
  final Region region;
  final BenefitKind kind;

  // 같은 조건의 요청은 ApiClient가 10분 동안 다시 보내지 않음(구역을 오가도 바로 보임). usage는 쉼표로 이은 여러 개.
  static Future<Map<String, dynamic>> fetch(ApiClient api, Region r, BenefitKind kind, String? usage) => switch (kind) {
        BenefitKind.apply => api.benefitsHousing(kind: 'apply', sido: r.code, sgg: r.sgg),
        BenefitKind.rent => api.benefitsHousing(kind: 'rent', sido: r.code, sgg: r.sgg),
        BenefitKind.loan => api.benefitsLoans(usage: usage, sido: r.code),
      };

  @override
  State<BenefitFeed> createState() => _BenefitFeedState();
}

class _BenefitFeedState extends State<BenefitFeed> {
  // 대출 용도 칩: 여러 개를 고를 수 있고(하나라도 맞으면), 다시 누르면 풀림. 비어 있으면 전체.
  final Set<String> _usages = {};
  late Future<Map<String, dynamic>> _future = _load();

  String? get _usage => _usages.isEmpty ? null : (_usages.toList()..sort()).join(',');

  Future<Map<String, dynamic>> _load() => BenefitFeed.fetch(widget.api, widget.region, widget.kind, _usage);

  void _reload() {
    if (mounted) setState(() => _future = _load());
  }

  String get _title => switch (widget.kind) {
        BenefitKind.apply => '접수 중·예정 청약',
        BenefitKind.rent => '공공임대 모집공고',
        BenefitKind.loan => '서민금융 대출상품',
      };

  String get _footnote => switch (widget.kind) {
        BenefitKind.apply => '접수 기간과 자격은 공고문이 기준이에요. 청약홈에서 꼭 확인해 주세요.',
        BenefitKind.rent => '접수 기간과 자격은 공고문이 기준이에요. 공고 페이지에서 꼭 확인해 주세요.',
        BenefitKind.loan => '금리·한도는 대출 심사 결과에 따라 달라질 수 있어요. 취급 기관에 문의해 주세요.',
      };

  Widget _message(Widget child, {VoidCallback? onTap}) => ListSection(
        title: _title,
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
          return _message(const Text('목록을 불러오지 못했어요. 눌러서 다시 시도', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)), onTap: _reload);
        }
        if (d == null) {
          return _message(const LoadingNote());
        }
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        final usages = ((d['usages'] as List?) ?? const []).cast<String>();
        return ListSection(
          title: _title,
          trailing: widget.kind == BenefitKind.loan ? null : '${d['total']}건',
          info: InfoIconButton(title: '안내', lines: [_footnote]),
          children: [
            if (widget.kind == BenefitKind.loan && usages.isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  PillChip(
                    label: '전체',
                    selected: _usages.isEmpty,
                    onTap: () {
                      _usages.clear();
                      _reload();
                    },
                  ),
                  for (final u in usages)
                    PillChip(
                      label: u,
                      selected: _usages.contains(u),
                      onTap: () {
                        _usages.contains(u) ? _usages.remove(u) : _usages.add(u);
                        _reload();
                      },
                    ),
                ],
              ),
            ],
            if (d['scope_note'] != null)
              Padding(padding: const EdgeInsets.only(top: 12), child: Text(d['scope_note'] as String, style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6))),
            const SizedBox(height: 14),
            Container(height: 1, color: AppColors.hair),
            if (items.isEmpty)
              const EmptyNote('지금 접수할 수 있는 공고가 없어요.', vertical: 40),
            ExpandableList(
              key: ValueKey('${widget.kind.name}/${_usage ?? ''}'),
              // 광고는 공고 맨 위 3개 다음에 한 번(2026-10-19). 광고도 목록 한 칸이라 보이는 개수(limit)에 1을 더함.
              limit: kAdsEnabled && items.length > 3 ? kListLimit + 1 : kListLimit,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  ListLine(
                    name: items[i]['name'] as String,
                    sub: items[i]['sub'] as String?,
                    value: (items[i]['tag'] as String?)?.isEmpty ?? true ? null : items[i]['tag'] as String,
                    valueSub: (items[i]['span'] as String?)?.isEmpty ?? true ? null : items[i]['span'] as String,
                    onTap: () => showItemSheet(context, items[i], 'benefit-${widget.kind.name}'),
                  ),
                  if (kAdsEnabled && i == 2) const AdSlot(),
                ],
              ],
            ),
            // 공고가 3개 이하면 목록 끝에
            if (kAdsEnabled && items.length <= 3) const AdSlot(),
          ],
        );
      },
    );
  }
}

/// 목록 항목({name, sub, detail[[라벨,값]], url, link_label}) 상세 시트 — 혜택·나들이 목록이 같이 씀. tag는 통계용 짧은 이름.
Future<void> showItemSheet(BuildContext context, Map<String, dynamic> it, String tag) {
  Analytics.instance.track('life_open', tag);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
    builder: (_) => _BenefitSheet(item: it),
  );
}

class _BenefitSheet extends StatelessWidget {
  const _BenefitSheet({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final rows = ((item['detail'] as List?) ?? const []).map((e) => (e as List).cast<String>()).toList();
    final url = item['url'] as String?;
    final pin = item['pin'] as Map<String, dynamic>?; // 지도 앱으로 보낼 재료(장소 목록)
    final hasUrl = url != null && url.isNotEmpty;
    return SheetFrame(
      title: item['name'] as String,
      sub: item['sub'] as String?,
      children: [
            Container(height: 1, color: AppColors.ink),
            for (final r in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hair))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 88, child: Text(r[0], style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                    Expanded(child: Text(r[1], style: const TextStyle(fontSize: 16, height: 1.5))),
                  ],
                ),
              ),
            if (hasUrl) ...[
              const SizedBox(height: 26),
              ActionButton(label: item['link_label'] as String? ?? '자세히 보기', onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
            ],
            if (pin != null) ...[
              SizedBox(height: hasUrl ? 10 : 26),
              if (hasUrl)
                GestureDetector(
                  onTap: () => openMapChooser(context, pin),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 10),
                    child: Center(child: Text('지도에서 보기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, decoration: TextDecoration.underline))),
                  ),
                )
              else
                ActionButton(label: '지도에서 보기', onTap: () => openMapChooser(context, pin)),
            ],
      ],
    );
  }
}
