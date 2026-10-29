// 공용 부품 — 화면 맨 위(PageHero: 큰 도형+날짜+제목), 뒤집는 카드(FlipCard)
// (2026-10-29: 1,787줄짜리 components.dart를 주제별로 나눔. 불러오는 쪽은 그대로 `widgets/components.dart` 하나만 import 하면 됨.)
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../sources_info.dart';
import 'basics.dart';
import 'text.dart';

const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

/// 한 화면의 맨 위. 큰 도형(화면 가장자리로 잘려 나감) + 데일리컷/날짜 +
/// 섹션명 + 한 문장 제목. body에 큰 숫자·차트 같은 대표 내용을 넣음.
/// back을 주면 누르면 뒤집혀서 뒷면(back)이 보임.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.section,
    required this.headline,
    required this.body,
    this.emphasis,
    this.eyebrow,
    this.source,
    this.back,
    this.backTitle,
    this.backHint,
    this.stub = false,
    this.onEyebrowTap,
    this.headlineLines = 0,
    this.topExtra,
  });

  final Widget? topExtra; // 지역 줄 바로 아래(제목 위)에 놓는 전환 버튼 등

  final int headlineLines; // 제목이 짧아도 이 줄 수만큼 자리를 비워 둠(고른 항목이 바뀔 때 화면이 위아래로 안 출렁이게)
  final VoidCallback? onEyebrowTap; // 있으면 눈썹 글(예: '오늘 · 서울 ▾')을 눌러 지역 선택
  final bool stub; // 실데이터가 아니면 true(개발용 표시)
  final Section section;
  final String headline;
  final String? emphasis;
  final String? eyebrow;
  final List<Widget> body;
  final String? source;
  final Widget? back;
  final String? backTitle;
  final String? backHint;

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[section]!;
    Widget hint(String text) => Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Text.rich(
        TextSpan(children: [
          const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.refresh, size: 13, color: AppColors.inkSoft)),
          TextSpan(text: ' $text'),
        ]),
        style: const TextStyle(fontSize: 11, color: AppColors.inkSoft),
      ),
    );
    final front = _HeroFrame(
      section: section,
      source: source,
      topExtra: topExtra,
      onEyebrowTap: onEyebrowTap,
      eyebrow: eyebrow ?? t.label,
      headline: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 24 * 1.4 * headlineLines),
        child: HighlightText(
          text: headline,
          emphasis: emphasis,
          color: t.highlight,
          style: AppTheme.displaySerif(
            size: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...body,
          if (back != null) hint(backHint ?? '눌러서 더 보기'),
        ],
      ),
    );
    if (back == null) return StubMark(stub: stub, child: front);
    return FlipCard(
      front: StubMark(stub: stub, child: front),
      back: StubMark(
        stub: stub,
        child: _HeroFrame(
          section: section,
          source: source,
          topExtra: topExtra,
          onEyebrowTap: onEyebrowTap,
          eyebrow: eyebrow ?? t.label,
          headline: Text(
            backTitle ?? '',
            style: AppTheme.displaySerif(
              size: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [back!, hint('눌러서 앞면으로')],
          ),
        ),
      ),
    );
  }
}

class _HeroFrame extends StatelessWidget {
  const _HeroFrame({
    required this.section,
    required this.eyebrow,
    required this.headline,
    required this.child,
    this.onEyebrowTap,
    this.source,
    this.topExtra,
  });

  final String? source;
  final Widget? topExtra;
  final VoidCallback? onEyebrowTap;
  final Section section;
  final String eyebrow;
  final Widget headline;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _Blob(section: section),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      const TextSpan(
                        text: '데일리컷',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      TextSpan(
                        text:
                            '   ${now.month}월 ${now.day}일 ${_weekdays[now.weekday - 1]}요일',
                      ),
                    ],
                  ),
                  style: const TextStyle(fontSize: 13, color: AppColors.ink),
                ),
                // 데이터 출처: 날짜 옆의 작은 ⓘ(배경 없이) — 누르면 이 화면의 출처와 앱 전체 출처 목록
                GestureDetector(
                  onTap: () => showSourcesSheet(context, current: source),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(8, 8, 12, 8),
                    child: Icon(Icons.info_outline, size: 15, color: AppColors.inkSoft),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 86),
            GestureDetector(
              onTap: onEyebrowTap,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: eyebrow),
                    if (onEyebrowTap != null) const WidgetSpan(alignment: PlaceholderAlignment.middle, child: Icon(Icons.arrow_drop_down, size: 18)),
                  ]),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            if (topExtra != null) ...[const SizedBox(height: 10), topExtra!],
            const SizedBox(height: 8),
            headline,
            const SizedBox(height: 22),
            child,
          ],
        ),
      ],
    );
  }
}

/// 화면 오른쪽 위 가장자리로 잘려 나가는 큰 도형. 아주 느리게 흔들림.
class _Blob extends StatefulWidget {
  const _Blob({required this.section});

  final Section section;

  @override
  State<_Blob> createState() => _BlobState();
}

class _BlobState extends State<_Blob> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  );
  bool _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
        _c.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = sectionThemes[widget.section]!;
    return Positioned(
      right: -76,
      top: -80,
      width: 200,
      height: 200,
      child: IgnorePointer(
        child: RotationTransition(
          turns: Tween<double>(
            begin: -0.014,
            end: 0.017,
          ).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)),
          child: Image.asset(t.shapeAsset, fit: BoxFit.contain),
        ),
      ),
    );
  }
}

/// 누르면 뒤집히는 앞/뒷면. 회전이 90도(옆에서 봐서 폭이 0에 가까운 순간)일
/// 때만 면을 바꿔서 면마다 높이가 달라도 어색하지 않게 함.
class FlipCard extends StatefulWidget {
  const FlipCard({super.key, required this.front, required this.back});

  final Widget front;
  final Widget back;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubic,
  );
  bool _showingBack = false;

  void _toggle() {
    if (_showingBack) {
      _controller.reverse();
    } else {
      _controller.forward();
    }
    _showingBack = !_showingBack;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggle,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, _) {
          final angle = _curve.value * math.pi;
          final isBack = angle > math.pi / 2;
          final transform = Matrix4.identity()
            ..setEntry(3, 2, 0.0012)
            ..rotateY(isBack ? angle - math.pi : angle);
          return Transform(
            transform: transform,
            alignment: Alignment.center,
            // 앞·뒷면을 IndexedStack에 같이 넣어 둘 중 큰 쪽 높이로 맞춤(뒤집어도 아래가 안 출렁임)
            child: IndexedStack(index: isBack ? 1 : 0, children: [widget.front, widget.back]),
          );
        },
      ),
    );
  }
}
