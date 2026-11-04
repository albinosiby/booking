import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/accounts_models.dart';
import 'accounts_overview_widgets.dart';

/// Distinct colors for breakdown rows; cycles when there are more rows.
const financeShareColors = [
  AppColors.lime,
  Color(0xFF4FA3E0),
  Color(0xFFB07CE8),
  financeAmber,
  Color(0xFFE07A5F),
  Color(0xFF4DB6AC),
  Color(0xFF9E9E9E),
];

class FinanceReportAppBarTitle extends StatelessWidget {
  const FinanceReportAppBarTitle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title, subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: scheme.primary, size: 25),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class FinanceChoicePill extends StatelessWidget {
  const FinanceChoicePill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = selected ? const Color(0xFF102008) : scheme.onSurface;
    return Material(
      color: selected ? AppColors.lime : scheme.surfaceContainerHigh,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? AppColors.lime
              : scheme.outline.withValues(alpha: .35),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? Icons.check_rounded : icon,
                size: 17,
                color: selected ? foreground : scheme.primary,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pill-shaped filter button. Highlighted while [active]; shows a clear
/// button instead of the dropdown arrow when [onClear] is given.
class FinanceFilterChip extends StatelessWidget {
  const FinanceFilterChip({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
    this.active = false,
    this.onClear,
  });
  final IconData icon;
  final String label, tooltip;
  final VoidCallback onTap;
  final bool active;
  final VoidCallback? onClear;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active ? scheme.primary.withValues(alpha: .14) : scheme.surface,
        shape: StadiumBorder(
          side: BorderSide(color: active ? scheme.primary : scheme.outline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (onClear != null)
                  InkWell(
                    onTap: onClear,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        semanticLabel: 'Clear $label',
                      ),
                    ),
                  )
                else
                  const Icon(Icons.arrow_drop_down, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Average per elapsed day (monthly) or month (yearly) of the period.
(String, int) financeAverage(
  int total,
  DateTime anchor,
  bool yearly,
  String? today,
) {
  final t = DateTime.tryParse(today ?? '') ?? DateTime.now();
  final current = anchor.year == t.year && (yearly || anchor.month == t.month);
  final units = yearly
      ? (current ? t.month : 12)
      : (current ? t.day : DateTime(anchor.year, anchor.month + 1, 0).day);
  return (
    yearly ? 'Monthly average' : 'Daily average',
    (total / math.max(1, units)).round(),
  );
}

class FinanceOption {
  const FinanceOption(this.id, this.label, {this.icon, this.note});
  final String id, label;
  final IconData? icon;
  final String? note;
}

/// Sheet (dialog on wide windows) listing [options]; returns the chosen ID, or null if dismissed.
Future<String?> showFinanceOptions(
  BuildContext context, {
  required String title,
  required List<FinanceOption> options,
  required String selected,
}) => showAdaptiveSheet<String>(
  context: context,
  scrollable: false,
  builder: (c) => AdaptiveSheetBody(
    initialChildSize: math.min(.9, .2 + options.length * .075),
    builder: (c, controller, shrink) => ListView(
      controller: controller,
      shrinkWrap: shrink,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(title, style: Theme.of(c).textTheme.titleLarge),
        ),
        for (final o in options)
          ListTile(
            leading: o.icon == null ? null : Icon(o.icon),
            title: Text(o.label),
            subtitle: o.note == null ? null : Text(o.note!),
            trailing: o.id == selected
                ? Icon(Icons.check, color: Theme.of(c).colorScheme.primary)
                : null,
            onTap: () => Navigator.pop(c, o.id),
          ),
      ],
    ),
  ),
);

/// Large period total with supporting figures underneath.
class FinanceTotalCard extends StatelessWidget {
  const FinanceTotalCard({
    super.key,
    required this.label,
    required this.amount,
    required this.subtitle,
    required this.currency,
    this.stats = const [],
    this.inverse = false,
    this.artwork,
  });
  final String label, subtitle, currency;
  final int amount;
  final List<(String, int?)> stats;
  final String? artwork;

  /// Uses the inverse surface instead of the brand color (Expenses).
  final bool inverse;
  @override
  Widget build(BuildContext context) {
    const on = Colors.white;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: inverse
              ? const [Color(0xFF0A3314), Color(0xFF10451C), Color(0xFF176D18)]
              : const [Color(0xFF092D12), Color(0xFF0C431A), Color(0xFF12661A)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.lime.withValues(alpha: .2)),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: on),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: on.withValues(alpha: .94),
                        ),
                      ),
                      const SizedBox(height: 5),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          financeMoney(amount, currency),
                          style: const TextStyle(
                            fontSize: 31,
                            fontWeight: FontWeight.w800,
                            color: on,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: on.withValues(alpha: .78),
                        ),
                      ),
                    ],
                  ),
                ),
                if (artwork != null) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 88,
                    height: 90,
                    child: SvgPicture.asset(
                      artwork!,
                      excludeFromSemantics: true,
                    ),
                  ),
                ],
              ],
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = stats.length >= 3
                      ? (constraints.maxWidth < 270 ? 2 : 3)
                      : stats.length;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 8) / columns;
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (name, value) in stats)
                        Container(
                          width: width,
                          constraints: const BoxConstraints(minHeight: 72),
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .22),
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                name.toLowerCase().contains('cash')
                                    ? Icons.account_balance_wallet_outlined
                                    : name.toLowerCase().contains('bank')
                                    ? Icons.credit_card_outlined
                                    : Icons.bar_chart_rounded,
                                size: 19,
                                color: AppColors.lime,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: on.withValues(alpha: .8),
                                ),
                              ),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  value == null
                                      ? '—'
                                      : financeMoney(value, currency),
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: on,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FinanceShare {
  const FinanceShare(this.id, this.name, this.total, this.icon);
  final String? id;
  final String name;
  final int total;
  final IconData icon;
}

