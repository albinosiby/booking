import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Booking confirmation artwork supplied for the booking success flow.
/// Respects reduced motion and the ancestor TickerMode.
class BookingSuccess extends StatefulWidget {
  static const duration = Duration(milliseconds: 2800);

  const BookingSuccess({
    super.key,
    this.size = 128,
    this.animate = true,
    this.semanticLabel = 'Booking confirmed',
  }) : assert(size > 0 && size < double.infinity);

  final double size;
  final bool animate;
  final String semanticLabel;

  @override
  State<BookingSuccess> createState() => _BookingSuccessState();
}

class _BookingSuccessState extends State<BookingSuccess>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: BookingSuccess.duration,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant BookingSuccess oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animate != widget.animate) {
      if (widget.animate) _controller.value = 0;
      _syncPlayback();
    }
  }

  void _syncPlayback() {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    if (widget.animate &&
        !reducedMotion &&
        TickerMode.valuesOf(context).enabled) {
      if (!_controller.isAnimating && _controller.value < 1) {
        _controller.forward();
      }
    } else {
      _controller.stop();
      if (!widget.animate || reducedMotion) _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: widget.semanticLabel,
      image: true,
      child: RepaintBoundary(
        child: SizedBox.square(
          dimension: widget.size,
          child: CustomPaint(painter: _BookingSuccessPainter(_controller)),
        ),
      ),
    );
  }
}

