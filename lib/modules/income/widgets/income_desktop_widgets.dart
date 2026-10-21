import 'package:flutter/material.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/income_models.dart';

/// Ledger row for the desktop income list: source, payment account and the
/// amount in a right-aligned column.
class IncomeLedgerRow extends StatelessWidget {
  const IncomeLedgerRow({
    super.key,
    required this.item,
    required this.currency,
    required this.icon,
    required this.onTap,
  });
  final IncomeItem item;
  final String currency;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final entry = item.entry;
    final positive = entry.amount >= 0;
    final tone = positive ? scheme.primary : scheme.error;
    final stamp = financeStamp(entry.date);
    final line = entry.lines.isEmpty ? null : entry.lines.first;
    final source = item.refund ? '${item.source} refund' : item.source;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: tone.withValues(alpha: .12),
              child: Icon(
                item.refund ? Icons.undo_rounded : icon,
                color: tone,
                size: 18,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.bookingReference ?? entry.reason,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$source · ${entry.business ?? 'Shared'} · ${stamp.length > 11 ? stamp.substring(11) : stamp}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: line == null
                  ? const SizedBox.shrink()
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.lines.length > 1
                              ? '${entry.lines.length} accounts'
                              : line.accountName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          financeLabel(line.method),
                          maxLines: 1,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 110),
              child: Text(
                positive
                    ? '+${financeMoney(entry.amount, currency)}'
                    : '−${financeMoney(-entry.amount, currency)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: positive ? scheme.primary : null,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
