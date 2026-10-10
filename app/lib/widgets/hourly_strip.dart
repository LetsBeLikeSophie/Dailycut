import 'package:flutter/material.dart';

import '../theme.dart';

/// 시간대별 날씨 가로 스크롤. 오늘 0시~모레 0시(1시간 간격)를 한 줄에 두고, 열 때 "지금" 칸이
/// 왼쪽 가까이에 오도록 스크롤해둠 — 왼쪽으로 밀면 오늘 지난 시각, 오른쪽으로 밀면 내일·모레.
/// 날짜가 바뀌는 칸(0시)과 첫 칸 위에 "오늘/내일/모레"를 붙이고, 지난 시각은 흐리게(예보값) 보여줌.
class HourlyStrip extends StatefulWidget {
  const HourlyStrip({super.key, required this.hours});

  final List<Map<String, dynamic>> hours;

  @override
  State<HourlyStrip> createState() => _HourlyStripState();
}

class _HourlyStripState extends State<HourlyStrip> {
  static const _cellW = 56.0;
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    final nowIndex = widget.hours.indexWhere((h) => h['is_now'] == true);
    if (nowIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_controller.hasClients) return;
        final target = (nowIndex * _cellW - 16).clamp(0.0, _controller.position.maxScrollExtent);
        _controller.jumpTo(target);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _dayLabel(Map<String, dynamic> h, int i) {
    final date = h['date'] as String?;
    if (date == null) return null;
    if (i != 0 && h['hour'] != 0) return null; // 첫 칸과 0시 칸에만
    final d = DateTime.tryParse(date);
    if (d == null) return null;
    final today = DateTime.now();
    final diff = DateTime(d.year, d.month, d.day).difference(DateTime(today.year, today.month, today.day)).inDays;
    return switch (diff) { 0 => '오늘', 1 => '내일', 2 => '모레', _ => '${d.month}/${d.day}' };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 92,
          child: ListView.builder(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            itemCount: widget.hours.length,
            itemExtent: _cellW,
            itemBuilder: (context, i) {
              final h = widget.hours[i];
              final isNow = h['is_now'] == true;
              final isPast = h['is_past'] == true;
              final pop = (h['pop'] as num?)?.toInt() ?? 0;
              final day = _dayLabel(h, i);
              return Opacity(
                opacity: isPast ? 0.45 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 16,
                      child: Text(
                        day ?? '',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.ink),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isNow ? AppColors.ink : null,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        isNow ? '지금' : (h['time'] as String),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isNow ? FontWeight.w700 : FontWeight.w400,
                          color: isNow ? Colors.white : AppColors.inkSoft,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${h['temp']}°',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isNow ? FontWeight.w700 : FontWeight.w500,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      pop > 0 ? '$pop%' : '',
                      style: const TextStyle(fontSize: 11, color: AppColors.down),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        if (widget.hours.any((h) => h['date'] != null))
          const Text(
            '오늘 0시 ~ 모레 0시 · 옆으로 밀어보세요 · 지난 시각은 예보값이에요',
            style: TextStyle(fontSize: 11, color: AppColors.inkSoft),
          ),
      ],
    );
  }
}
