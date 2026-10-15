import 'package:flutter/material.dart';

import '../analytics.dart';
import '../local_prefs.dart';
import '../theme.dart';
import 'components.dart';

IconData lifeIconFor(String key) => switch (key) {
      'laundry' => Icons.local_laundry_service_outlined,
      'carwash' => Icons.local_car_wash_outlined,
      'pm10' => Icons.air,
      'pm25' => Icons.grain,
      'uv' => Icons.brightness_high_outlined,
      'pollen' => Icons.local_florist_outlined,
      'sun' => Icons.wb_twilight,
      'term' => Icons.eco_outlined,
      'holiday' => Icons.event_available_outlined,
      'warning' => Icons.warning_amber_outlined,
      'quake' => Icons.vibration,
      _ => Icons.info_outline,
    };

Color levelColor(String? level) => switch (level) {
      'good' => const Color(0xFF2F9E44),
      'ok' => const Color(0xFFB98600),
      'bad' => AppColors.up,
      _ => AppColors.ink,
    };

/// 오늘의 생활 지수 한 줄: 아이콘 · 이름 · 값(좋음/보통/나쁨 색). 설명은 누르면 시트로.
Widget lifeIndexLine(BuildContext context, Map<String, dynamic> it, {bool stub = false}) {
  final key = it['key'] as String;
  return ListLine(
    stub: stub,
    leading: SizedBox(width: 28, child: Icon(lifeIconFor(key), size: 22, color: AppColors.ink)),
    name: it['title'] as String,
    value: it['value'] as String,
    valueColor: levelColor(it['level'] as String?),
    valueWeight: FontWeight.w400,
    onTap: () => showLifeSheet(context, it),
  );
}

Future<void> showLifeSheet(BuildContext context, Map<String, dynamic> it) {
  Analytics.instance.track('life_open', (it['key'] as String?) ?? '');
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
    builder: (_) => _LifeSheet(item: it),
  );
}

class _LifeSheet extends StatelessWidget {
  const _LifeSheet({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final key = item['key'] as String;
    final lines = ((item['detail'] as List?) ?? const []).cast<String>();
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(lifeIconFor(key), size: 26),
                const SizedBox(width: 10),
                Expanded(child: Text(item['title'] as String, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700))),
                InfoIconButton(title: '출처', lines: ['${item['source'] ?? ''}']),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              item['value'] as String,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: levelColor(item['level'] as String?)),
            ),
            const SizedBox(height: 20),
            Text('왜 이렇게 나왔나요', style: AppTheme.subheading),
            const SizedBox(height: 8),
            for (final l in lines.where((l) => !l.startsWith('판정 기준')))
              _detailLine(l),
            for (final l in lines.where((l) => l.startsWith('판정 기준')))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(l, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.6)),
              ),
          ],
        ),
      ),
    );
  }
}


/// "낮 평균 습도 58% (60% 아래면 잘 말라요)" → 앞은 본문, 괄호 안은 아래 줄에 작고 회색 부가설명으로.
Widget _detailLine(String line) {
  final m = RegExp(r'^(.*?)\s*\((.*)\)\s*$').firstMatch(line);
  final main = m?.group(1) ?? line;
  final sub = m?.group(2);
  return Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(main, style: const TextStyle(fontSize: 16, height: 1.5)),
        if (sub != null && sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(sub, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft, height: 1.5)),
          ),
      ],
    ),
  );
}


/// 오늘의 생활 지수 묶음: 숨긴 지수는 빼고 보여 주고, 아래 "지수 고르기"에서 보일 지수를 바꿈(기기에만 저장).
class LifeIndexSection extends StatefulWidget {
  const LifeIndexSection({super.key, required this.indexes, this.stub = false});

  final List<Map<String, dynamic>> indexes;
  final bool stub;

  @override
  State<LifeIndexSection> createState() => _LifeIndexSectionState();
}

class _LifeIndexSectionState extends State<LifeIndexSection> {
  static const _key = 'life_hidden';
  List<String> _hidden = const [];

  @override
  void initState() {
    super.initState();
    LocalPrefs.getList(_key).then((v) {
      if (mounted) setState(() => _hidden = v);
    });
  }

  Future<void> _edit() async {
    Analytics.instance.track('life_edit');
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.background,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('보일 생활 지수', style: AppTheme.subheading),
                const SizedBox(height: 4),
                const Text('눌러서 보이거나 숨길 수 있어요', style: TextStyle(fontSize: 13, color: AppColors.inkSoft)),
                const SizedBox(height: 16),
                // 2026-10-14: 스위치 대신 알약 칩 — 진한 칩 = 보임(앱의 다른 선택 칩과 같은 모양)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final it in widget.indexes)
                      PillChip(
                        label: it['title'] as String,
                        selected: !_hidden.contains(it['key']),
                        onTap: () {
                          final next = [..._hidden];
                          next.contains(it['key']) ? next.remove(it['key']) : next.add(it['key'] as String);
                          setState(() => _hidden = next);
                          setSheet(() {});
                          LocalPrefs.setList(_key, next);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shown = [for (final it in widget.indexes) if (!_hidden.contains(it['key'])) it];
    return ListSection(
      title: '오늘의 생활 지수',
      stub: widget.stub,
      // 보일 지수 고르기(정부 지원의 "내 조건"과 같은 모양의 글자 버튼)
      action: GestureDetector(
        onTap: _edit,
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: Text.rich(
            TextSpan(children: [
              WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.tune, size: 15)),
              TextSpan(text: ' 지수 고르기'),
            ]),
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.inkSoft),
          ),
        ),
      ),
      children: [for (final it in shown) lifeIndexLine(context, it)],
    );
  }
}
