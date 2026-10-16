import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dailycut/widgets/dog_icon.dart';

/// 개 아이콘이 의도한 모양인지 눈으로 보려고 큰 그림으로 뽑음(`flutter test --update-goldens test/dog_golden_test.dart`).
void main() {
  testWidgets('개 아이콘 모양', (tester) async {
    await tester.binding.setSurfaceSize(const Size(560, 220));
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Colors.white,
          body: RepaintBoundary(
            key: const Key('dogs'),
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    for (final s in [DogSize.small, DogSize.medium, DogSize.large]) ...[
                      DogIcon(size: s, color: const Color(0xFF2E8B57), height: 90),
                      const SizedBox(width: 24),
                    ],
                  ]),
                  const SizedBox(height: 14),
                  Row(children: [
                    DogIcon(size: DogSize.all, color: const Color(0xFF2E8B57), height: 60),
                    const SizedBox(width: 30),
                    for (final s in [DogSize.small, DogSize.medium, DogSize.large, DogSize.all]) ...[
                      DogIcon(size: s, color: const Color(0xFF2E8B57), height: 18),
                      const SizedBox(width: 12),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await expectLater(find.byKey(const Key('dogs')), matchesGoldenFile('goldens/dogs.png'));
  });
}
