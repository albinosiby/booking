import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/accounts_models.dart';
import '../models/accounts_screen_models.dart';

const financeMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
String financeMonthLabel(String month) {
  final parsed = DateTime.tryParse('$month-01');
  return parsed == null
      ? month
      : '${financeMonths[parsed.month - 1]} ${parsed.year}';
}

String _monthShort(String month) {
  final m = int.tryParse(month.length >= 7 ? month.substring(5, 7) : '');
  return m == null || m < 1 || m > 12 ? month : financeMonths[m - 1];
}

/// Short axis amount: lakh/crore for INR, k/M otherwise.
String financeCompact(int minor, String currency) {
  final v = minor / 100, a = v.abs(), sign = v < 0 ? '-' : '';
  final steps = currency == 'INR'
      ? const [(1e7, 'Cr'), (1e5, 'L'), (1e3, 'k')]
      : const [(1e6, 'M'), (1e3, 'k')];
  var text = a.round().toString();
  for (final (size, unit) in steps) {
    if (a >= size) {
      final n = a / size;
      text =
          '${n >= 10 ? n.round() : n.toStringAsFixed(1).replaceFirst('.0', '')}$unit';
      break;
    }
  }
  return '$sign${currency == 'INR' ? '₹' : ''}$text';
}

const _note =
    'Income includes received booking payments and extra income. Transfers are excluded.';

