import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'accounts_overview_widgets.dart';

/// Percent change against the previous period, or null when it is undefined.
double? financeChange(int current, int previous) =>
    previous == 0 ? null : (current - previous) / previous.abs() * 100;

/// Headline figure for the wide accounts dashboard.
class FinanceStatTile extends StatelessWidget {
  const FinanceStatTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
    this.change,
    this.higherIsBetter = true,
    this.accent,
    this.highlight = false,
  });
  final IconData icon;
  final String label, value, caption;
  final double? change;
  final bool higherIsBetter, highlight;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = highlight ? scheme.onPrimary : scheme.onSurface;
    final tint = highlight ? scheme.onPrimary : (accent ?? scheme.primary);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
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
              if (change != null)
                _ChangeBadge(change!, higherIsBetter, highlight),
            ],
          ),
          const SizedBox(height: 18),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -.8,
                color: fg,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: fg.withValues(alpha: .6)),
          ),
        ],
      ),
    );
  }
}

class _ChangeBadge extends StatelessWidget {
  const _ChangeBadge(this.change, this.higherIsBetter, this.onPrimary);
  final double change;
  final bool higherIsBetter, onPrimary;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final good = (change >= 0) == higherIsBetter;
    final color = onPrimary
        ? scheme.onPrimary
        : good
        ? scheme.primary
        : scheme.error;
    final text = change.abs() >= 1000
        ? '>999%'
        : '${change.abs().toStringAsFixed(change.abs() < 10 ? 1 : 0)}%';
    return Tooltip(
      message: 'Compared with the previous period',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              change >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: color,
            ),
            const SizedBox(width: 2),
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Titled column block on the wide dashboard.
class FinancePanel extends StatelessWidget {
  const FinancePanel({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.onAction,
  });
  final String title;
  final String? subtitle, action;
  final VoidCallback? onAction;
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

/// Labelled action buttons for the wide dashboard header.
class FinanceActionButtons extends StatelessWidget {
  const FinanceActionButtons(this.actions, {super.key});
  final List<FinanceAction> actions;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (i, a) in actions.indexed)
        i == 0
            ? FilledButton.icon(
                onPressed: a.onTap,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: Icon(a.icon, size: 18),
                label: Text(a.label),
              )
            : OutlinedButton.icon(
                onPressed: a.onTap,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                icon: Icon(a.icon, size: 18),
                label: Text(a.label),
              ),
    ],
  );
}
