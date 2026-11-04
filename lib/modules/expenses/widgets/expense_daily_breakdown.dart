import 'package:flutter/material.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/widgets/monthly_finance_chart.dart';
import '../models/expense_models.dart';

/// Daily totals come from the overview, so pagination cannot hide spending.
class ExpenseDailyBreakdown extends StatelessWidget {
  const ExpenseDailyBreakdown({
    super.key,
    required this.summary,
    required this.anchor,
    required this.currency,
    required this.selectedDay,
    required this.onDay,
    required this.onClearDay,
    this.onAddExpense,
    this.onDownloadDay,
    this.exporting = false,
  });

  final ExpenseSummary summary;
  final DateTime anchor;
  final String currency;
  final int? selectedDay;
  final ValueChanged<int> onDay;
  final VoidCallback onClearDay;
  final VoidCallback? onAddExpense, onDownloadDay;
  final bool exporting;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final entries = summary.dailyTotals.entries.where((entry) {
      final date = DateTime.tryParse(entry.key);
      return date != null &&
          date.year == anchor.year &&
          date.month == anchor.month &&
          (selectedDay == null || date.day == selectedDay);
    }).toList()..sort((a, b) => b.key.compareTo(a.key));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.format_list_bulleted_rounded, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                selectedDay == null
                    ? 'Expenses by day'
                    : 'Selected day’s expenses',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (selectedDay != null) ...[
          TextButton(onPressed: onClearDay, child: const Text('Show all days')),
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = <Widget>[
                if (onAddExpense != null)
                  OutlinedButton.icon(
                    key: const ValueKey('expense-day-add'),
                    onPressed: onAddExpense,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add expense'),
                  ),
                if (onDownloadDay != null)
                  FilledButton.tonalIcon(
                    key: const ValueKey('expense-day-download'),
                    onPressed: exporting ? null : onDownloadDay,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: Text(exporting ? 'Preparing…' : 'Download'),
                  ),
              ];
              if (constraints.maxWidth < 300) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final action in actions) action],
                );
              }
              return Wrap(spacing: 8, runSpacing: 4, children: actions);
            },
          ),
        ],
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (selectedDay != null)
                  Text(
                    'Total expenses ${financeMoney(0, currency)} · Net cash spent ${financeMoney(0, currency)} · Net bank spent ${financeMoney(0, currency)}',
                  ),
                Text(
                  selectedDay == null
                      ? 'No expenses or reversals in this month.'
                      : 'No expenses or reversals on this day.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        for (final entry in entries) ...[
          const SizedBox(height: 8),
          Material(
            color: selectedDay == DateTime.parse(entry.key).day
                ? scheme.primary.withValues(alpha: .10)
                : scheme.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: scheme.outline.withValues(alpha: .18)),
            ),
            child: InkWell(
              key: ValueKey('expense-day-${entry.key}'),
              onTap: selectedDay == null
                  ? () => onDay(DateTime.parse(entry.key).day)
                  : null,
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 47,
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${DateTime.parse(entry.key).day}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                financeMonths[anchor.month - 1],
                                style: theme.textTheme.labelSmall,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${anchor.year}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (selectedDay == null)
                          Icon(
                            Icons.chevron_right,
                            color: scheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          '${selectedDay == null ? 'Expenses' : 'Total expenses'} ${financeMoney(entry.value.gross, currency)}',
                        ),
                        Text(
                          'Reversals ${financeMoney(entry.value.reversals, currency)}',
                        ),
                        Text(
                          '${selectedDay == null ? 'Net' : 'Net spent'} ${financeMoney(entry.value.net, currency)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: scheme.primary,
                          ),
                        ),
                        if (selectedDay != null) ...[
                          Text(
                            'Net cash spent ${entry.value.methodBreakdownAvailable ? financeMoney(entry.value.cash, currency) : '—'}',
                          ),
                          Text(
                            'Net bank spent ${entry.value.methodBreakdownAvailable ? financeMoney(entry.value.bank, currency) : '—'}',
                          ),
                        ],
                      ],
                    ),
                    if (entry.value.purposes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      for (final purpose in entry.value.purposes)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: LayoutBuilder(
                            builder: (context, constraints) =>
                                constraints.maxWidth < 280 ||
                                    MediaQuery.textScalerOf(context).scale(14) >
                                        20
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${purpose.category} · ${purpose.reason} · ${purpose.space}',
                                      ),
                                      Text(
                                        financeMoney(purpose.amount, currency),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Icon(
                                        Icons.category_outlined,
                                        size: 16,
                                        color: scheme.primary,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          '${purpose.category} · ${purpose.reason} · ${purpose.space}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        financeMoney(purpose.amount, currency),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      if (entry.value.purposeCount >
                          entry.value.purposes.length)
                        Text(
                          '${entry.value.purposeCount - entry.value.purposes.length} more · select day for transactions',
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                    if (entry.value.methods.isNotEmpty) ...[
                      const Divider(height: 18),
                      Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Wrap(
                              spacing: 12,
                              runSpacing: 4,
                              children: [
                                for (final method
                                    in entry.value.methods.entries)
                                  if (method.value != 0)
                                    Text(
                                      '${financeLabel(method.key)} ${financeMoney(method.value, currency)}',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                    Text(
                      '${entry.value.expenseCount} expenses · ${entry.value.reversalCount} reversals',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
