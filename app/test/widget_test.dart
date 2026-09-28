import 'package:flutter_test/flutter_test.dart';

import 'package:dailycut/main.dart';

void main() {
  testWidgets('탭바에 다섯 섹션이 다 보임', (WidgetTester tester) async {
    await tester.pumpWidget(const DailyCutApp());
    await tester.pump();

    for (final label in ['투데이', '시세', '문화', '머니', 'AI']) {
      expect(find.text(label), findsOneWidget);
    }
  });
}
