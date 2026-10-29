// 공용 부품 — 선택·버튼(SegmentToggle·CheckToggle·PillChip·ActionButton)
// (2026-10-29: 1,787줄짜리 components.dart를 주제별로 나눔. 불러오는 쪽은 그대로 `widgets/components.dart` 하나만 import 하면 됨.)
import 'package:flutter/material.dart';

import '../../theme.dart';

/// 화면 안 큰 구역 전환(예: 문화 탭의 행사·전시 / 영화 / 음악): 상자 없이 글자만, 고른 것은 굵게 + 밑줄.
/// 앱의 여백 많은 편집체 분위기에 맞춰 버튼 느낌을 뺌.
class SegmentToggle extends StatefulWidget {
  const SegmentToggle({super.key, required this.labels, required this.index, required this.onChanged});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  State<SegmentToggle> createState() => _SegmentToggleState();
}

class _SegmentToggleState extends State<SegmentToggle> {
  final _c = ScrollController();
  bool _more = false; // 오른쪽에 더 있음
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _c.addListener(_check);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _check() {
    if (!_c.hasClients) return;
    final more = _c.position.maxScrollExtent - _c.offset > 4;
    if (more != _more && mounted) setState(() => _more = more);
  }

  @override
  Widget build(BuildContext context) {
    final labels = widget.labels;
    final index = widget.index;
    if (!_checked) {
      _checked = true; // 처음 그린 뒤 한 번만 확인(이후엔 스크롤할 때 listener가 확인)
      WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    }
    // 2026-10-16: 장소 탭처럼 구분이 6개면 폭을 넘어서 가로로 밀어 볼 수 있게 하고, 더 있다는 걸 오른쪽 끝 흐림+화살표로 알림(칸이 적으면 그대로 한 줄)
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Stack(
        children: [
          SingleChildScrollView(
            controller: _c,
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++) ...[
                  GestureDetector(
                    onTap: () => widget.onChanged(i),
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 3),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: i == index ? AppColors.ink : Colors.transparent, width: 2)),
                        ),
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: i == index ? FontWeight.w700 : FontWeight.w400,
                            color: i == index ? AppColors.ink : AppColors.inkSoft,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (i < labels.length - 1) const SizedBox(width: 26),
                ],
              ],
            ),
          ),
          if (_more)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 44,
                  alignment: Alignment.centerRight,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0x00FFFFFF), AppColors.background], stops: [0, 0.7]),
                  ),
                  child: const Icon(Icons.chevron_right, size: 18, color: AppColors.inkSoft),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 앱 공용 알약 칩(고르기/걸러 보기용). 선택되면 검정 바탕. 2026-10-16: 화면마다 따로 만들던 칩(_Pill·_Chip·_MiniPill)을 이것 하나로 합침.
///  - dotColor: 앞에 붙는 색 점(달력의 종류 칩) / large: 16글자·넉넉한 칩(지역 고르기) / emphasized: 선택 안 됐어도 테두리·글씨 진하게
/// 체크 모양 켜기/끄기 한 줄(2026-10-24, 장보기 시세의 `_FilterToggle`을 공용으로 뺌): ☐ 제철만 7.
/// 출처 시트의 "익명 통계 보내기"는 Material 기본 스위치(회색 트랙)가 앱 모양과 안 맞아서 이걸로 바꿈.
/// 알약 칩(PillChip)은 "여러 개 중 고르기", 이건 "하나를 켜고 끄기"에 씀.
class CheckToggle extends StatelessWidget {
  const CheckToggle({super.key, required this.label, required this.on, required this.onTap, this.count, this.icon, this.iconColor});

  final String label;
  final bool on;
  final VoidCallback onTap;
  final int? count; // 있으면 라벨 뒤에 작은 숫자
  final IconData? icon;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(on ? Icons.check_box : Icons.check_box_outline_blank, size: 20, color: AppColors.ink),
            const SizedBox(width: 6),
            if (icon != null) ...[Icon(icon, size: 15, color: iconColor), const SizedBox(width: 3)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w400)),
            if (count != null) ...[const SizedBox(width: 5), Text('$count', style: const TextStyle(fontSize: 11, color: AppColors.inkSoft))],
          ],
        ),
      ),
    );
  }
}

class PillChip extends StatelessWidget {
  const PillChip({super.key, required this.label, required this.selected, required this.onTap, this.vertical = 8, this.dotColor, this.large = false, this.emphasized = false});

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double vertical;
  final Color? dotColor;
  final bool large;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final strong = selected || emphasized;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: large ? 9 : vertical),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.background,
          border: Border.all(color: strong ? AppColors.ink : AppColors.line),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[Container(width: 7, height: 7, decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor)), const SizedBox(width: 6)],
            Text(
              label,
              style: TextStyle(fontSize: large ? 16 : 13, fontWeight: strong ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppColors.ink),
            ),
          ],
        ),
      ),
    );
  }
}

/// 앱 공용 가로 버튼(2026-10-16, 8개 파일에서 따로 그리던 윤곽선 버튼을 합침). 기본은 윤곽선, filled는 검정 바탕. 라벨은 13 굵게.
class ActionButton extends StatelessWidget {
  const ActionButton({super.key, required this.label, required this.onTap, this.filled = false, this.icon, this.expand = true, this.vertical = 14});

  final String label;
  final VoidCallback onTap;
  final bool filled;
  final IconData? icon;
  final bool expand; // false면 글자 폭만큼(예: 히어로 안의 작은 버튼)
  final double vertical;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Colors.white : AppColors.ink;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: EdgeInsets.symmetric(vertical: vertical, horizontal: expand ? 0 : 16),
        alignment: expand ? Alignment.center : null,
        decoration: BoxDecoration(color: filled ? AppColors.ink : null, border: Border.all(color: AppColors.ink), borderRadius: BorderRadius.circular(8)),
        child: Row(
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[Icon(icon, size: 18, color: fg), const SizedBox(width: 8)],
            Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: fg)),
          ],
        ),
      ),
    );
  }
}
