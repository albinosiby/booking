import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/accounts_models.dart';
import 'monthly_finance_chart.dart';

/// Monthly/yearly switch with a period stepper, shared by the Expenses and
/// Income pages. Tapping the period label opens a calendar.
class FinancePeriodBar extends StatelessWidget {
  const FinancePeriodBar({
    super.key,
    required this.anchor,
    required this.yearly,
    required this.onChanged,
  });
  final DateTime anchor;
  final bool yearly;
  final void Function(DateTime anchor, bool yearly) onChanged;

  Future<void> _choose(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: yearly
          ? 'Choose a date in the year'
          : 'Choose a date in the month',
    );
    if (d != null) onChanged(d, yearly);
  }

  void _step(int by) => onChanged(
    yearly
        ? DateTime(anchor.year + by)
        : DateTime(anchor.year, anchor.month + by),
    yearly,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final last = yearly
        ? DateTime(anchor.year, 12, 31)
        : DateTime(anchor.year, anchor.month + 1, 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('Monthly')),
            ButtonSegment(value: true, label: Text('Yearly')),
          ],
          selected: {yearly},
          onSelectionChanged: (v) => onChanged(anchor, v.first),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outline.withValues(alpha: .5)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous period',
                onPressed: () => _step(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Tooltip(
                  message: 'Choose period',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _choose(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  yearly
                                      ? '${anchor.year}'
                                      : '${financeMonths[anchor.month - 1]} ${anchor.year}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.calendar_month_outlined,
                                size: 16,
                                color: scheme.primary,
                              ),
                            ],
                          ),
                          Text(
                            '1 ${financeMonths[yearly ? 0 : anchor.month - 1]} – ${last.day} ${financeMonths[last.month - 1]}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next period',
                onPressed: () => _step(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Bar per day (monthly) or per month (yearly), sized to fit the card.
/// Tapping a month drills into it; tapping a day selects its ledger.
class FinancePeriodChart extends StatelessWidget {
  const FinancePeriodChart({
    super.key,
    required this.values,
    required this.yearly,
    required this.currency,
    required this.onMonth,
    required this.yearlyTitle,
    required this.monthlyTitle,
    this.note,
    this.onDay,
    this.selectedDay,
    this.anchor,
    this.onClearDay,
  });
  final List<int> values;
  final bool yearly;
  final String currency, yearlyTitle, monthlyTitle;
  final String? note;
  final ValueChanged<int> onMonth;
  final ValueChanged<int>? onDay;
  final int? selectedDay;
  final DateTime? anchor;
  final VoidCallback? onClearDay;

  String _name(int i) => yearly ? financeMonths[i] : 'Day ${i + 1}';

  @override
  Widget build(BuildContext context) {
    const height = 120.0;
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final max = values.fold<int>(0, (n, v) => math.max(n, v.abs()));
    final peak = max == 0 ? -1 : values.indexWhere((v) => v.abs() == max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          yearly ? yearlyTitle : monthlyTitle,
          style: theme.textTheme.titleSmall,
        ),
        if (peak >= 0)
          Text(
            'Highest: ${_name(peak)} · ${financeMoney(values[peak], currency)}',
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final column = constraints.maxWidth / math.max(1, values.length);
            final bar = math.min(yearly ? 18.0 : 8.0, column * .6);
            String label(int i) {
              if (yearly) {
                return column >= 30
                    ? financeMonths[i]
                    : financeMonths[i].substring(0, 1);
              }
              final day = i + 1;
              return day == 1 || day % 5 == 0 ? '$day' : '';
            }

            VoidCallback? select(int i) => yearly
                ? () => onMonth(i + 1)
                : onDay == null
                ? null
                : () => onDay!(i + 1);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Semantics(
                      button: yearly || onDay != null,
                      selected: !yearly && selectedDay == i + 1,
                      label:
                          '${_name(i)}: ${financeMoney(values[i], currency)}',
                      excludeSemantics: true,
                      onTap: select(i),
                      child: Tooltip(
                        message:
                            '${_name(i)} · ${financeMoney(values[i], currency)}',
                        child: InkWell(
                          key: ValueKey('finance-bar-$i'),
                          onTap: select(i),
                          borderRadius: BorderRadius.circular(6),
                          child: Column(
                            children: [
                              Container(
                                height: height,
                                decoration: BoxDecoration(
                                  color: !yearly && selectedDay == i + 1
                                      ? scheme.primary.withValues(alpha: .12)
                                      : null,
                                  borderRadius: BorderRadius.circular(6),
                                  border: !yearly && selectedDay == i + 1
                                      ? Border.all(color: scheme.primary)
                                      : null,
                                ),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: bar,
                                    height: values[i] == 0
                                        ? 2
                                        : math.max(
                                            4,
                                            height * values[i].abs() / max,
                                          ),
                                    decoration: BoxDecoration(
                                      color: values[i] == 0
                                          ? scheme.outlineVariant
                                          : values[i] < 0
                                          ? scheme.error
                                          : scheme.primary.withValues(
                                              alpha: i == peak ? 1 : .55,
                                            ),
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(bar / 2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                label(i),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                textScaler: TextScaler.noScaling,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: !yearly && selectedDay == i + 1
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (!yearly && onDay != null && selectedDay == null) ...[
          const SizedBox(height: 10),
          Text(
            'Tap a day to view its transactions.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (!yearly &&
            selectedDay != null &&
            anchor != null &&
            onClearDay != null)
          FinanceDaySelection(
            date: DateTime(anchor!.year, anchor!.month, selectedDay!),
            total: values[selectedDay! - 1],
            currency: currency,
            onClear: onClearDay!,
          ),
        if (note != null) ...[
          const SizedBox(height: 10),
          Text(note!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Selected calendar date and chart total, independent of ledger pagination.
class FinanceDaySelection extends StatelessWidget {
  const FinanceDaySelection({
    super.key,
    required this.date,
    required this.total,
    required this.currency,
    required this.onClear,
  });
  final DateTime date;
  final int total;
  final String currency;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 16,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            '${date.day} ${financeMonths[date.month - 1]} ${date.year} · ${financeMoney(total, currency)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('Show all days')),
      ],
    ),
  );
}
