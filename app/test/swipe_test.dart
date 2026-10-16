import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dailycut/widgets/swipe.dart';

void main() {
  Widget app(void Function(int) outer, void Function(int) inner) => MaterialApp(
        home: Scaffold(
          body: SwipeDetector(
            onSwipe: outer,
            child: Column(
              children: [
                SwipeDetector(onSwipe: inner, child: Container(key: const Key('inner'), height: 120, color: Colors.red)),
                Expanded(child: Container(key: const Key('outer'), color: Colors.blue)),
              ],
            ),
          ),
        ),
      );

  testWidgets('가장 안쪽이 먼저 받고, 안쪽 밖에서는 바깥이 받음', (tester) async {
    var outer = 0, inner = 0;
    await tester.pumpWidget(app((s) => outer += s, (s) => inner += s));

    await tester.fling(find.byKey(const Key('inner')), const Offset(-300, 0), 1500); // 왼쪽으로 밀기 = 다음(+1)
    await tester.pumpAndSettle();
    expect(inner, 1);
    expect(outer, 0);

    await tester.fling(find.byKey(const Key('outer')), const Offset(300, 0), 1500); // 오른쪽으로 밀기 = 이전(-1)
    await tester.pumpAndSettle();
    expect(inner, 1);
    expect(outer, -1);
  });

  testWidgets('천천히 끌다 놓거나 마우스로 끌면 무시', (tester) async {
    var outer = 0, inner = 0;
    await tester.pumpWidget(app((s) => outer += s, (s) => inner += s));

    // 속도가 낮으면(멈췄다가 놓기) 인정 안 함
    final slow = await tester.startGesture(tester.getCenter(find.byKey(const Key('outer'))));
    await slow.moveBy(const Offset(-120, 0));
    await tester.pump(const Duration(milliseconds: 600));
    await slow.up();
    await tester.pumpAndSettle();
    expect(outer, 0);

    // 마우스는 받지 않음
    final mouse = await tester.startGesture(tester.getCenter(find.byKey(const Key('outer'))), kind: PointerDeviceKind.mouse);
    await mouse.moveBy(const Offset(-300, 0));
    await mouse.up();
    await tester.pumpAndSettle();
    expect(outer, 0);
    expect(inner, 0);
  });
}
