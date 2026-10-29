// 공용 부품 — 숫자 서식·오름/내림 색/문구·개발용 표시(StubMark)
// (2026-10-29: 1,787줄짜리 components.dart를 주제별로 나눔. 불러오는 쪽은 그대로 `widgets/components.dart` 하나만 import 하면 됨.)
import 'package:flutter/material.dart';

import '../../theme.dart';

/// 개발용 임시 표시: 실데이터가 아닌(스텁/예시) 영역에 분홍 배경 + 빨간 왼쪽 선을 깔아서
/// 눈으로 구분함. 실데이터가 다 붙으면 false로 바꾸거나 이 표시를 지우면 됨.
// 2026-10-14: 배포본에선 끔(예시 구간은 화면에서 아예 뺐음). 개발 때만 `--dart-define=SHOW_STUB_MARKS=true`.
const kShowStubMarks = bool.fromEnvironment('SHOW_STUB_MARKS');

class StubMark extends StatelessWidget {
  const StubMark({super.key, required this.stub, required this.child});

  final bool stub;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!stub || !kShowStubMarks) return child;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: const BoxDecoration(
        color: Color(0xFFFFF0F0),
        border: Border(left: BorderSide(color: Color(0xFFE57373), width: 3)),
      ),
      child: child,
    );
  }
}

String formatNumber(num v, {int decimals = 0}) {
  final s = v.toStringAsFixed(decimals);
  final parts = s.split('.');
  final intPart = parts[0].replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (m) => ',',
  );
  return parts.length > 1 ? '$intPart.${parts[1]}' : intPart;
}

Color changeColor(String change) => switch (change) {
  'up' => AppColors.up,
  'down' => AppColors.down,
  _ => AppColors.inkSoft,
};

/// 작은 그래프 색: 오르면 빨강·내리면 파랑, **비슷하면 옅은 회색**(2026-10-17: 진한 회색 + "－ 0.4%"가 마이너스처럼 읽혀 헷갈렸음).
Color sparkColor(String change) => switch (change) {
  'up' => AppColors.up,
  'down' => AppColors.down,
  _ => const Color(0xFFC9C9C9),
};

/// 변동 표시. 0.5% 이내(change == 'flat')면 부호 없는 숫자 대신 **"비슷해요"**(2026-10-17: "－ 0.4%"가 마이너스로 보임).
String changeLabel(String change, {num? pct}) {
  if (change == 'flat') return '비슷해요';
  final arrow = change == 'up' ? '▲' : '▼';
  if (pct == null) return arrow;
  return '$arrow ${pct.abs() == pct.abs().roundToDouble() ? pct.abs().round() : pct.abs()}%';
}
