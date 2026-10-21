import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/expense_models.dart';

/// Presentation of the repository's typed expense; no data access happens here.
class ExpenseReceipt extends StatelessWidget {
  const ExpenseReceipt({
    super.key,
    required this.detail,
    required this.currency,
  });
  final ExpenseDetail detail;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExpenseReceiptHero(detail: detail, currency: currency),
        const ExpenseDetailHeading(title: 'Expense information'),
        ExpenseInformationCard(item: item),
        const ExpenseDetailHeading(title: 'Paid from'),
        ExpensePaymentsCard(item: item, currency: currency),
      ],
    );
  }
}

/// Total, category and date card, plus the reversal notice when reversed.
class ExpenseReceiptHero extends StatelessWidget {
  const ExpenseReceiptHero({
    super.key,
    required this.detail,
    required this.currency,
  });
  final ExpenseDetail detail;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final item = detail.item;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.receipt_long_outlined),
              ),
              const SizedBox(height: 16),
              Text(
                'TOTAL EXPENSE',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                financeMoney(item.amount, currency),
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  item.category,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                financeStamp(item.date),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (detail.reversed) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.undo_rounded, color: colors.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Reversed expense\nThe original expense is retained for your records.',
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Reason, business, space, staff and reference fields.
class ExpenseInformationCard extends StatelessWidget {
  const ExpenseInformationCard({
    super.key,
    required this.item,
    this.wide = false,
  });
  final ExpenseItem item;

  /// Lays the fields out in two columns on desktop.
  final bool wide;
  @override
  Widget build(BuildContext context) {
    final fields = [
      ExpenseDetailField(label: 'Reason', value: item.reason),
      ExpenseDetailField(
        label: 'Business',
        value: item.business ?? 'Organization-wide',
      ),
      if (item.space?.trim().isNotEmpty == true)
        ExpenseDetailField(label: 'Space', value: item.space!),
      if (item.staff.trim().isNotEmpty)
        ExpenseDetailField(label: 'Recorded by', value: item.staff),
      if (item.reference.trim().isNotEmpty)
        ExpenseDetailField(label: 'Reference', value: item.reference),
    ];
    return AppCard(
      padding: wide ? const EdgeInsets.all(22) : const EdgeInsets.all(18),
      child: wide
          ? AppGrid(minTileWidth: 240, maxColumns: 2, gap: 12, children: fields)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: fields,
            ),
    );
  }
}

/// Accounts and methods the expense was paid from.
class ExpensePaymentsCard extends StatelessWidget {
  const ExpensePaymentsCard({
    super.key,
    required this.item,
    required this.currency,
    this.wide = false,
  });
  final ExpenseItem item;
  final String currency;

  /// Pins amounts to the card's right edge on desktop.
  final bool wide;
  @override
  Widget build(BuildContext context) => item.lines.isEmpty
      ? const Text('No payment breakdown available')
      : AppCard(
          child: Column(
            children: [
              for (var i = 0; i < item.lines.length; i++) ...[
                if (i > 0)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1),
                  ),
                _PaymentLine(
                  line: item.lines[i],
                  currency: currency,
                  wide: wide,
                ),
              ],
            ],
          ),
        );
}

class ExpenseDetailHeading extends StatelessWidget {
  const ExpenseDetailHeading({super.key, required this.title, this.count});
  final String title;
  final int? count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (count != null)
          Text('$count', style: Theme.of(context).textTheme.labelLarge),
      ],
    ),
  );
}

class ExpenseDetailField extends StatelessWidget {
  const ExpenseDetailField({
    super.key,
    required this.label,
    required this.value,
  });
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(value, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}

class _PaymentLine extends StatelessWidget {
  const _PaymentLine({
    required this.line,
    required this.currency,
    this.wide = false,
  });
  final FinanceLine line;
  final String currency;
  final bool wide;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        child: Icon(
          line.method == 'cash'
              ? Icons.payments_outlined
              : Icons.account_balance_outlined,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final account = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.accountName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  financeLabel(line.method),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
            final amount = Text(
              financeMoney(line.amount.abs(), currency),
              style: Theme.of(context).textTheme.titleSmall,
            );
            if (constraints.maxWidth < 300 ||
                MediaQuery.textScalerOf(context).scale(14) > 20) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [account, const SizedBox(height: 8), amount],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: account),
                const SizedBox(width: 12),
                if (wide) amount else Flexible(child: amount),
              ],
            );
          },
        ),
      ),
    ],
  );
}
