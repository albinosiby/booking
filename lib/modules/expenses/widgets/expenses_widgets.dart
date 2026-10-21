import 'package:flutter/material.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/expense_models.dart';
import '../../accounts/widgets/finance_period_widgets.dart';

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
  Widget build(BuildContext context) => FinancePeriodChart(
    values: values,
    yearly: filter.yearly,
    currency: currency,
    onMonth: onMonth,
    yearlyTitle: 'Monthly expenses · tap a month to explore',
    monthlyTitle: 'Daily expenses',
    note: 'Reversals reduce the total on the date they were recorded.',
  );
}

class ExpenseTile extends StatelessWidget {
  const ExpenseTile({
    super.key,
    required this.item,
    required this.currency,
    required this.onTap,
    this.wide = false,
  });
  final ExpenseItem item;
  final String currency;
  final VoidCallback onTap;

  /// Desktop rows pin the amount to the right edge with a chevron.
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reversal = item.originalId != null;
    final amount = Text(
      '${reversal || item.amount < 0 ? '+' : '−'}${financeMoney(item.amount.abs(), currency)}',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        color: reversal ? scheme.primary : null,
      ),
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: scheme.error.withValues(alpha: .12),
              child: Icon(
                reversal ? Icons.undo : expenseCategoryIcon(item.category),
                color: scheme.error,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      reversal ? 'Reversal · ${item.category}' : item.category,
                      '${item.business ?? 'Organization'}${item.space == null ? '' : ' / ${item.space}'}',
                      if (item.invoicesCount > 0)
                        '${item.invoicesCount} invoice${item.invoicesCount == 1 ? '' : 's'}',
                    ].join(' · '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (wide) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 110),
                child: amount,
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ] else
              Flexible(child: amount),
          ],
        ),
      ),
    );
  }
}
