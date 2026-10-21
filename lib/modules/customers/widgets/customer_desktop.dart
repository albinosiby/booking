import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/widgets/booking_widgets.dart';
import '../models/customer_models.dart';
import 'customer_plan_session.dart';

String customerInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((v) => v.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  return [
    parts.first,
    if (parts.length > 1) parts.last,
  ].map((v) => String.fromCharCode(v.runes.first)).join().toUpperCase();
}

class CustomerAvatar extends StatelessWidget {
  const CustomerAvatar({super.key, required this.name, this.radius = 20});
  final String name;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: CircleAvatar(
        radius: radius,
        backgroundColor: colors.primary.withValues(alpha: .12),
        foregroundColor: colors.primary,
        child: Text(
          customerInitials(name),
          style: TextStyle(
            fontSize: radius * .72,
            fontWeight: FontWeight.w700,
            color: colors.primary,
          ),
        ),
      ),
    );
  }
}

/// Headline figures for the customers shown on the current page of results.
class CustomerListStats extends StatelessWidget {
  const CustomerListStats({super.key, required this.state});
  final CustomerListModel state;
  @override
  Widget build(BuildContext context) {
    final items = state.items;
    final shared = items.where((c) => c.recordCount > 1).length;
    final records = items.fold(0, (sum, c) => sum + c.recordCount);
    return AppStatRow(
      key: const ValueKey('customer-list-stats'),
      children: [
        AppStatTile(
          highlight: true,
          icon: Icons.people_alt_outlined,
          label: 'Phone numbers',
          value: '${items.length}${state.next == null ? '' : '+'}',
          caption: state.query.isEmpty
              ? (state.next == null ? 'All customers' : 'Loaded so far')
              : 'Matching “${state.query}”',
        ),
        AppStatTile(
          icon: Icons.badge_outlined,
          label: 'Customer records',
          value: '$records',
          caption: 'Linked to these numbers',
        ),
        AppStatTile(
          icon: Icons.call_split_rounded,
          label: 'Shared numbers',
          value: '$shared',
          caption: 'More than one record',
        ),
      ],
    );
  }
}

/// Table-like directory of customers for desktop windows.
class CustomerTable extends StatelessWidget {
  const CustomerTable({super.key, required this.items});
  final List<CustomerSummary> items;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final head = theme.textTheme.labelSmall?.copyWith(
      color: colors.onSurfaceVariant,
      letterSpacing: 1.2,
      fontWeight: FontWeight.w700,
    );
    Widget row({
      required Widget phone,
      required Widget name,
      required Widget records,
      Widget? trailing,
    }) => Row(
      children: [
        Expanded(flex: 4, child: phone),
        Expanded(flex: 4, child: name),
        Expanded(flex: 3, child: records),
        SizedBox(width: 32, child: trailing),
      ],
    );
    return AppListCard(
      key: const ValueKey('customer-table'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
          child: row(
            phone: Text('PHONE NUMBER', style: head),
            name: Text('NAME', style: head),
            records: Text('RECORDS', style: head),
          ),
        ),
        for (final c in items)
          InkWell(
            key: ValueKey('customer-row-${c.id}'),
            onTap: () => context.push('/customers/${c.id}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: row(
                phone: Row(
                  children: [
                    CustomerAvatar(name: c.name),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                        c.phone,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                name: Text(
                  c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                records: Align(
                  alignment: Alignment.centerLeft,
                  child: c.recordCount > 1
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '${c.recordCount} linked customer records',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : Text(
                          '1 record',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Left column of the desktop customer page: identity and loaded totals.
class CustomerProfileCard extends StatelessWidget {
  const CustomerProfileCard({super.key, required this.state});
  final CustomerDetailModel state;
  @override
  Widget build(BuildContext context) {
    final s = state, c = s.customer!;
    final theme = Theme.of(context), colors = theme.colorScheme;
    int sum(int Function(BookingRecord b) f) =>
        s.bookings.fold(0, (total, b) => total + f(b));
    final scope = s.next == null ? 'All bookings' : 'Loaded so far';
    final sessions = s.bookings.where((b) => b.planSession).length;
    Widget figure(String label, String value, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
    return AppCard(
      key: const ValueKey('customer-profile-card'),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: CustomerAvatar(name: c.name, radius: 32),
          ),
          const SizedBox(height: 18),
          Text(
            c.phone,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(c.name, style: theme.textTheme.titleMedium),
          if (c.recordCount > 1) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Multiple customer records use this number. Each booking shows the name recorded for it.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          Divider(color: colors.outline.withValues(alpha: .4)),
          const SizedBox(height: 6),
          Text(
            scope.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.primary,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          figure(
            'Bookings',
            '${s.bookings.length}${s.next == null ? '' : '+'}',
          ),
          if (sessions > 0) figure('Plan sessions', '$sessions'),
          figure('Booked value', bookingMoney(sum((b) => b.total), s.currency)),
          figure(
            'Amount due',
            bookingMoney(sum((b) => b.balance), s.currency),
            color: sum((b) => b.balance) > 0 ? colors.primary : null,
          ),
          figure(
            'Refund due',
            bookingMoney(sum((b) => b.refundDue), s.currency),
            color: sum((b) => b.refundDue) > 0 ? colors.error : null,
          ),
        ],
      ),
    );
  }
}

/// One booking in the desktop history list.
class CustomerBookingRow extends StatelessWidget {
  const CustomerBookingRow({
    super.key,
    required this.booking,
    required this.currency,
  });
  final BookingRecord booking;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final b = booking, theme = Theme.of(context), colors = theme.colorScheme;
    final day = DateTime.tryParse(b.localStart);
    // Same-day bookings show the date once: "2030-06-04 09:00 – 10:00".
    final sameDay =
        b.localStart.length >= 16 &&
        b.localEnd.length >= 16 &&
        b.localStart.substring(0, 10) == b.localEnd.substring(0, 10);
    final localizations = MaterialLocalizations.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return InkWell(
      key: ValueKey('customer-booking-${b.id}'),
      onTap: () => context.push('/booking/${b.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    day == null
                        ? '—'
                        : localizations
                              .formatShortMonthDay(day)
                              .split(' ')
                              .first
                              .toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      color: colors.primary,
                    ),
                  ),
                  Text(
                    day == null ? '' : '${day.day}',
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${b.businessName} · ${b.spaceName}',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    sameDay
                        ? '${bookingLocal(b.localStart)} – ${bookingLocal(b.localEnd).substring(11)}'
                        : '${bookingLocal(b.localStart)} – ${bookingLocal(b.localEnd)}',
                  ),
                  const SizedBox(height: 2),
                  Text('${b.customer.name} · ${b.reference}', style: muted),
                  Text(b.timezone, style: muted),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      BookingStatusChip(status: b.status),
                      if (!b.planSession)
                        BookingStatusChip(status: b.paymentStatus),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            if (b.planSession)
              CustomerPlanSession(booking: b, alignEnd: true)
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    bookingMoney(b.total, currency),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text('Total', style: muted),
                  if (b.balance > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Amount due: ${bookingMoney(b.balance, currency)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (b.refundDue > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Refund due: ${bookingMoney(b.refundDue, currency)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
