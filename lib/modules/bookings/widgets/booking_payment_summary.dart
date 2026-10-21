import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
  });
  final BookingRecord booking;
  final String currency;
  final VoidCallback? onCollect;

  @override
  Widget build(BuildContext context) {
    final b = booking, theme = Theme.of(context), colors = theme.colorScheme;
    final refund = b.refundDue > 0, unpaid = b.balance > 0;
    final accent = refund ? colors.error : colors.primary;
    Widget line(String label, int amount, {bool emphasized = false}) => Padding(
      padding: EdgeInsets.symmetric(vertical: 5.h),
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
          SizedBox(width: 12.w),
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
              Icon(Icons.account_balance_wallet_outlined, size: 20.r),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Payment summary',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ],
          ),
          SizedBox(height: 20.h),
          Text(
            refund
                ? 'Refund due'
                : unpaid
                ? 'Balance due'
                : 'Fully paid',
            style: theme.textTheme.labelLarge?.copyWith(color: accent),
          ),
          SizedBox(height: 4.h),
          Text(
            bookingMoney(refund ? b.refundDue : b.balance, currency),
            style: theme.textTheme.headlineMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (!refund && !unpaid)
            Padding(
              padding: EdgeInsets.only(top: 4.h),
              child: const Text('No payment pending'),
            ),
          SizedBox(height: 20.h),
          if (b.discountMinor > 0) ...[
            line('Subtotal', b.subtotal ?? b.total + b.discountMinor),
            line('Discount', -b.discountMinor),
            if (b.selection.discount?.reason.isNotEmpty == true)
              Text(
                b.selection.discount!.reason,
                style: theme.textTheme.bodySmall,
              ),
          ],
          line('Booking total', b.total, emphasized: true),
          line('Amount received', b.netPaid),
          SizedBox(height: 8.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(8.r),
            child: LinearProgressIndicator(
              value: b.total <= 0 ? 1 : (b.netPaid / b.total).clamp(0.0, 1.0),
              minHeight: 5.h,
              backgroundColor: colors.surfaceContainerHighest,
            ),
          ),
          if (onCollect != null) ...[
            SizedBox(height: 18.h),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const ValueKey('booking-summary-collect'),
                onPressed: onCollect,
                icon: const Icon(Icons.add_rounded),
                label: const Text('Collect payment'),
              ),
            ),
          ],
          if (b.status == 'cancelled')
            Padding(
              padding: EdgeInsets.only(top: 12.h),
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
