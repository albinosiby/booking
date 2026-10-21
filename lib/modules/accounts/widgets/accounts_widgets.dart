import '../../workspace/widgets/workspace_business_order.dart';
import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/accounts_models.dart';
import '../../bookings/models/booking_models.dart';

class FinanceScopePicker extends StatelessWidget {
  const FinanceScopePicker({
    super.key,
    required this.catalog,
    required this.business,
    required this.space,
    required this.onChanged,
    this.sharedLabel = 'All businesses',
    this.enabled = true,
  });
  final FinanceCatalog catalog;
  final String? business, space;
  final void Function(String?, String?) onChanged;
  final String sharedLabel;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      AppPicker(
        label: 'Business',
        value: business ?? '',
        enabled: enabled,
        items: [
          PickerItem('', sharedLabel),
          ...orderedWorkspaceBusinesses(
            context,
            catalog.businesses,
            (b) => b.id,
          ).map((b) => PickerItem(b.id, b.name)),
        ],
        onChanged: (v) => onChanged(v.isEmpty ? null : v, null),
      ),
      if (business != null) ...[
        const SizedBox(height: 12),
        AppPicker(
          label: 'Space',
          value: space ?? '',
          enabled: enabled,
          items: [
            const PickerItem('', 'All spaces'),
            ...catalog.businesses
                .where((b) => b.id == business)
                .expand((b) => b.spaces)
                .map((s) => PickerItem(s.id, s.name)),
          ],
          onChanged: (v) => onChanged(business, v.isEmpty ? null : v),
        ),
      ],
    ],
  );
}

Future<FinanceFilter?> chooseFinanceDates(
  BuildContext context,
  FinanceFilter filter,
) async {
  final range = await showDateRangePicker(
    context: context,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100, 12, 31),
    initialDateRange: DateTimeRange(
      start: DateTime.parse(filter.from),
      end: DateTime.parse(filter.until),
    ),
  );
  return range == null
      ? null
      : filter.dates(bookingDate(range.start), bookingDate(range.end));
}

class FinanceSection extends StatelessWidget {
  const FinanceSection(this.title, {super.key, this.action, this.onTap});
  final String title;
  final String? action;
  final VoidCallback? onTap;
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
        if (action != null) TextButton(onPressed: onTap, child: Text(action!)),
      ],
    ),
  );
}

class FinanceTransactionTile extends StatelessWidget {
  const FinanceTransactionTile({
    super.key,
    required this.entry,
    required this.currency,
    this.onTap,
    this.label,
  });
  final FinanceTransaction entry;
  final String currency;
  final VoidCallback? onTap;

  /// Replaces the entry kind in the subtitle, e.g. the income source.
  final String? label;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final transfer = entry.kind == 'transfer', positive = entry.amount >= 0;
    final tone = transfer
        ? scheme.onSurfaceVariant
        : positive
        ? scheme.primary
        : scheme.error;
    final stamp = financeStamp(entry.date);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: tone.withValues(alpha: .12),
              child: Icon(
                transfer
                    ? Icons.swap_horiz
                    : positive
                    ? Icons.south_west
                    : Icons.north_east,
                color: tone,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.bookingReference ?? entry.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${label ?? financeLabel(entry.kind)} · ${entry.business ?? 'Shared'} · ${stamp.length > 11 ? stamp.substring(11) : stamp}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                transfer
                    ? financeMoney(entry.amount, currency)
                    : positive
                    ? '+${financeMoney(entry.amount, currency)}'
                    : '−${financeMoney(-entry.amount, currency)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: positive && !transfer ? scheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<DateTime?> chooseFinanceDateTime(
  BuildContext context,
  DateTime current,
) async {
  final d = await showDatePicker(
    context: context,
    initialDate: current,
    firstDate: DateTime(2000),
    lastDate: DateTime.now(),
  );
  if (d == null || !context.mounted) return null;
  final t = await showAppTimePicker(
    context: context,
    initialTime:
        '${current.hour.toString().padLeft(2, '0')}:${current.minute.toString().padLeft(2, '0')}',
  );
  if (t == null) return null;
  final parts = t.split(':');
  return DateTime(
    d.year,
    d.month,
    d.day,
    int.parse(parts[0]),
    int.parse(parts[1]),
  );
}
