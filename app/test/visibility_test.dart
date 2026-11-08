import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 광고 칸(ad_view_mobile.dart)이 "다른 탭이 앞에 있는지"를 Visibility.of로 판단함 — IndexedStack이 그 값을 정말 주는지(2026-11-08).
/// TickerMode는 IndexedStack이 끄지 않아서 예전 검사가 늘 "앞에 있음"으로 나왔음. 플러터를 올렸을 때 이 동작이 바뀌면 여기서 걸림.
void main() {
  testWidgets('IndexedStack 안에서 앞에 없는 칸은 Visibility.of가 false', (tester) async {
    final seen = <int, bool>{};
    Widget probe(int i) => Builder(builder: (context) {
          seen[i] = Visibility.of(context);
          return const SizedBox();
        });
    Widget app(int index) => Directionality(
          textDirection: TextDirection.ltr,
          child: IndexedStack(index: index, children: [probe(0), probe(1)]),
        );
    await tester.pumpWidget(app(0));
    expect(seen, {0: true, 1: false});
    await tester.pumpWidget(app(1));
    expect(seen, {0: false, 1: true});
  });

  testWidgets('TickerMode(enabled: false)면 안 보이는 탭의 애니메이션이 멈춤', (tester) async {
    late AnimationController c;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(
        enabled: false,
        child: _Host(onController: (x) => c = x),
      ),
    ));
    await tester.pump(const Duration(seconds: 2));
    expect(c.value, 0.0); // 멈춰 있음
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: TickerMode(enabled: true, child: _Host(onController: (x) => c = x)),
    ));
    await tester.pump(const Duration(milliseconds: 500));
    expect(c.value, greaterThan(0.0)); // 다시 앞에 오면 돎
  });
}

class _Host extends StatefulWidget {
  const _Host({required this.onController});
  final void Function(AnimationController) onController;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  @override
  void initState() {
    super.initState();
    widget.onController(_c);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
