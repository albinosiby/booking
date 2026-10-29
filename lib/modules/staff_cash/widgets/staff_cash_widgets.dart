import 'package:flutter/material.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/staff_cash_models.dart';

/// Reads "To hand over", "Owner to give you" or "All settled" from a signed holding.
class StaffCashHoldingCard extends StatelessWidget {
  const StaffCashHoldingCard({
    super.key,
    required this.holdingMinor,
    required this.currency,
  });
  final int holdingMinor;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = holdingMinor > 0
        ? 'Cash to hand over'
        : holdingMinor < 0
        ? 'Owner to give you'
        : 'Cash settled';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: scheme.onPrimary)),
          const SizedBox(height: 6),
          Text(
            financeMoney(holdingMinor.abs(), currency),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: scheme.onPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Current balance · carries across days',
            style: TextStyle(color: scheme.onPrimary),
          ),
        ],
      ),
    );
  }
}

class StaffCashAmountTile extends StatelessWidget {
  const StaffCashAmountTile(this.label, this.minor, this.currency, {super.key});
  final String label, currency;
  final int minor;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).dividerColor),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 4),
        Text(
          financeMoney(minor, currency),
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

String staffCashSettlementTitle(StaffCashSettlement s, String currency) =>
    s.collected
    ? 'Collected ${financeMoney(s.amountMinor, currency)} from ${s.staffName}'
    : 'Gave ${financeMoney(s.amountMinor, currency)} to ${s.staffName}';

String staffCashRemaining(int after, String currency) => after == 0
    ? 'Fully settled'
    : after > 0
    ? 'Still to hand over ${financeMoney(after, currency)}'
    : 'Still owed to staff ${financeMoney(-after, currency)}';

class StaffCashTransactionTile extends StatelessWidget {
  const StaffCashTransactionTile({
    super.key,
    required this.item,
    required this.currency,
  });
  final StaffCashTransaction item;
  final String currency;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        spacing: 16,
        runSpacing: 8,
        children: [
          Text(
            item.customer.isNotEmpty
                ? item.customer
                : item.reason.isNotEmpty
                ? item.reason
                : financeLabel(item.kind),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          Text(
            financeMoney(item.netMinor, currency),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: item.netMinor < 0
                  ? Theme.of(context).colorScheme.error
                  : null,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        [
          if (item.reference.isNotEmpty) item.reference,
          financeLabel(item.kind),
          if (item.methods.isNotEmpty)
            item.methods.map(financeLabel).join(' / '),
          if (item.space.isNotEmpty) item.space,
          item.time,
          item.mine ? 'You' : item.staffName,
        ].join(' · '),
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
}

class StaffCashSettlementTile extends StatelessWidget {
  const StaffCashSettlementTile({
    super.key,
    required this.item,
    required this.currency,
    this.personal = false,
  });
  final bool personal;
  final StaffCashSettlement item;
  final String currency;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      item.collected ? Icons.south_west : Icons.north_east,
      color: Theme.of(context).colorScheme.primary,
    ),
    title: Text(
      personal
          ? '${item.collected ? 'Given to owner' : 'Received from owner'} · ${financeMoney(item.amountMinor, currency)}'
          : staffCashSettlementTitle(item, currency),
    ),
    subtitle: Text(
      '${personal && item.balanceAfterMinor < 0 ? 'Owner still owes you ${financeMoney(-item.balanceAfterMinor, currency)}' : staffCashRemaining(item.balanceAfterMinor, currency)} · ${financeStamp(item.settledAt.toIso8601String())}'
      '${item.note.isEmpty ? '' : '\n${item.note}'}',
    ),
    isThreeLine: item.note.isNotEmpty,
  );
}
