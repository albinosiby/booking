import 'package:flutter/material.dart';
import '../../accounts/models/accounts_models.dart';
import '../../accounts/widgets/monthly_finance_chart.dart';
import '../models/income_models.dart';

/// Complete daily totals from the overview, independent of ledger pagination.
class IncomeDailyBreakdown extends StatelessWidget {
  const IncomeDailyBreakdown({
    super.key,
    required this.summary,
    required this.anchor,
    required this.currency,
    required this.selectedDay,
    required this.onDay,
    required this.onClearDay,
    this.onAddIncome,
    this.onDownloadDay,
    this.exporting = false,
  });

  final IncomeSummary summary;
  final DateTime anchor;
  final String currency;
  final int? selectedDay;
  final ValueChanged<int> onDay;
  final VoidCallback onClearDay;
  final VoidCallback? onAddIncome, onDownloadDay;
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
        const Divider(height: 26),
        Text(
          selectedDay == null ? 'Income by day' : 'Selected day’s income',
          style: theme.textTheme.titleSmall,
        ),
        if (selectedDay != null) ...[
          TextButton(onPressed: onClearDay, child: const Text('Show all days')),
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = <Widget>[
                if (onAddIncome != null)
                  OutlinedButton.icon(
                    key: const ValueKey('income-day-add'),
                    onPressed: onAddIncome,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add income'),
                  ),
                if (onDownloadDay != null)
                  FilledButton.tonalIcon(
                    key: const ValueKey('income-day-download'),
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
                    'Total income ${financeMoney(0, currency)} · Net cash received ${financeMoney(0, currency)} · Net bank received ${financeMoney(0, currency)}',
                  ),
                Text(
                  selectedDay == null
                      ? 'No income or refunds in this month.'
                      : 'No income or refunds on this day.',
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
              key: ValueKey('income-day-${entry.key}'),
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
                          '${selectedDay == null ? 'Income' : 'Total income'} ${financeMoney(entry.value.gross, currency)}',
                        ),
                        Text(
                          'Refunds ${financeMoney(entry.value.refunds, currency)}',
                        ),
                        Text(
                          '${selectedDay == null ? 'Net' : 'Net received'} ${financeMoney(entry.value.net, currency)}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (selectedDay != null) ...[
                          Text(
                            'Net cash received ${entry.value.methodBreakdownAvailable ? financeMoney(entry.value.cash, currency) : '—'}',
                          ),
                          Text(
                            'Net bank received ${entry.value.methodBreakdownAvailable ? financeMoney(entry.value.bank, currency) : '—'}',
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
                                        '${purpose.purpose} · ${purpose.space}',
                                      ),
                                      Text(
                                        financeMoney(purpose.amount, currency),
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${purpose.purpose} · ${purpose.space}',
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
                      '${entry.value.incomeCount} payments · ${entry.value.refundCount} refunds',
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
