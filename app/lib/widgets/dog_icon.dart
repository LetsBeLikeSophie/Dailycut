import 'package:flutter/material.dart';

/// 반려견 크기 아이콘(2026-10-16): 앱 톤에 맞게 **선으로만** 그린 옆모습 강아지. 크기별로 몸 비율이 달라 한눈에 구분됨.
///  small = 소형견(다리 짧고 귀가 쫑긋) · medium = 중·소형견 · large = 대형견(다리 길고 귀가 처짐) · all = 세 마리가 크기 순으로 나란히(모든 크기)
/// 이모지 폰트에 기대지 않고 CustomPainter로 직접 그려서 어느 기기에서나 같음.
enum DogSize { small, medium, large, all }

class DogIcon extends StatelessWidget {
  const DogIcon({super.key, required this.size, required this.color, this.height = 18});

  final DogSize size;
  final Color color;
  final double height; // 그림 높이(가로는 비율대로)

  @override
  Widget build(BuildContext context) {
    final w = _widthFor(size) * height / _unitH;
    return SizedBox(width: w, height: height, child: CustomPaint(painter: _DogPainter(size, color)));
  }
}

// 그림 좌표계는 높이 20 기준(단위 u). 가로는 크기마다 다름.
const double _unitH = 20;

double _widthFor(DogSize s) => switch (s) {
      DogSize.small => 17,
      DogSize.medium => 21,
      DogSize.large => 25,
      DogSize.all => 58,
    };

class _Prop {
  const _Prop({required this.body, required this.bodyH, required this.leg, required this.head, required this.floppy});

  final double body; // 몸통 길이
  final double bodyH; // 몸통 두께
  final double leg; // 다리 길이
  final double head; // 머리 반지름
  final bool floppy; // 귀가 처졌는지(아니면 쫑긋)
}

const _small = _Prop(body: 8, bodyH: 5, leg: 3.6, head: 3.4, floppy: false);
const _medium = _Prop(body: 10.5, bodyH: 5.8, leg: 5, head: 3.4, floppy: true);
const _large = _Prop(body: 13, bodyH: 6.6, leg: 7.2, head: 3.7, floppy: true);

class _DogPainter extends CustomPainter {
  _DogPainter(this.kind, this.color);

  final DogSize kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.height / _unitH;
    canvas.scale(k);
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    const ground = 19.0;
    switch (kind) {
      case DogSize.small:
        _dog(canvas, p, const Offset(3.2, ground), _small);
      case DogSize.medium:
        _dog(canvas, p, const Offset(3.5, ground), _medium);
      case DogSize.large:
        _dog(canvas, p, const Offset(4, ground), _large);
      case DogSize.all:
        // 세 마리를 크기 순으로(왼쪽이 작음). 가로 간격은 각자 몸통 길이 + 머리 + 꼬리 몫
        _dog(canvas, p, const Offset(2.8, ground), _small);
        _dog(canvas, p, const Offset(21.4, ground), _medium);
        _dog(canvas, p, const Offset(42.6, ground), _large, scale: 0.78);
    }
  }

  /// 옆모습 강아지 한 마리. [origin]은 뒷발 쪽 바닥 위치, 오른쪽을 보고 있음.
  void _dog(Canvas c, Paint p, Offset origin, _Prop pr, {double scale = 1}) {
    c.save();
    c.translate(origin.dx, origin.dy);
    c.scale(scale);
    final bl = pr.body, bh = pr.bodyH, leg = pr.leg, hr = pr.head;
    final top = -(leg + bh), bottom = -leg;

    // 몸통
    c.drawRRect(RRect.fromLTRBR(0, top, bl, bottom, Radius.circular(bh * 0.5)), p);

    // 다리(뒤 두 개·앞 두 개)
    for (final x in [1.3, 3.4, bl - 3.4, bl - 1.3]) {
      c.drawLine(Offset(x, bottom - 0.2), Offset(x, 0), p);
    }

    // 꼬리: 엉덩이에서 위로 휘어 올라감
    final tail = Path()
      ..moveTo(0.2, top + bh * 0.3)
      ..quadraticBezierTo(-bl * 0.3, top - bh * 0.1, -bl * 0.18, top - bh * 0.75);
    c.drawPath(tail, p);

    // 머리(몸통 앞 위쪽) + 주둥이
    final hx = bl - 0.2, hy = top - hr * 0.55;
    c.drawCircle(Offset(hx, hy), hr, p);
    final snout = Path()
      ..moveTo(hx + hr * 0.75, hy - hr * 0.05)
      ..quadraticBezierTo(hx + hr * 1.55, hy + hr * 0.05, hx + hr * 1.35, hy + hr * 0.55)
      ..quadraticBezierTo(hx + hr * 1.1, hy + hr * 0.85, hx + hr * 0.5, hy + hr * 0.7);
    c.drawPath(snout, p);

    // 눈·코(채운 점)
    final dot = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    c.drawCircle(Offset(hx + hr * 0.22, hy - hr * 0.22), 0.62, dot);
    c.drawCircle(Offset(hx + hr * 1.38, hy + hr * 0.22), 0.7, dot);

    // 귀: 소형견은 쫑긋, 그 밖은 처짐
    final ear = Path();
    if (pr.floppy) {
      ear
        ..moveTo(hx - hr * 0.15, hy - hr * 0.85)
        ..quadraticBezierTo(hx - hr * 1.05, hy - hr * 0.55, hx - hr * 0.8, hy + hr * 0.55);
    } else {
      ear
        ..moveTo(hx - hr * 0.85, hy - hr * 0.35)
        ..quadraticBezierTo(hx - hr * 1.15, hy - hr * 1.75, hx - hr * 0.45, hy - hr * 1.5)
        ..quadraticBezierTo(hx - hr * 0.05, hy - hr * 1.35, hx + hr * 0.1, hy - hr * 0.9);
    }
    c.drawPath(ear, p);
    c.restore();
  }

  @override
  bool shouldRepaint(_DogPainter old) => old.kind != kind || old.color != color;
}