/// Category or source totals as a colored split bar plus ranked rows.
class FinanceBreakdown extends StatefulWidget {
  const FinanceBreakdown({
    super.key,
    required this.shares,
    required this.currency,
    required this.onSelect,
    this.selected,
  });
  final List<FinanceShare> shares;
  final String currency;
  final String? selected;
  final ValueChanged<String> onSelect;
  @override
  State<FinanceBreakdown> createState() => _FinanceBreakdownState();
}

class _FinanceBreakdownState extends State<FinanceBreakdown> {
  static const preview = 6;
  var all = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final shares = widget.shares;
    final total = shares.fold<int>(0, (n, s) => n + math.max(0, s.total));
    Color color(int i) => financeShareColors[i % financeShareColors.length];
    final shown = all ? shares.length : math.min(preview, shares.length);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: total == 0
                  ? ColoredBox(color: scheme.outline.withValues(alpha: .3))
                  : Row(
                      children: [
                        for (final (i, s) in shares.indexed)
                          if (s.total > 0)
                            Expanded(
                              flex: s.total,
                              child: ColoredBox(color: color(i)),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 8),
          for (final (i, s) in shares.take(shown).indexed)
            Material(
              color: s.id != null && s.id == widget.selected
                  ? scheme.primary.withValues(alpha: .1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: s.id == null ? null : () => widget.onSelect(s.id!),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color(i).withValues(alpha: .18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(s.icon, size: 18, color: color(i)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              total == 0
                                  ? '0%'
                                  : '${(math.max(0, s.total) / total * 100).round()}%',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            financeMoney(s.total, widget.currency),
                            textAlign: TextAlign.right,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (shares.length > preview)
            TextButton(
              onPressed: () => setState(() => all = !all),
              child: Text(all ? 'Show fewer' : 'Show all ${shares.length}'),
            ),
        ],
      ),
    );
  }
}

/// Entries grouped under a day header with that day's total, one card per day.
class FinanceDayGroups<T> extends StatelessWidget {
  const FinanceDayGroups({
    super.key,
    required this.items,
    required this.dayOf,
    required this.builder,
    required this.currency,
    this.amountOf,
    this.today,
  });
  final List<T> items;
  final String Function(T) dayOf;
  final int Function(T)? amountOf;
  final Widget Function(T) builder;
  final String currency;
  final String? today;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groups = <(String, List<T>)>[];
    for (final item in items) {
      final raw = dayOf(item),
          day = raw.length >= 10 ? raw.substring(0, 10) : raw;
      if (groups.isEmpty || groups.last.$1 != day) {
        groups.add((day, [item]));
      } else {
        groups.last.$2.add(item);
      }
    }
    final muted = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (day, group) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, right: 4, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(financeDayLabel(day, today), style: muted),
                ),
                if (amountOf != null)
                  Text(
                    financeMoney(
                      group.fold(0, (n, i) => n + amountOf!(i)),
                      currency,
                    ),
                    style: muted,
                  ),
              ],
            ),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, item) in group.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 64),
                  builder(item),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
