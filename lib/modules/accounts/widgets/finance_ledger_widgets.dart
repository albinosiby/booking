import 'dart:math' as math;
import 'package:flutter/material.dart';
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

/// Bottom sheet listing [options]; returns the chosen ID, or null if dismissed.
Future<String?> showFinanceOptions(
  BuildContext context, {
  required String title,
  required List<FinanceOption> options,
  required String selected,
}) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (c) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: math.min(.9, .2 + options.length * .075),
    builder: (c, controller) => ListView(
      controller: controller,
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
  });
  final String label, subtitle, currency;
  final int amount;
  final List<(String, int)> stats;

  /// Uses the inverse surface instead of the brand color (Expenses).
  final bool inverse;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = inverse ? scheme.inverseSurface : scheme.primary,
        on = inverse ? scheme.onInverseSurface : scheme.onPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: on),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: on.withValues(alpha: .85),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                financeMoney(amount, currency),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 12, color: on.withValues(alpha: .8)),
            ),
            if (stats.isNotEmpty) ...[
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (name, value) in stats)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: on.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 11,
                              color: on.withValues(alpha: .8),
                            ),
                          ),
                          Text(
                            financeMoney(value, currency),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                ],
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
                        child: Text(
                          financeMoney(s.total, widget.currency),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
