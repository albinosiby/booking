import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../models/booking_models.dart';
import 'booking_widgets.dart' show bookingLocal, paymentLabel;

class BookingPaymentHistory extends StatelessWidget {
  const BookingPaymentHistory({
    super.key,
    required this.payments,
    required this.currency,
    this.collectAmount,
    this.onCollect,
  });
  final List<BookingPayment> payments;
  final String currency;
  final int? collectAmount;
  final VoidCallback? onCollect;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            Text(
              'Payment history · ${payments.length}',
              style: theme.textTheme.titleLarge,
            ),
            if (collectAmount != null && collectAmount! > 0)
              FilledButton.tonalIcon(
                key: const ValueKey('history-collect'),
                onPressed: onCollect,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(
                  'Collect ${bookingMoney(collectAmount!, currency)}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (payments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No payments recorded yet.',
              textAlign: TextAlign.center,
            ),
          )
        else
          AppCard(
            child: Column(
              children: [
                for (final item in payments.indexed) ...[
                  if (item.$1 > 0) const Divider(height: 28),
                  _payment(context, item.$2),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _payment(BuildContext context, BookingPayment p) {
    final t = Theme.of(context), refund = p.kind == 'refund';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: t.colorScheme.surfaceContainerHighest,
              child: Icon(
                refund
                    ? Icons.undo_rounded
                    : switch (p.method) {
                        'cash' => Icons.payments_outlined,
                        'upi' => Icons.qr_code_rounded,
                        'card' => Icons.credit_card_outlined,
                        _ => Icons.account_balance_outlined,
                      },
                size: 18,
                color: refund ? t.colorScheme.error : t.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${paymentLabel(p.method)}${refund ? ' · Refund' : ''}',
                          style: t.textTheme.titleSmall,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          '${refund ? '−' : ''}${bookingMoney(p.amount, currency)}',
                          textAlign: TextAlign.end,
                          style: t.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: refund
                                ? t.colorScheme.error
                                : t.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    bookingLocal(p.localReceived),
                    style: t.textTheme.bodySmall,
                  ),
                  Text(
                    '${refund ? 'Refunded' : 'Collected'} by ${p.collector}',
                    style: t.textTheme.bodySmall,
                  ),
                  if (p.reference.isNotEmpty || p.reason.isNotEmpty)
                    ReviewMore(
                      key: ValueKey('payment-history-${p.id}'),
                      title: 'Reference & notes',
                      children: [
                        if (p.reference.isNotEmpty)
                          Text('Reference: ${p.reference}'),
                        if (p.reason.isNotEmpty) Text(p.reason),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class BookingActivityHistory extends StatelessWidget {
  const BookingActivityHistory({super.key, required this.events});
  final List<BookingEvent> events;
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Booking history · ${events.length}',
          style: t.textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        if (events.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No booking activity yet.',
              textAlign: TextAlign.center,
            ),
          )
        else
          AppCard(
            child: Column(
              children: [
                for (final item in events.indexed)
                  Stack(
                    children: [
                      if (item.$1 < events.length - 1)
                        Positioned(
                          left: 11,
                          top: 26,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: t.colorScheme.outlineVariant,
                          ),
                        ),
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: item.$1 == events.length - 1 ? 0 : 24,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              _icon(item.$2.action),
                              size: 24,
                              color: item.$2.action == 'cancelled'
                                  ? t.colorScheme.error
                                  : t.colorScheme.primary,
                            ),
                            const SizedBox(width: 14),
                            Expanded(child: _event(context, item.$2)),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ],
    );
  }

  IconData _icon(String action) => switch (action) {
    'created' => Icons.add_circle_outline,
    'rescheduled' => Icons.event_repeat,
    'payment_recorded' => Icons.payments_outlined,
    'refund_recorded' => Icons.undo_rounded,
    'cancelled' => Icons.cancel_outlined,
    'completed' => Icons.task_alt,
    'customer_updated' => Icons.person_outline,
    _ => Icons.history_rounded,
  };
  Widget _event(BuildContext context, BookingEvent e) {
    final title = switch (e.action) {
      'created' => 'Booking created',
      'rescheduled' => 'Rescheduled',
      'payment_recorded' => 'Payment recorded',
      'refund_recorded' => 'Refund recorded',
      'customer_updated' => 'Customer details updated',
      'no_show' => 'Marked no-show',
      _ => paymentLabel(e.action),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          '${e.actor} · ${bookingLocal(e.date)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (e.before != null || e.after != null) ...[
          const SizedBox(height: 8),
          if (e.before != null) Text('Previous: ${bookingLocal(e.before!)}'),
          if (e.after != null) Text('→ New: ${bookingLocal(e.after!)}'),
        ],
        if (e.reason.isNotEmpty)
          ReviewMore(title: 'Reason & details', children: [Text(e.reason)]),
      ],
    );
  }
}
