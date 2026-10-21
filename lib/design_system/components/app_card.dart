import 'package:flutter/material.dart';
import '../tokens/spacing.dart';

class AppCard extends StatefulWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  // Pointer hover feedback for web and desktop; touch devices never set it.
  bool hover = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final lifted = hover && widget.onTap != null;
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          if (lifted)
            BoxShadow(
              color: Colors.black.withValues(
                alpha: theme.brightness == Brightness.dark ? .45 : .08,
              ),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: Material(
        color: colors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: lifted
                ? colors.primary.withValues(alpha: .55)
                : colors.outline.withValues(alpha: .4),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: widget.onTap == null
            ? Padding(padding: widget.padding, child: widget.child)
            : InkWell(
                onTap: widget.onTap,
                onHover: (v) => setState(() => hover = v),
                child: Padding(padding: widget.padding, child: widget.child),
              ),
      ),
    );
  }
}