class _BookingSuccessPainter extends CustomPainter {
  _BookingSuccessPainter(this.animation) : super(repaint: animation);
  final Animation<double> animation;
  static final Path _check = Path()
    ..moveTo(137, 119)
    ..lineTo(153, 135)
    ..lineTo(184, 104);
  static final _metric = _check.computeMetrics().single;
  double _phase(double t, double start, double end) =>
      ((t - start) / (end - start)).clamp(0.0, 1.0);
  double _ease(double t) => Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
  void _round(Canvas c, Rect r, double radius, Paint p) =>
      c.drawRRect(RRect.fromRectAndRadius(r, Radius.circular(radius)), p);

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final fit = math.min(size.width, size.height) / 320;
    canvas.save();
    canvas.translate(
      (size.width - fit * 320) / 2,
      (size.height - fit * 320) / 2,
    );
    canvas.scale(fit);
    final fill = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFF0FDFA), Color(0xFFCCFBF1)],
      ).createShader(const Rect.fromLTWH(44, 35, 232, 232));
    canvas.drawCircle(const Offset(160, 151), 116, fill);
    fill
      ..shader = null
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(const Offset(160, 151), 105, fill);
    fill
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF0F766E).withValues(alpha: 0.07);
    canvas.drawOval(const Rect.fromLTWH(88, 270, 144, 16), fill);

    final burst = _ease(_phase(t, 0.36, 0.84));
    final burstAlpha = t < 0.46
        ? _ease(_phase(t, 0.36, 0.46))
        : 1 - _ease(_phase(t, 0.46, 0.84));
    if (burstAlpha > 0) {
      canvas.save();
      canvas.translate(160, 149);
      canvas.rotate((-0.2 + 0.34 * burst));
      canvas.scale(0.6 + 0.46 * burst);
      for (var i = 0; i < 12; i++) {
        final a = math.pi * 2 * i / 12 - 0.2;
        canvas.save();
        canvas.translate(127 * math.cos(a), 112 * math.sin(a));
        canvas.rotate(i * 31 * math.pi / 180);
        fill.color = const [
          Color(0xFF14B8A6),
          Color(0xFFF5B942),
          Color(0xFF93C5FD),
        ][i % 3].withValues(alpha: burstAlpha);
        _round(canvas, const Rect.fromLTWH(-3, -6, 6, 12), 3, fill);
        canvas.restore();
      }
      canvas.restore();
    }
    final cardIn = _ease(_phase(t, 0, 0.26));
    final settle = _ease(_phase(t, 0.26, 0.42));
    final dy = t < 0.26 ? 28 - 31 * cardIn : -3 + 3 * settle;
    final angle =
        (t < 0.26 ? -8 + 9.5 * cardIn : 1.5 * (1 - settle)) * math.pi / 180;
    final scale = t < 0.26 ? 0.9 + 0.115 * cardIn : 1.015 - 0.015 * settle;
    canvas.save();
    canvas.translate(160, 180 + dy);
    canvas.rotate(angle);
    canvas.scale(scale);
    canvas.translate(-160, -180);
    // One small layer keeps the entire entering card at a consistent opacity.
    canvas.saveLayer(
      const Rect.fromLTWH(50, 85, 220, 190),
      Paint()..color = Colors.white.withValues(alpha: cardIn),
    );
    fill.color = const Color(0xFF0F766E).withValues(alpha: 0.06);
    _round(canvas, const Rect.fromLTWH(70, 105, 180, 162), 26, fill);
    fill.shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Colors.white, Color(0xFFF0FDFA)],
    ).createShader(const Rect.fromLTWH(66, 97, 188, 164));
    _round(canvas, const Rect.fromLTWH(66, 97, 188, 164), 26, fill);
    fill
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFD5EFE9);
    _round(canvas, const Rect.fromLTWH(66, 97, 188, 164), 26, fill);
    fill
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = const Color(0xFFCEE5DF);
    for (double x = 83; x < 237; x += 11) {
      canvas.drawLine(Offset(x, 215), Offset(math.min(x + 4, 237), 215), fill);
    }
    fill
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFDBF9F1);
    canvas.drawCircle(const Offset(66, 215), 7, fill);
    canvas.drawCircle(const Offset(254, 215), 7, fill);
    final details = _ease(_phase(t, 0.43, 0.65));
    fill.color = const Color(0xFF153D47).withValues(alpha: details);
    _round(canvas, const Rect.fromLTWH(112, 184, 96, 7), 3.5, fill);
    fill.color = const Color(0xFFA0C3BD).withValues(alpha: details);
    _round(canvas, const Rect.fromLTWH(130, 199, 60, 4), 2, fill);
    fill.color = const Color(0xFFD9F8ED).withValues(alpha: details);
    _round(canvas, const Rect.fromLTWH(101, 230, 118, 17), 8.5, fill);
    fill.color = const Color(0xFF0D9488).withValues(alpha: details);
    canvas.drawCircle(const Offset(115, 238.5), 3, fill);
    fill.color = const Color(0xFF4F9D8C).withValues(alpha: details);
    _round(canvas, const Rect.fromLTWH(125, 236, 79, 5), 2.5, fill);
    canvas.restore();
    canvas.restore();

    final ripple = _ease(_phase(t, 0.34, 0.78));
    final rippleAlpha = t < 0.40
        ? 0.55 * _ease(_phase(t, 0.34, 0.40))
        : 0.55 * (1 - _ease(_phase(t, 0.40, 0.78)));
    fill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF2DD4BF).withValues(alpha: rippleAlpha);
    canvas.drawCircle(const Offset(160, 119), 59 * (0.8 + 0.9 * ripple), fill);
    final badgeIn = _ease(_phase(t, 0.12, 0.32));
    final badgeSettle = _ease(_phase(t, 0.32, 0.45));
    final badgeScale = t < 0.32
        ? 0.45 + 0.63 * badgeIn
        : 1.08 - 0.08 * badgeSettle;
    canvas.save();
    canvas.translate(160, 119);
    canvas.scale(badgeScale);
    canvas.translate(-160, -119);
    canvas.saveLayer(
      const Rect.fromLTWH(95, 54, 130, 134),
      Paint()..color = Colors.white.withValues(alpha: badgeIn),
    );
    fill
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF0F766E).withValues(alpha: 0.08);
    canvas.drawCircle(const Offset(160, 123), 58, fill);
    fill.color = Colors.white;
    canvas.drawCircle(const Offset(160, 119), 58, fill);
    fill.shader = const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2DD4BF), Color(0xFF0F766E)],
    ).createShader(const Rect.fromLTWH(109, 68, 102, 102));
    canvas.drawCircle(const Offset(160, 119), 51, fill);
    fill
      ..shader = null
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.23);
    canvas.drawCircle(const Offset(160, 119), 43, fill);
    fill
      ..strokeWidth = 3
      ..color = Colors.white.withValues(alpha: 0.55);
    canvas.drawPath(
      Path()
        ..moveTo(132, 85)
        ..cubicTo(139, 79, 150, 76, 160, 76),
      fill,
    );
    final check = Curves.easeInOut.transform(_phase(t, 0.30, 0.53));
    if (check > 0) {
      fill
        ..strokeWidth = 9
        ..strokeJoin = StrokeJoin.round
        ..color = Colors.white;
      canvas.drawPath(_metric.extractPath(0, _metric.length * check), fill);
    }
    canvas.restore();
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _BookingSuccessPainter oldDelegate) =>
      oldDelegate.animation != animation;
}
