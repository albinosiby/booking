import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'ground_canvas.dart';

class FootballGroundDiagram extends StatelessWidget {
  const FootballGroundDiagram({super.key, required this.split});
  final bool split;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: split
        ? 'Football ground: Half A and Half B combine into Full Ground'
        : 'Football ground: one undivided court',
    child: AspectRatio(
      aspectRatio: 760 / 530,
      child: CustomPaint(painter: FootballGroundPainter(split: split)),
    ),
  );
}

class FootballGroundPainter extends CustomPainter {
  const FootballGroundPainter({required this.split});
  final bool split;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final g = GroundCanvas(canvas, size);
    g.surface(const Color(0xFF117561));
    g.rect(20, 17, 720, 496);
    g.line(380, 17, 380, 513);
    canvas.drawCircle(const Offset(380, 265), 74, g.linePaint);
    g.dot(380, 265);
    g.rect(20, 138, 68, 254);
    g.rect(20, 219, 31, 92);
    g.rect(672, 138, 68, 254);
    g.rect(709, 219, 31, 92);
    g.dot(130, 265);
    g.dot(630, 265);
    canvas.drawArc(
      const Rect.fromLTWH(14, 191, 102, 148),
      -math.pi / 2,
      math.pi,
      false,
      g.linePaint,
    );
    canvas.drawArc(
      const Rect.fromLTWH(644, 191, 102, 148),
      math.pi / 2,
      math.pi,
      false,
      g.linePaint,
    );
    g.rect(7, 225, 13, 80);
    g.rect(740, 225, 13, 80);
    for (final x in [20.0, 740.0]) {
      for (final y in [17.0, 513.0]) {
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x, y), radius: 20),
          x == 20
              ? (y == 17 ? 0 : -math.pi / 2)
              : (y == 17 ? math.pi / 2 : math.pi),
          math.pi / 2,
          false,
          g.linePaint,
        );
      }
    }
    if (split) {
      for (final x in [220.0, 540.0]) {
        g.dashed(Path()..addRect(Rect.fromLTWH(x - 96, 17, 192, 137)));
        g.dashed(Path()..addRect(Rect.fromLTWH(x - 96, 376, 192, 137)));
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x, 17), radius: 51),
          0,
          math.pi,
          false,
          g.linePaint,
        );
        canvas.drawArc(
          Rect.fromCircle(center: Offset(x, 513), radius: 51),
          math.pi,
          math.pi,
          false,
          g.linePaint,
        );
        g.dot(x, 56);
        g.dot(x, 474);
        g.rect(x - 25, 5, 50, 17);
        g.rect(x - 25, 508, 50, 17);
        for (var n = -20; n <= 20; n += 10) {
          g.line(x + n, 5, x + n, 22);
          g.line(x + n, 508, x + n, 525);
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant FootballGroundPainter oldDelegate) =>
      split != oldDelegate.split;
}
