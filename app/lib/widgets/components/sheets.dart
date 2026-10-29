// 공용 부품 — 안내 시트(showNoteSheet)·ⓘ 버튼(InfoIconButton)·상세 시트 틀(SheetFrame)
// (2026-10-29: 1,787줄짜리 components.dart를 주제별로 나눔. 불러오는 쪽은 그대로 `widgets/components.dart` 하나만 import 하면 됨.)
import 'package:flutter/material.dart';

import '../../theme.dart';

/// 작은 ⓘ 안내 시트(2026-10-16): 출처·기준·설명 같은 부가 글을 본문 아래에 늘어놓지 않고 ⓘ를 누르면 보이게 함.
Future<void> showNoteSheet(BuildContext context, {required String title, required List<String> lines}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.background,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTheme.subheading),
            const SizedBox(height: 12),
            for (final l in lines) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(l, style: const TextStyle(fontSize: 13, height: 1.6))),
          ],
        ),
      ),
    ),
  );
}

/// 제목·캡션 옆에 붙이는 ⓘ 버튼(누르면 [showNoteSheet]).
class InfoIconButton extends StatelessWidget {
  const InfoIconButton({super.key, required this.title, required this.lines});

  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showNoteSheet(context, title: title, lines: lines),
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.fromLTRB(8, 4, 0, 4),
        child: Icon(Icons.info_outline, size: 15, color: AppColors.inkSoft),
      ),
    );
  }
}

/// 상세 시트의 공용 틀(2026-10-16): 안전 영역 + 스크롤 + 세리프 24 제목 + 13 회색 부제 + 내용. 혜택·장소·정부 지원·시장 상세가 같이 씀.
class SheetFrame extends StatelessWidget {
  const SheetFrame({super.key, required this.title, this.sub, required this.children, this.gapAfterHeader = 22, this.infoLines});

  final String title;
  final String? sub;
  final List<String>? infoLines; // 있으면 제목 오른쪽에 ⓘ(출처·기준 설명)
  final List<Widget> children;
  final double gapAfterHeader; // 제목 묶음과 내용 사이

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(child: Text(title, style: AppTheme.displaySerif(size: 24, fontWeight: FontWeight.w700))),
                if (infoLines != null) Padding(padding: const EdgeInsets.only(top: 6), child: InfoIconButton(title: '출처·안내', lines: infoLines!)),
              ],
            ),
            if (sub != null && sub!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(sub!, style: const TextStyle(fontSize: 13, color: AppColors.inkSoft)),
            ],
            SizedBox(height: gapAfterHeader),
            ...children,
          ],
        ),
      ),
    );
  }
}
