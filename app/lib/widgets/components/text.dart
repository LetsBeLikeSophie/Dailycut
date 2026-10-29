// 공용 부품 — 형광펜 제목(HighlightText)·줄바꿈·큰 숫자(BigNumber)
// (2026-10-29: 1,787줄짜리 components.dart를 주제별로 나눔. 불러오는 쪽은 그대로 `widgets/components.dart` 하나만 import 하면 됨.)
import 'package:flutter/material.dart';

import '../../theme.dart';
import 'basics.dart';

/// 제목 속 일부 구절만 섹션 형광펜으로 강조(전체 문장은 그대로).
class HighlightText extends StatelessWidget {
  const HighlightText({
    super.key,
    required this.text,
    required this.color,
    this.emphasis,
    this.emphasisAll = const [],
    required this.style,
  });

  final String text;
  final Color color;
  final String? emphasis;
  final List<String> emphasisAll; // 글 안에 나오는 모든 자리를 칠할 낱말들(예: '토요일', '일요일')
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    // 2026-10-16: 한글은 글자 사이 어디서나 줄이 바뀌어 "…21°예 / 요"처럼 마지막 글자가 혼자 내려왔음 →
    // 단어(띄어쓰기) 단위로만 줄을 바꿈(CSS word-break: keep-all). 공백 하나를 줄바꿈 하나로 바꾸는 거라 글자 위치(강조 구간)는 그대로.
    return LayoutBuilder(
      builder: (context, c) {
        final base = DefaultTextStyle.of(context).style.merge(style);
        final t = keepAllWrap(text, base, c.maxWidth, MediaQuery.textScalerOf(context));
        final ranges = <(int, int)>[];
        final e = emphasis;
        if (e != null) {
          final i = text.indexOf(e);
          if (i >= 0) ranges.add((i, i + e.length));
        }
        for (final w in emphasisAll) {
          var from = 0;
          while (w.isNotEmpty) {
            final i = text.indexOf(w, from);
            if (i < 0) break;
            ranges.add((i, i + w.length));
            from = i + w.length;
          }
        }
        if (ranges.isEmpty) return Text(t, style: style);
        ranges.sort((x, y) => x.$1.compareTo(y.$1));
        final marked = TextStyle(backgroundColor: color.withValues(alpha: 0.85));
        final spans = <TextSpan>[];
        var pos = 0;
        for (final (start, end) in ranges) {
          if (start < pos) continue; // 겹치면 앞의 것만
          if (start > pos) spans.add(TextSpan(text: t.substring(pos, start)));
          spans.add(TextSpan(text: t.substring(start, end), style: marked));
          pos = end;
        }
        if (pos < t.length) spans.add(TextSpan(text: t.substring(pos)));
        return Text.rich(TextSpan(style: style, children: spans));
      },
    );
  }
}

/// 띄어쓰기 단위로만 줄을 나눔: 한 줄에 안 들어가는 단어 앞의 공백을 줄바꿈으로 바꿔 돌려줌(길이는 같음).
/// 한 단어가 한 줄보다 길면 어쩔 수 없이 그대로 두어 기본 줄바꿈에 맡김.
final Map<String, String> _wrapMemo = {};

String keepAllWrap(String text, TextStyle style, double maxWidth, TextScaler scaler) {
  if (!maxWidth.isFinite || !text.contains(' ')) return text;
  // 같은 글·폭·글꼴 크기면 다시 재지 않음(다시 그릴 때마다 글자 폭을 재던 것). 글꼴 크기·굵기·배율이 키에 들어감.
  final memoKey = '${maxWidth.toStringAsFixed(1)}|${style.fontSize}|${style.fontWeight?.value}|${style.fontFamily}|${scaler.scale(10)}|$text';
  final memo = _wrapMemo[memoKey];
  if (memo != null) return memo;
  if (_wrapMemo.length > 200) _wrapMemo.clear();
  double width(String s) {
    final tp = TextPainter(text: TextSpan(text: s, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
    return tp.width;
  }

  final out = StringBuffer();
  var line = '';
  var first = true;
  for (final w in text.split(' ')) {
    if (first) {
      out.write(w);
      line = w;
      first = false;
      continue;
    }
    final cand = '$line $w';
    if (line.isNotEmpty && width(cand) > maxWidth) {
      out.write('\n');
      line = w;
    } else {
      out.write(' ');
      line = cand;
    }
    out.write(w);
  }
  return _wrapMemo[memoKey] = out.toString();
}

/// 큰 숫자(세리프 60). 숫자는 처음 나타날 때 0에서 올라가며 멈춤.
class BigNumber extends StatelessWidget {
  const BigNumber({
    super.key,
    required this.to,
    this.decimals = 0,
    this.unit,
    this.suffix = '',
  });

  final num to;
  final int decimals;
  final String? unit;
  final String suffix; // 숫자 바로 뒤(예: 도 기호 °)에 같은 크기로 붙는 글자

  @override
  Widget build(BuildContext context) {
    final still = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final big = const TextStyle(
      fontFamily: 'NotoSerifKR',
      fontSize: 60,
      fontWeight: FontWeight.w900,
      height: 1.05,
      letterSpacing: -1.8,
      color: AppColors.ink,
    );
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: still ? to.toDouble() : 0, end: to.toDouble()),
      duration: still ? Duration.zero : const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Text.rich(
        TextSpan(
          style: big,
          children: [
            TextSpan(text: '${formatNumber(v, decimals: decimals)}$suffix'),
            if (unit != null)
              TextSpan(
                text: '  $unit',
                style: const TextStyle(
                  fontFamily: 'NotoSansKR',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0,
                  color: AppColors.inkSoft,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
