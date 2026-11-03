import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/booking_models.dart';

/// A receipt-style overview; transaction/activity histories intentionally stay
/// outside the booking details presentation.
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
          Text('Payment', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              Flexible(
                flex: 2,
                child: Text(
                  refund
                      ? 'Refund due'
                      : unpaid
                      ? 'Balance due'
                      : 'Paid in full',
                  style: theme.textTheme.labelLarge?.copyWith(color: accent),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                flex: 3,
                child: Text(
                  bookingMoney(refund ? b.refundDue : b.balance, currency),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (b.discountMinor > 0) ...[
            line('Subtotal', b.subtotal ?? b.total + b.discountMinor),
            line('Discount', -b.discountMinor),
            if (b.selection.discount?.reason.isNotEmpty == true)
              Text(
                b.selection.discount!.reason,
                style: theme.textTheme.bodySmall,
              ),
          ],
          line('Received', b.netPaid),
          line('Booking total', b.total, emphasized: true),
          const SizedBox(height: 8),
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
