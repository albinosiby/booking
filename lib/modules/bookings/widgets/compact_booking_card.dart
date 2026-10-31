import '../../admissions/widgets/calendar_attendance.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../models/compact_booking_model.dart';
import '../models/booking_models.dart';
import 'booking_payment_helpers.dart';

/// Shared reservation tile for Home, Bookings and Calendar.
class CompactBookingCard extends StatelessWidget {
  const CompactBookingCard({
    super.key,
    required this.model,
    required this.currency,
    this.canCollect = false,
  });
  final CompactBookingModel model;
  final String currency;
  final bool canCollect;
  String date(String value) {
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }

  String clock(String value) =>
      value.length >= 16 ? TimeFormat.display(value.substring(11, 16)) : value;
  IconData get spaceIcon {
    final text = '${model.option} ${model.business}'.toLowerCase();
    if (text.contains('cricket')) return Icons.sports_cricket_outlined;
    if (text.contains('football') || text.contains('turf')) {
      return Icons.sports_soccer;
    }
    if (text.contains('pool') || text.contains('swim')) {
      return Icons.pool_outlined;
    }
    if (text.contains('hall')) return Icons.celebration_outlined;
    return Icons.sports_tennis_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final b = model, theme = Theme.of(context), colors = theme.colorScheme;
    final sameDay =
        b.end == null ||
        (b.start.length >= 10 &&
            b.end!.length >= 10 &&
            b.start.substring(0, 10) == b.end!.substring(0, 10));
    final time = b.end == null
        ? clock(b.start)
        : '${clock(b.start)} – ${sameDay ? '' : '${date(b.end!)}, '}${clock(b.end!)}';
    final status = b.status == 'confirmed'
        ? 'Confirmed'
        : paymentLabel(b.status);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final amount = b.refund > 0
        ? b.refund
        : b.balance > 0
        ? b.balance
        : b.total;
    final space = [
      if (b.business.isNotEmpty && b.business != b.space) b.business,
      b.space,
      if (b.option?.isNotEmpty == true && b.option != b.space) b.option!,
    ].where((value) => value.isNotEmpty).join(' · ');
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: () => context.push(
          b.admissionId == null
              ? '/booking/${b.id}'
              : '/admissions/${b.admissionId}',
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Tooltip(
                      message: b.customer,
                      child: Text(
                        b.customer,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '$status · ${b.reference}',
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 88),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: b.status == 'cancelled'
                            ? colors.error.withValues(alpha: .08)
                            : colors.primary.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: b.status == 'cancelled'
                              ? colors.error
                              : colors.primary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  Icon(spaceIcon, size: 15, color: colors.onSurfaceVariant),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Tooltip(
                      message: space,
                      child: Text(
                        space,
                        style: muted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (b.phone.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 112),
                      child: Text(
                        b.phone,
                        style: muted,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(date(b.start), style: muted),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              if (b.admissionId != null)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: CalendarAttendance(
                    admissionId: b.admissionId!,
                    visitId: b.id,
                    attendance: b.admissionAttendance ?? 'unmarked',
                    cancelled: b.status == 'cancelled',
                  ),
                ),
              if (b.admissionId == null && amount != null)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${b.refund > 0
                              ? 'Refund due'
                              : b.balance > 0
                              ? 'Amount due'
                              : b.status == 'cancelled'
                              ? 'Booking total'
                              : 'Paid'} · ${bookingMoney(amount, currency)}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: b.balance > 0 || b.refund > 0
                                ? colors.primary
                                : colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      if (canCollect && b.collectible) ...[
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.payments_outlined, size: 16),
                          label: const Text('Collect'),
                          onPressed: () =>
                              context.push('/booking/${b.id}?action=collect'),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
