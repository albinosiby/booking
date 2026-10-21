import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/booking_list_model.dart';
import '../models/booking_models.dart';
import 'booking_widgets.dart';

/// Desktop summary of the loaded reservations; figures cover loaded rows only.
class BookingListStats extends StatelessWidget {
  const BookingListStats({super.key, required this.state});
  final BookingListModel state;
  @override
  Widget build(BuildContext context) {
    final s = state, currency = s.catalog.currency;
    final bookings = s.bookings;
    final confirmed = bookings.where((b) => b.status == 'confirmed').length;
    final unpaid = bookings.where((b) => b.balance > 0).toList();
    final refunds = bookings.where((b) => b.refundDue > 0).toList();
    final scope = s.next == null ? 'All results' : 'Loaded so far';
    return AppStatRow(
      key: const ValueKey('booking-list-stats'),
      children: [
        AppStatTile(
          highlight: true,
          icon: Icons.event_note_outlined,
          label: 'Bookings',
          value: '${bookings.length}${s.next == null ? '' : '+'}',
          caption: scope,
        ),
        AppStatTile(
          icon: Icons.verified_outlined,
          label: 'Confirmed',
          value: '$confirmed',
          caption: '${bookings.length - confirmed} other statuses',
        ),
        AppStatTile(
          icon: Icons.account_balance_wallet_outlined,
          label: 'Amount due',
          value: bookingMoney(
            unpaid.fold(0, (sum, b) => sum + b.balance),
            currency,
          ),
          caption: '${unpaid.length} with a balance',
        ),
        AppStatTile(
          icon: Icons.undo_rounded,
          accent: Theme.of(context).colorScheme.error,
          label: 'Refunds due',
          value: bookingMoney(
            refunds.fold(0, (sum, b) => sum + b.refundDue),
            currency,
          ),
          caption: '${refunds.length} to settle',
        ),
      ],
    );
  }
}

/// Desktop reservations grouped by local date, two cards per row.
class BookingDateGroups extends StatelessWidget {
  const BookingDateGroups({
    super.key,
    required this.bookings,
    required this.currency,
    required this.canCollect,
  });
  final List<BookingRecord> bookings;
  final String currency;
  final bool canCollect;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final groups = <String, List<BookingRecord>>{};
    for (final b in bookings) {
      final day = b.localStart.length >= 10
          ? b.localStart.substring(0, 10)
          : b.localStart;
      groups.putIfAbsent(day, () => []).add(b);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final MapEntry(key: day, value: rows) in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  switch (DateTime.tryParse(day)) {
                    final d? => localizations.formatFullDate(d),
                    null => day,
                  },
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${rows.length} ${rows.length == 1 ? 'booking' : 'bookings'}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Divider(
                    color: theme.colorScheme.outline.withValues(alpha: .4),
                  ),
                ),
              ],
            ),
          ),
          AppGrid(
            key: ValueKey('booking-day-group-$day'),
            minTileWidth: 380,
            maxColumns: 2,
            gap: 14,
            children: [
              for (final b in rows)
                BookingCard(
                  booking: b,
                  currency: currency,
                  canCollect: canCollect,
                ),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ],
    );
  }
}
