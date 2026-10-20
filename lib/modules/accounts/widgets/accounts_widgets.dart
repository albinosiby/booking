import '../../workspace/widgets/workspace_business_order.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

class FinancePeriodPicker extends StatelessWidget {
  const FinancePeriodPicker({
    super.key,
    required this.filter,
    required this.onChanged,
    this.today,
  });
  final FinanceFilter filter;
  final ValueChanged<FinanceFilter> onChanged;
  final String? today;
  @override
  Widget build(BuildContext context) {
    final d = DateTime.tryParse(today ?? '') ?? DateTime.now();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in ['Today', 'This month', 'This year', 'Custom'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(p),
                    onPressed: () async {
                      if (p == 'Custom') {
                        final next = await chooseFinanceDates(context, filter);
                        if (next != null) onChanged(next);
                      } else {
                        final start = p == 'Today'
                            ? d
                            : p == 'This month'
                            ? DateTime(d.year, d.month)
                            : DateTime(d.year);
                        onChanged(
                          filter.dates(bookingDate(start), bookingDate(d)),
                        );
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '${filter.from} → ${filter.until}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
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

class FinanceStat extends StatelessWidget {
  const FinanceStat(
    this.title,
    this.value, {
    super.key,
    this.icon = Icons.payments_outlined,
    this.note,
  });
  final String title, value;
  final IconData icon;
  final String? note;
  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 20),
        const SizedBox(height: 12),
        Text(title, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        if (note != null) ...[
          const SizedBox(height: 6),
          Text(note!, style: Theme.of(context).textTheme.bodySmall),
        ],
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
  });
  final FinanceTransaction entry;
  final String currency;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final transfer = entry.kind == 'transfer', positive = entry.amount >= 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: .1),
              child: Icon(
                transfer
                    ? Icons.swap_horiz
                    : positive
                    ? Icons.south_west
                    : Icons.north_east,
                color: Theme.of(context).colorScheme.primary,
                size: 20,
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
                  const SizedBox(height: 4),
                  Text(
                    '${financeLabel(entry.kind)} · ${entry.business ?? 'Shared'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    financeStamp(entry.date),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${!transfer && positive ? '+' : ''}${financeMoney(entry.amount, currency)}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: positive && !transfer
                      ? Theme.of(context).colorScheme.primary
                      : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> openFinanceActions(
  BuildContext context,
  FinanceCatalog catalog,
) async {
  final kind = await showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (c) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (catalog.canIncome)
            ListTile(
              leading: const Icon(Icons.south_west),
              title: const Text('Add extra income'),
              onTap: () => Navigator.pop(c, 'income'),
            ),
          if (catalog.canManage)
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Transfer money'),
              onTap: () => Navigator.pop(c, 'transfer'),
            ),
        ],
      ),
    ),
  );
  if (context.mounted && kind != null) context.push('/accounts/entry/$kind');
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
