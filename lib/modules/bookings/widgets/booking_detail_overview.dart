import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/booking_models.dart';
import 'booking_widgets.dart' show BookingStatusChip;

class BookingReferenceBanner extends StatelessWidget {
  const BookingReferenceBanner({
    super.key,
    required this.booking,
    required this.onCopy,
  });

  final BookingRecord booking;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final label = switch (b.status) {
      'cancelled' => 'Cancelled',
      _ when b.refundDue > 0 => 'Refund due',
      _ when b.balance == 0 => 'Fully paid',
      _ when b.netPaid > 0 => 'Partially paid',
      _ => 'Payment due',
    };
    final icon = switch (b.status) {
      'cancelled' => Icons.cancel_rounded,
      _ when b.refundDue > 0 => Icons.undo_rounded,
      _ when b.balance == 0 => Icons.check_circle_rounded,
      _ => Icons.pending_rounded,
    };
    return Container(
      key: const ValueKey('booking-reference-banner'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0xFF075B49), Color(0xFF32974E)],
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SelectableText(
                          b.reference,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy booking reference',
                        onPressed: onCopy,
                        color: Colors.white,
                        icon: const Icon(Icons.copy_outlined, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 17, color: Colors.white),
                        const SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (constraints.maxWidth >= 330) ...[
              const SizedBox(width: 10),
              Icon(
                Icons.confirmation_number_outlined,
                color: Colors.white.withValues(alpha: .72),
                size: 62,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class WebsitePaymentReviewCard extends StatelessWidget {
  const WebsitePaymentReviewCard({
    super.key,
    required this.booking,
    required this.currency,
  });

  final BookingRecord booking;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final submission = booking.websitePayment;
    if (submission == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final amount = (submission['amount_minor'] as num?)?.toInt();
    final percentage = submission['percentage'];
    final transactionId = submission['transaction_id']?.toString().trim();
    final upiId = submission['upi_id']?.toString().trim();
    return Container(
      key: const ValueKey('booking-website-payment-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: .07),
        border: Border.all(color: colors.primary.withValues(alpha: .25)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.verified_user_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Website payment · Verify before collecting',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (transactionId?.isNotEmpty == true) ...[
            const SizedBox(height: 12),
            _DetailLine(
              icon: Icons.content_copy_rounded,
              child: SelectableText(
                'Transaction ID: $transactionId',
                key: const ValueKey('booking-website-transaction-id'),
              ),
            ),
          ],
          if (amount != null) ...[
            const SizedBox(height: 8),
            _DetailLine(
              icon: Icons.payments_outlined,
              child: Text(
                'Submitted: ${percentage == null ? '' : '$percentage% · '}${bookingMoney(amount, currency)}',
              ),
            ),
          ],
          if (upiId?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            _DetailLine(
              icon: Icons.account_balance_outlined,
              child: SelectableText('UPI ID: $upiId'),
            ),
          ],
          const SizedBox(height: 10),
          _DetailLine(
            icon: Icons.info_outline_rounded,
            child: Text(
              'Customer-submitted reference only. Check your bank before recording the verified collection. This submission does not change the paid balance.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class BookingInformationCard extends StatelessWidget {
  const BookingInformationCard({super.key, required this.booking});

  final BookingRecord booking;

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final colors = Theme.of(context).colorScheme;
    final name = b.businessName == b.spaceName
        ? b.spaceName
        : '${b.businessName} · ${b.spaceName}';
    final type = '${b.businessName} ${b.spaceName}'.toLowerCase();
    final icon = type.contains('pool') || type.contains('swim')
        ? Icons.pool_outlined
        : type.contains('turf') || type.contains('football')
        ? Icons.sports_soccer_outlined
        : type.contains('badminton') || type.contains('court')
        ? Icons.sports_tennis_outlined
        : Icons.event_available_outlined;
    final date = b.localStart.length >= 10
        ? b.localStart.substring(0, 10)
        : b.localStart;
    final start = b.localStart.length >= 16
        ? b.localStart.substring(11, 16)
        : b.localStart;
    final end = b.localEnd.length >= 16
        ? b.localEnd.substring(11, 16)
        : b.localEnd;
    final crossesDay =
        b.localStart.length >= 10 &&
        b.localEnd.length >= 10 &&
        b.localStart.substring(0, 10) != b.localEnd.substring(0, 10);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colors.primary, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (b.optionName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          b.optionName,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(color: colors.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(Icons.calendar_today_outlined, date),
              _MetaChip(
                Icons.schedule_outlined,
                '$start – ${crossesDay ? '${b.localEnd.substring(0, 10)} ' : ''}$end',
              ),
              _MetaChip(Icons.location_on_outlined, b.timezone),
            ],
          ),
          const SizedBox(height: 14),
          _DetailLine(
            icon: Icons.cleaning_services_outlined,
            child: Text('Cleanup time: ${b.cleanupMinutes} minutes'),
          ),
          const SizedBox(height: 6),
          const _DetailLine(
            icon: Icons.info_outline_rounded,
            child: Text('Internal only · does not block the next booking.'),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              BookingStatusChip(status: b.status),
              if (b.checkedIn)
                Chip(
                  avatar: Icon(
                    Icons.check_circle_outline_rounded,
                    color: colors.primary,
                    size: 17,
                  ),
                  label: Text(
                    b.automaticallyCheckedIn ? 'Auto checked in' : 'Checked in',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _DetailLine(
                  icon: Icons.person_outline_rounded,
                  child: Text(b.customer.name),
                ),
                _DetailLine(
                  icon: Icons.phone_outlined,
                  child: SelectableText(b.customer.phone),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.icon, required this.child});
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 9),
      Flexible(child: child),
    ],
  );
}
