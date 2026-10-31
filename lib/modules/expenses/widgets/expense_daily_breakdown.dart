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
        Text(
          selectedDay == null ? 'Expenses by day' : 'Selected day’s expenses',
          style: theme.textTheme.titleSmall,
        ),
        if (selectedDay != null) ...[
          TextButton(onPressed: onClearDay, child: const Text('Show all days')),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
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
            ],
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
                ? scheme.primary.withValues(alpha: .12)
                : scheme.surfaceContainerHighest.withValues(alpha: .45),
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              key: ValueKey('expense-day-${entry.key}'),
              onTap: selectedDay == null
                  ? () => onDay(DateTime.parse(entry.key).day)
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${DateTime.parse(entry.key).day} ${financeMonths[anchor.month - 1]} ${anchor.year}',
                      style: theme.textTheme.labelLarge,
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      children: [
                        Text(
                          'Expenses ${financeMoney(entry.value.gross, currency)}',
                        ),
                        if (entry.value.reversals != 0)
                          Text(
                            'Reversals ${financeMoney(entry.value.reversals, currency)}',
                          ),
                        Text(
                          'Net spent ${financeMoney(entry.value.net, currency)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
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
                          child: Text(
                            '${purpose.category} · ${purpose.reason} · ${purpose.space} · ${financeMoney(purpose.amount, currency)}',
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
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          for (final method in entry.value.methods.entries)
                            if (method.value != 0)
                              Text(
                                '${financeLabel(method.key)} ${financeMoney(method.value, currency)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontWeight: FontWeight.w600,
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
