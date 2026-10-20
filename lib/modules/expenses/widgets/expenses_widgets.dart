import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/expense_models.dart';

const expenseMonths = [
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
IconData expenseCategoryIcon(String name) {
  final n = name.toLowerCase();
  if (n.contains('maint')) return Icons.build_outlined;
  if (n.contains('food')) return Icons.restaurant_outlined;
  if (n.contains('clean')) return Icons.cleaning_services_outlined;
  if (n.contains('util')) return Icons.bolt_outlined;
  if (n.contains('staff')) return Icons.groups_outlined;
  if (n.contains('equip')) return Icons.inventory_2_outlined;
  if (n.contains('rent')) return Icons.home_work_outlined;
  if (n.contains('market')) return Icons.campaign_outlined;
  if (n.contains('transport')) return Icons.local_shipping_outlined;
  return Icons.category_outlined;
}

class ExpenseChart extends StatelessWidget {
  const ExpenseChart({
    super.key,
    required this.values,
    required this.filter,
    required this.currency,
    required this.onMonth,
  });
  final List<int> values;
  final ExpenseFilter filter;
  final String currency;
  final ValueChanged<int> onMonth;
  @override
  Widget build(BuildContext context) {
    final max = values.fold<int>(1, (n, v) => math.max(n, v.abs()));
    final colors = Theme.of(context).colorScheme;
    Widget bar(int i) => Semantics(
      button: filter.yearly,
      label:
          '${filter.yearly ? expenseMonths[i] : 'Day ${i + 1}'}: ${financeMoney(values[i], currency)}',
      child: Tooltip(
        message: financeMoney(values[i], currency),
        child: InkWell(
          onTap: filter.yearly ? () => onMonth(i + 1) : null,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: filter.yearly ? 48 : 32,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  width: filter.yearly ? 24 : 14,
                  height: values[i] == 0
                      ? 3
                      : math.max(4, 112 * values[i].abs() / max),
                  decoration: BoxDecoration(
                    color: values[i] == 0
                        ? colors.outlineVariant
                        : values[i] < 0
                        ? colors.error
                        : colors.primary.withValues(alpha: .75),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  filter.yearly ? expenseMonths[i] : '${i + 1}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          filter.yearly
              ? 'Monthly expenses · tap a month to explore'
              : 'Daily expenses',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 168,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [for (var i = 0; i < values.length; i++) bar(i)],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Reversals reduce the total on the date they were recorded.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.item,
    required this.currency,
    required this.onTap,
  });
  final ExpenseItem item;
  final String currency;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(vertical: 8),
    leading: CircleAvatar(
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      child: Icon(
        expenseCategoryIcon(item.category),
        color: Theme.of(context).colorScheme.onPrimaryContainer,
      ),
    ),
    title: Text(item.reason, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: Text(
      '${item.category} · ${item.date.substring(0, 10)}\n${item.business ?? 'Organization'}${item.space == null ? '' : ' / ${item.space}'}${item.invoicesCount > 0 ? ' · ${item.invoicesCount} invoices' : ''}',
    ),
    isThreeLine: true,
    trailing: Text(
      '${item.originalId != null ? '−' : ''}${financeMoney(item.amount.abs(), currency)}',
      style: const TextStyle(fontWeight: FontWeight.w700),
    ),
    onTap: onTap,
  );
}
