import 'package:flutter/material.dart';
import 'ground_canvas.dart';

class CricketGroundDiagram extends StatelessWidget {
  const CricketGroundDiagram({super.key, required this.split});
  final bool split;
  @override
  Widget build(BuildContext context) => Semantics(
    image: true,
    label: split
        ? 'Cricket ground: Half A and Half B combine into Full Ground'
        : 'Cricket ground: one undivided ground',
    child: AspectRatio(
      aspectRatio: 760 / 530,
      child: CustomPaint(painter: CricketGroundPainter(split: split)),
    ),
  );
}

class CricketGroundPainter extends CustomPainter {
  const CricketGroundPainter({required this.split});
  final bool split;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    final g = GroundCanvas(canvas, size);
    g.surface(const Color(0xFFC5A361));
    canvas.drawOval(const Rect.fromLTWH(51, 49, 658, 438), g.linePaint);
    void pitch(double x, double y, double width, double height) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x - width / 2, y, width, height),
        const Radius.circular(2),
      );
      canvas.drawRRect(rect, Paint()..color = const Color(0xFFB99C60));
      canvas.drawRRect(
        rect,
        Paint()
          ..color = const Color(0xFFE1CE94)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      for (final end in [y + height * .1, y + height * .9]) {
        g.line(x - width * .88, end, x + width * .88, end);
        for (final offset in [-6.0, 0.0, 6.0]) {
          g.line(x + offset, end - 17, x + offset, end - 2);
        }
        g.line(x - 8, end - 17, x + 8, end - 17);
      }
    }

    if (split) {
      g.dashed(
        Path()
          ..moveTo(380, 49)
          ..lineTo(380, 487),
      );
      for (final x in [158.0, 602.0]) {
        pitch(x, 186, 30, 166);
        g.dashed(Path()..addRect(Rect.fromLTWH(x - 70, 153, 140, 232)));
      }
    }
    pitch(380, 82, 92, 370);
    g.dot(380, 268, radius: 4);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CricketGroundPainter oldDelegate) =>
      split != oldDelegate.split;
}
