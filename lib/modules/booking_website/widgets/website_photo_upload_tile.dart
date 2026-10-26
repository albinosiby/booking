import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A keyboard-accessible upload target shared by website photo sections.
class WebsitePhotoUploadTile extends StatelessWidget {
  const WebsitePhotoUploadTile({
    super.key,
    required this.label,
    required this.onPressed,
  });
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final enabled = onPressed != null;
    final color = enabled
        ? colors.primary
        : colors.onSurface.withValues(alpha: .38);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox.square(
        dimension: math.min(144.0, constraints.maxWidth),
        child: Semantics(
          button: true,
          enabled: enabled,
          child: Tooltip(
            message: label,
            child: CustomPaint(
              foregroundPainter: _DottedPhotoBorder(color),
              child: Material(
                color: enabled
                    ? colors.primary.withValues(alpha: .04)
                    : colors.surfaceContainerHighest.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_rounded, size: 32, color: color),
                        const SizedBox(height: 8),
                        Flexible(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: color,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DottedPhotoBorder extends CustomPainter {
  const _DottedPhotoBorder(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          (Offset.zero & size).deflate(1.5),
          const Radius.circular(12),
        ),
      );
    final paint = Paint()..color = color;
    for (final edge in path.computeMetrics()) {
      final count = (edge.length / 7).ceil();
      for (var index = 0; index < count; index++) {
        final point = edge.getTangentForOffset(index * edge.length / count);
        if (point != null) {
          canvas.drawCircle(point.position, 1, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DottedPhotoBorder oldDelegate) =>
      color != oldDelegate.color;
}
