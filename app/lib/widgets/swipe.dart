import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// 좌우로 밀기(스와이프) 감지(2026-10-16). 폰에서 옆으로 밀 때의 동작을 층마다 정함:
///  · 맨 바깥(RootShell) = 탭 이동(기본)  · 하위 구분이 있는 화면의 본문(SegmentedHost) = 구분 이동(양 끝에선 탭 이동으로 이어짐)
///  · 달력 = 달 이동. 같은 방향 감지가 겹치면 **가장 안쪽**이 이기므로(Flutter 제스처 규칙) 달력 위에선 달력만, 가로로 밀리는 칸
///    (시간대별 날씨·구분 버튼 줄·차트 끌기)은 그 칸이 먼저 반응함.
/// 터치(손가락·펜)만 받음 — 마우스로 끌 때 탭이 넘어가거나 글자 선택이 방해받지 않게.
/// [onSwipe]의 step: +1 = 왼쪽으로 밀었음(다음), -1 = 오른쪽으로 밀었음(이전).
class SwipeDetector extends StatelessWidget {
  const SwipeDetector({super.key, required this.child, required this.onSwipe, this.minVelocity = 300});

  final Widget child;
  final void Function(int step) onSwipe;
  final double minVelocity; // 이 속도(px/초) 넘게 밀어야 인정(천천히 끌다 놓은 건 무시)

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        HorizontalDragGestureRecognizer: GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
          () => HorizontalDragGestureRecognizer(supportedDevices: {PointerDeviceKind.touch, PointerDeviceKind.stylus}),
          (r) => r.onEnd = (d) {
            final v = d.primaryVelocity ?? 0;
            if (v < -minVelocity) {
              onSwipe(1);
            } else if (v > minVelocity) {
              onSwipe(-1);
            }
          },
        ),
      },
      child: child,
    );
  }
}
