import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Shared loading motion. Feature Cubits own when these widgets are shown;
/// animation controllers only own presentation and never start data requests.
class AppOrbitLoader extends StatelessWidget {
  const AppOrbitLoader({super.key});
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: _Motion(
      // Eight 900ms inner turns and five reverse outer turns form a seamless loop.
      duration: const Duration(milliseconds: 7200),
      builder: (context, phase) => CustomPaint(
        size: const Size.square(64),
        painter: _OrbitPainter(phase, Theme.of(context).colorScheme.primary),
      ),
    ),
  );
}

class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    this.label = 'Refreshing…',
    this.iconOnly = false,
  });
  final String label;
  final bool iconOnly;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: ExcludeSemantics(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: iconOnly ? 0 : 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Motion(
              duration: const Duration(milliseconds: 1530),
              builder: (context, phase) => CustomPaint(
                size: const Size.square(20),
                painter: _RefreshPainter(
                  phase,
                  Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
            if (!iconOnly) ...[
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// Decorative busy indicator; the containing button supplies its spoken label.
class AppSavingDots extends StatelessWidget {
  const AppSavingDots({super.key, this.color});
  final Color? color;
  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: _Motion(
      duration: const Duration(milliseconds: 720),
      builder: (context, phase) => CustomPaint(
        size: const Size(26, 18),
        painter: _DotsPainter(
          phase,
          color ??
              IconTheme.of(context).color ??
              Theme.of(context).colorScheme.primary,
        ),
      ),
    ),
  );
}

/// Non-button mutations use the same saving dots as busy action buttons.
class AppSavingIndicator extends StatelessWidget {
  const AppSavingIndicator({super.key, this.label = 'Saving…'});
  final String label;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    label: label,
    child: ExcludeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppSavingDots(color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Keeps loading feedback inline. Never replaces, dims or blocks cached content.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.initial = false, this.label});
  final bool initial;
  final String? label;
  @override
  Widget build(BuildContext context) {
    if (!initial) return AppRefreshIndicator(label: label ?? 'Refreshing…');
    final message = label ?? 'Loading your workspace…';
    return Semantics(
      liveRegion: true,
      label: 'Getting things ready. $message',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const AppOrbitLoader(),
                  const SizedBox(width: 18),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Getting things ready',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 5),
                        Text(
                          message,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Motion extends StatefulWidget {
  const _Motion({required this.duration, required this.builder});
  final Duration duration;
  final Widget Function(BuildContext, double) builder;
  @override
  State<_Motion> createState() => _MotionState();
}

class _MotionState extends State<_Motion> with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  bool reduced = false;
  void synchronize() {
    reduced = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduced || !TickerMode.valuesOf(context).enabled) {
      controller.stop();
    } else if (!controller.isAnimating) {
      controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    synchronize();
  }

  @override
  void didUpdateWidget(covariant _Motion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      controller.stop();
      controller.duration = widget.duration;
    }
    synchronize();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: controller,
      builder: (context, _) =>
          widget.builder(context, reduced ? .25 : controller.value),
    ),
  );
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }
}

abstract class _PhasePainter extends CustomPainter {
  const _PhasePainter(this.phase, this.color);
  final double phase;
  final Color color;
  @override
  bool shouldRepaint(covariant _PhasePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}

class _OrbitPainter extends _PhasePainter {
  const _OrbitPainter(super.phase, super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, 24, stroke..color = color.withValues(alpha: .14));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 24),
      -math.pi / 2 + phase * math.pi * 16,
      math.pi,
      false,
      stroke..color = color,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: 31),
      math.pi - phase * math.pi * 10,
      math.pi / 2,
      false,
      stroke
        ..strokeWidth = 1
        ..color = color.withValues(alpha: .45),
    );
    final pulse = (math.sin(phase * math.pi * 16 - math.pi / 2) + 1) / 2;
    canvas.drawCircle(
      center,
      4 + pulse,
      Paint()..color = color.withValues(alpha: .65 + pulse * .35),
    );
  }
}

class _RefreshPainter extends _PhasePainter {
  const _RefreshPainter(super.phase, super.color);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    canvas.drawCircle(center, 3, Paint()..color = color);
    canvas.drawCircle(
      center,
      6 * (.55 + phase * 1.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = color.withValues(
          alpha: .65 * math.pow(1 - phase, 2).toDouble(),
        ),
    );
  }
}

class _DotsPainter extends _PhasePainter {
  const _DotsPainter(super.phase, super.color);
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final pulse = (math.cos((phase - i * .1944) * math.pi * 2) + 1) / 2;
      canvas.drawCircle(
        Offset(4 + i * 9, 9),
        2.5 * (.7 + pulse * .45),
        Paint()..color = color.withValues(alpha: .45 + pulse * .55),
      );
    }
  }
}
