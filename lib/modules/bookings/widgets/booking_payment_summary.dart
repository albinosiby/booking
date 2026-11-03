import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/booking_models.dart';

/// The recorded balance and payment-method totals for a booking.
class BookingPaymentSummary extends StatelessWidget {
  const BookingPaymentSummary({
    super.key,
    required this.booking,
    required this.currency,
    this.onCollect,
    this.onRefund,
  });
  final BookingRecord booking;
  final String currency;
  final VoidCallback? onCollect;
  final VoidCallback? onRefund;

  @override
  Widget build(BuildContext context) {
    final b = booking, theme = Theme.of(context), colors = theme.colorScheme;
    final refund = b.refundDue > 0, unpaid = b.balance > 0;
    final recordedByMethod = <String, int>{};
    for (final payment in b.payments) {
      recordedByMethod.update(
        payment.method,
        (amount) =>
            amount +
            (payment.kind == 'refund' ? -payment.amount : payment.amount),
        ifAbsent: () =>
            payment.kind == 'refund' ? -payment.amount : payment.amount,
      );
    }
    final accent = refund ? colors.error : colors.primary;
    Widget line(String label, int amount, {bool emphasized = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: emphasized
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              bookingMoney(amount, currency),
              textAlign: TextAlign.end,
              style: emphasized
                  ? theme.textTheme.titleSmall
                  : theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined, color: accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Payment Summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            bookingMoney(refund ? b.refundDue : b.balance, currency),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            refund
                ? 'Refund due'
                : unpaid
                ? 'Balance due'
                : 'No payment pending',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                line('Booking total', b.total, emphasized: true),
                line('Amount received', b.netPaid),
              ],
            ),
          ),
          if (b.discountMinor > 0) ...[
            line('Subtotal', b.subtotal ?? b.total + b.discountMinor),
            line('Discount', -b.discountMinor),
            if (b.selection.discount?.reason.isNotEmpty == true)
              Text(
                b.selection.discount!.reason,
                style: theme.textTheme.bodySmall,
              ),
          ],
          for (final entry in recordedByMethod.entries)
            if (entry.value != 0)
              line(
                '${switch (entry.key) {
                  'cash' => 'Cash',
                  'upi' => 'UPI',
                  'card' => 'Card',
                  'bank_transfer' => 'Bank transfer',
                  _ => entry.key,
                }} recorded',
                entry.value,
              ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: b.total <= 0 ? 1 : (b.netPaid / b.total).clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
          if (onCollect != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('booking-summary-collect'),
                onPressed: onCollect,
                icon: const Icon(Icons.add_rounded),
                label: Text('Collect ${bookingMoney(b.balance, currency)}'),
              ),
            ),
          ],
          if (refund && onRefund != null) ...[
            const SizedBox(height: 14),
            AppButton(
              label: 'Record refund',
              secondary: true,
              onPressed: onRefund,
            ),
          ],
          if (b.status == 'cancelled')
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                'Booking cancelled. Payments are refunded separately.',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}