class MonthlyFinancePanel extends StatelessWidget {
  const MonthlyFinancePanel({
    super.key,
    required this.model,
    required this.currency,
    required this.onMonth,
  });
  final AccountsOverviewModel model;
  final String currency;
  final ValueChanged<String> onMonth;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context),
        months = model.overview?.monthlyAnalysis ?? <FinanceMonthAnalysis>[];
    final selected = model.activeMonth;
    if (months.isEmpty || selected == null) {
      return const AppCard(
        child: Text('Monthly analysis is unavailable right now.'),
      );
    }
    final first = months.first.month.substring(0, 4),
        last = months.last.month.substring(0, 4);
    final index = months.indexWhere((m) => m.month == selected.month);
    final previous = index > 0 ? months[index - 1] : null;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Monthly comparison',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                first == last ? first : '$first–$last',
                style: theme.textTheme.bodySmall,
              ),
              Tooltip(
                message: _note,
                triggerMode: TooltipTriggerMode.tap,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.info_outline,
                    size: 18,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              _Legend(label: 'Income', color: theme.colorScheme.primary),
              _Legend(label: 'Expenses', color: theme.colorScheme.error),
            ],
          ),
          const SizedBox(height: 14),
          _MonthBars(
            months: months,
            selected: selected.month,
            currency: currency,
            onMonth: onMonth,
          ),
          const SizedBox(height: 18),
          Text(
            financeMonthLabel(selected.month),
            key: const ValueKey('finance-selected-month'),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          _MonthSummary(
            month: selected,
            previous: previous,
            currency: currency,
          ),
          const SizedBox(height: 18),
          _SpaceBreakdown(
            key: ValueKey('finance-space-breakdown-${selected.month}'),
            rows: model.spaceBreakdown,
            currency: currency,
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 6),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _MonthBars extends StatefulWidget {
  const _MonthBars({
    required this.months,
    required this.selected,
    required this.currency,
    required this.onMonth,
  });
  final List<FinanceMonthAnalysis> months;
  final String selected, currency;
  final ValueChanged<String> onMonth;
  @override
  State<_MonthBars> createState() => _MonthBarsState();
}

class _MonthBarsState extends State<_MonthBars> {
  static const height = 140.0, axis = 40.0, minColumn = 28.0;
  final controller = ScrollController();
  void reveal() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted || !controller.hasClients) return;
    final index = widget.months.indexWhere((m) => m.month == widget.selected);
    if (index < 0) return;
    controller.jumpTo(
      (index * minColumn -
              (controller.position.viewportDimension - minColumn) / 2)
          .clamp(0.0, controller.position.maxScrollExtent),
    );
  });
  @override
  void initState() {
    super.initState();
    reveal();
  }

  @override
  void didUpdateWidget(covariant _MonthBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selected != widget.selected) reveal();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final values = widget.months.expand((m) => [m.income, m.expenses]);
    final high = values.fold<int>(0, math.max),
        low = values.fold<int>(0, math.min);
    final span = math.max(1, high - low);
    double y(num v) => height * (high - v) / span;
    final ticks = {high, if (low < 0) 0 else high ~/ 2, low}.toList();
    final grid = scheme.outline.withValues(alpha: .35);
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth - axis;
        final column = math.max(
          minColumn,
          available / math.max(1, widget.months.length),
        );
        final chart = SizedBox(
          width: column * widget.months.length,
          child: Stack(
            children: [
              for (final t in ticks)
                Positioned(
                  left: 0,
                  right: 0,
                  top: y(t).clamp(0.0, height - 1),
                  child: Container(
                    height: t == 0 ? 1 : .5,
                    color: t == 0 ? scheme.outline : grid,
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final m in widget.months) _column(context, m, column, y),
                ],
              ),
            ],
          ),
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: axis,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final t in ticks)
                    Positioned(
                      right: 6,
                      top: (y(t) - 7).clamp(-4.0, height - 10),
                      child: Text(
                        financeCompact(t, widget.currency),
                        textScaler: TextScaler.noScaling,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: column * widget.months.length <= available + .5
                  ? chart
                  : SingleChildScrollView(
                      controller: controller,
                      scrollDirection: Axis.horizontal,
                      child: chart,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _column(
    BuildContext context,
    FinanceMonthAnalysis month,
    double width,
    double Function(num) y,
  ) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final active = month.month == widget.selected;
    final bar = math.min(8.0, (width - 6) / 2);
    Widget column(int amount, Color color, double left) {
      final top = y(math.max(0, amount)), bottom = y(math.min(0, amount));
      return Positioned(
        left: left,
        top: top,
        width: bar,
        height: math.max(amount == 0 ? 0 : 2, bottom - top),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: active ? 1 : .4),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(amount >= 0 ? 3 : 0),
              bottom: Radius.circular(amount < 0 ? 3 : 0),
            ),
          ),
        ),
      );
    }

    final left = (width - bar * 2 - 2) / 2;
    return Semantics(
      button: true,
      selected: active,
      label:
          '${financeMonthLabel(month.month)}, income ${financeMoney(month.income, widget.currency)}, expenses ${financeMoney(month.expenses, widget.currency)}',
      excludeSemantics: true,
      onTap: () => widget.onMonth(month.month),
      child: InkWell(
        key: ValueKey('finance-month-${month.month}'),
        borderRadius: BorderRadius.circular(8),
        onTap: () => widget.onMonth(month.month),
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              Container(
                height: height,
                decoration: BoxDecoration(
                  color: active
                      ? scheme.primary.withValues(alpha: .1)
                      : Colors.transparent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    column(month.income, scheme.primary, left),
                    column(month.expenses, scheme.error, left + bar + 2),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _monthShort(month.month).substring(0, 1),
                textScaler: TextScaler.noScaling,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  color: active ? scheme.onSurface : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({
    required this.month,
    required this.previous,
    required this.currency,
  });
  final FinanceMonthAnalysis month;
  final FinanceMonthAnalysis? previous;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    String? change(int now, int? before) {
      if (before == null || before == 0) return null;
      final pct = ((now - before) / before.abs() * 100).round();
      final since = _monthShort(previous!.month);
      return pct == 0
          ? 'Same as $since'
          : '${pct > 0 ? '↑' : '↓'} ${pct.abs()}% vs $since';
    }

    Color? tone(int now, int? before, {required bool upIsGood}) {
      if (before == null || before == 0 || now == before) return null;
      return (now > before) == upIsGood ? scheme.primary : scheme.error;
    }

    final positive = month.net >= 0;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _tile(
          context,
          'Income',
          month.income,
          change(month.income, previous?.income),
          tone(month.income, previous?.income, upIsGood: true),
        ),
        _tile(
          context,
          'Expenses',
          month.expenses,
          change(month.expenses, previous?.expenses),
          tone(month.expenses, previous?.expenses, upIsGood: false),
        ),
        _tile(
          context,
          'Net',
          month.net,
          month.refunds != 0
              ? 'Refunds ${financeMoney(month.refunds, currency)}'
              : change(month.net, previous?.net),
          month.refunds != 0
              ? null
              : tone(month.net, previous?.net, upIsGood: true),
          accent: positive ? scheme.primary : scheme.error,
        ),
      ],
    );
  }

  Widget _tile(
    BuildContext context,
    String label,
    int amount,
    String? note,
    Color? noteColor, {
    Color? accent,
  }) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 88),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: (accent ?? theme.colorScheme.outline).withValues(
            alpha: accent == null ? .12 : .14,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: accent),
            ),
            Text(
              financeMoney(amount, currency),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            if (note != null)
              Text(
                note,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: noteColor ?? theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SpaceBreakdown extends StatefulWidget {
  const _SpaceBreakdown({
    super.key,
    required this.rows,
    required this.currency,
  });
  final List<FinanceSpaceMonth> rows;
  final String currency;
  @override
  State<_SpaceBreakdown> createState() => _SpaceBreakdownState();
}

class _SpaceBreakdownState extends State<_SpaceBreakdown> {
  static const preview = 4;
  var all = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final rows = [...widget.rows]
      ..sort((a, b) {
        final c = b.income.compareTo(a.income);
        return c != 0 ? c : a.label.compareTo(b.label);
      });
    final total = rows.fold<int>(0, (n, r) => n + math.max(0, r.income));
    final shown = all ? rows : rows.take(preview);
    String money(int n) => financeMoney(n, widget.currency);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('By space', style: theme.textTheme.titleSmall),
            ),
            Text('Share of income', style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No space activity this month.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        for (final r in shown)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        r.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '${money(r.net)} net',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: r.net < 0 ? scheme.error : null,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : math.max(0, r.income) / total,
                          minHeight: 5,
                          color: scheme.primary,
                          backgroundColor: scheme.outline.withValues(
                            alpha: .25,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      total == 0
                          ? '0%'
                          : '${(math.max(0, r.income) / total * 100).round()}%',
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    'In ${money(r.income)}',
                    'Out ${money(r.expenses)}',
                    if (r.refunds != 0) 'Refunds ${money(r.refunds)}',
                  ].join(' · '),
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        if (rows.length > preview)
          TextButton(
            onPressed: () => setState(() => all = !all),
            child: Text(all ? 'Show fewer' : 'Show all ${rows.length} spaces'),
          ),
      ],
    );
  }
}
