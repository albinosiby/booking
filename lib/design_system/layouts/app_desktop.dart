import 'package:flutter/material.dart';
import '../components/app_card.dart';
import '../tokens/app_theme.dart';
import '../tokens/spacing.dart';

/// Window width at which full pages switch to their desktop layout.
///
/// Measured on the whole window so pages can pick their AppPage `maxWidth`
/// before laying out. At this width the 264px sidebar still leaves AppPage
/// at least [AppPage.wideWidth], so its desktop header always matches.
const appDesktopWidth = 1180.0;

bool isDesktopWidth(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= appDesktopWidth;

/// Headline figure card for desktop dashboards.
class AppStatTile extends StatelessWidget {
  const AppStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.caption,
    this.accent,
    this.highlight = false,
    this.trailing,
    this.onTap,
  });
  final IconData icon;
  final String label, value;
  final String? caption;
  final Color? accent;

  /// Brand gradient fill for the most important figure in a row.
  final bool highlight;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = highlight ? scheme.onPrimary : scheme.onSurface;
    final tint = highlight ? scheme.onPrimary : (accent ?? scheme.primary);
    final radius = BorderRadius.circular(AppSpacing.cardRadius);
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: highlight ? null : scheme.surface,
          gradient: highlight
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.lime, AppColors.forest],
                )
              : null,
          border: highlight
              ? null
              : Border.all(color: scheme.outline.withValues(alpha: .4)),
        ),
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: tint.withValues(alpha: highlight ? .18 : .12),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(icon, size: 19, color: tint),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fg.withValues(alpha: .8),
                        ),
                      ),
                    ),
                    ?trailing,
                  ],
                ),
                const SizedBox(height: 16),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.8,
                      color: fg,
                    ),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: fg.withValues(alpha: .6),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Equal-height row of stat tiles with consistent gaps.
class AppStatRow extends StatelessWidget {
  const AppStatRow({super.key, required this.children, this.gap = 16});
  final List<Widget> children;
  final double gap;
  @override
  Widget build(BuildContext context) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: c),
        ],
      ],
    ),
  );
}

/// Titled block on desktop pages, with an optional trailing action.
class AppPanel extends StatelessWidget {
  const AppPanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.onAction,
    this.trailing,
  });
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
  final Widget? trailing;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null)
                        Text(subtitle!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                ?trailing,
                if (action != null)
                  TextButton.icon(
                    onPressed: onAction,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward, size: 16),
                    label: Text(action!),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}

/// Responsive card grid: as many columns of at least [minTileWidth] as fit.
class AppGrid extends StatelessWidget {
  const AppGrid({
    super.key,
    required this.children,
    this.minTileWidth = 300,
    this.maxColumns = 4,
    this.gap = 16,
  });
  final List<Widget> children;
  final double minTileWidth, gap;
  final int maxColumns;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = ((box.maxWidth + gap) / (minTileWidth + gap))
          .floor()
          .clamp(1, maxColumns);
      final width = (box.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [for (final c in children) SizedBox(width: width, child: c)],
      );
    },
  );
}

/// Main content beside a narrower side column, top aligned.
class AppTwoPane extends StatelessWidget {
  const AppTwoPane({
    super.key,
    required this.primary,
    required this.secondary,
    this.secondaryWidth,
    this.primaryFlex = 3,
    this.secondaryFlex = 2,
    this.gap = 28,
    this.secondaryFirst = false,
  });
  final List<Widget> primary, secondary;

  /// Fixed side column width; when null the columns share space by flex.
  final double? secondaryWidth;
  final int primaryFlex, secondaryFlex;
  final double gap;

  /// Puts the side column on the left (for example a filter rail).
  final bool secondaryFirst;
  @override
  Widget build(BuildContext context) {
    Widget column(List<Widget> c) =>
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: c);
    final main = Expanded(flex: primaryFlex, child: column(primary));
    final side = secondaryWidth == null
        ? Expanded(flex: secondaryFlex, child: column(secondary))
        : SizedBox(width: secondaryWidth, child: column(secondary));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: secondaryFirst
          ? [side, SizedBox(width: gap), main]
          : [main, SizedBox(width: gap), side],
    );
  }
}

/// Toolbar row for desktop list pages: search or filters left, actions right.
class AppToolbar extends StatelessWidget {
  const AppToolbar({super.key, this.leading, this.actions = const []});
  final Widget? leading;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Expanded(child: leading ?? const SizedBox.shrink()),
      for (final a in actions) ...[const SizedBox(width: 10), a],
    ],
  );
}

/// One card holding rows separated by dividers, for desktop lists.
class AppListCard extends StatelessWidget {
  const AppListCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => AppCard(
    padding: EdgeInsets.zero,
    child: Column(
      children: [
        for (final (i, c) in children.indexed) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: .35),
            ),
          c,
        ],
      ],
    ),
  );
}
