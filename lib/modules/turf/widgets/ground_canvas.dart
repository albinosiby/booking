import 'package:flutter/material.dart';

/// Shared vector drawing primitives for sport diagrams (760 × 530).
class GroundCanvas {
  GroundCanvas(this.canvas, Size size) {
    canvas.scale(size.width / 760, size.height / 530);
  }
  final Canvas canvas;
  final linePaint = Paint()
    ..color = const Color(0xFFF3F6ED)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.6;
  void surface(Color border) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(4, 4, 752, 522),
        const Radius.circular(28),
      ),
      Paint()..color = border,
    );
    canvas.clipRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(13, 13, 734, 504),
        const Radius.circular(20),
      ),
    );
    for (var i = 0; i < 12; i++) {
      canvas.drawRect(
        Rect.fromLTWH(13 + i * 62, 13, 62, 504),
        Paint()
          ..color = i.isEven
              ? const Color(0xFF145D2E)
              : const Color(0xFF105127),
      );
    }
  }

  void line(double x1, double y1, double x2, double y2) =>
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), linePaint);
  void rect(double x, double y, double w, double h) =>
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), linePaint);
  void dot(double x, double y, {double radius = 3}) =>
      canvas.drawCircle(Offset(x, y), radius, Paint()..color = linePaint.color);
  void dashed(Path path) {
    final paint = Paint()
      ..color = linePaint.color.withValues(alpha: .8)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      for (double distance = 0; distance < metric.length; distance += 13) {
        canvas.drawPath(metric.extractPath(distance, distance + 8), paint);
      }
    }
  }
}
