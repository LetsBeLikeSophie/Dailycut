import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../analytics.dart';
import '../api_client.dart';
import '../region.dart';
import '../theme.dart';
import 'components.dart';

/// 혜택 탭의 주거·금융 목록: 청약(청약홈), 공공임대(마이홈·LH), 서민 대출(서민금융진흥원).
/// 서버가 줄여서 준 항목({name, sub, tag, span, detail[[라벨,값]], url, link_label})을 한 모양으로 보여주고,
/// 누르면 상세 시트가 열림. 받는 동안은 자리를 잡고 "불러오는 중", 못 받으면 다시 시도 안내(예시 데이터 없음).
enum BenefitKind { apply, rent, loan }

class BenefitFeed extends StatefulWidget {
  const BenefitFeed({super.key, required this.api, required this.region, required this.kind});

  final ApiClient api;
  final Region region;
  final BenefitKind kind;

  // 같은 조건으로 받은(받는 중인) 요청은 10분 동안 다시 보내지 않음 — 구역을 오가도 바로 보이게.
  static final Map<String, ({DateTime at, Future<Map<String, dynamic>> future})> _memo = {};

  static Future<Map<String, dynamic>> fetch(ApiClient api, Region r, BenefitKind kind, String? usage) {
    final key = '${kind.name}/${r.code}/${r.sgg ?? ''}/${usage ?? ''}'; // usage는 쉼표로 이은 여러 개
    final hit = _memo[key];
    if (hit != null && DateTime.now().difference(hit.at).inMinutes < 10) return hit.future;
    final f = switch (kind) {
      BenefitKind.apply => api.benefitsHousing(kind: 'apply', sido: r.code, sgg: r.sgg),
      BenefitKind.rent => api.benefitsHousing(kind: 'rent', sido: r.code, sgg: r.sgg),
      BenefitKind.loan => api.benefitsLoans(usage: usage, sido: r.code),
    };
    _memo[key] = (at: DateTime.now(), future: f);
    f.catchError((_) {
      _memo.remove(key);
      return <String, dynamic>{};
    });
    return f;
  }

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
          return _message(const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.ink)),
              SizedBox(height: 14),
              Text('불러오는 중이에요', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            ],
          ));
        }
        final items = (d['items'] as List).cast<Map<String, dynamic>>();
        final usages = ((d['usages'] as List?) ?? const []).cast<String>();
        return ListSection(
          title: _title,
          trailing: widget.kind == BenefitKind.loan ? null : '${d['total']}건',
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
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('지금 접수할 수 있는 공고가 없어요.', style: TextStyle(fontSize: 13, color: AppColors.inkSoft))),
              ),
            ExpandableList(
              key: ValueKey('${widget.kind.name}/${_usage ?? ''}'),
              children: [
                for (final it in items)
                  ListLine(
                    name: it['name'] as String,
                    sub: it['sub'] as String?,
                    value: (it['tag'] as String?)?.isEmpty ?? true ? null : it['tag'] as String,
                    valueSub: (it['span'] as String?)?.isEmpty ?? true ? null : it['span'] as String,
                    onTap: () => showItemSheet(context, it, 'benefit-${widget.kind.name}'),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Text(
                '${d['region'] != null ? '${d['region']} 기준 · ' : ''}$_footnote',
                style: const TextStyle(fontSize: 11, color: AppColors.inkSoft, height: 1.6),
              ),
            ),
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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item['name'] as String, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(item['sub'] as String? ?? '', style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            const SizedBox(height: 22),
            Container(height: 1, color: AppColors.ink),
            for (final r in rows)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.hair))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 88, child: Text(r[0], style: const TextStyle(fontSize: 13, color: AppColors.inkSoft))),
                    Expanded(child: Text(r[1], style: const TextStyle(fontSize: 15, height: 1.5))),
                  ],
                ),
              ),
            if (url != null && url.isNotEmpty) ...[
              const SizedBox(height: 26),
              GestureDetector(
                onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(8)),
                  child: Text(item['link_label'] as String? ?? '자세히 보기', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
