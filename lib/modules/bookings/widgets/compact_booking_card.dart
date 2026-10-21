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
  String get initials {
    final names = model.customer
        .trim()
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty)
        .toList();
    if (names.isEmpty) return '?';
    return [
      names.first,
      if (names.length > 1) names.last,
    ].map((v) => String.fromCharCode(v.runes.first)).join().toUpperCase();
  }

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
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: () => context.push(
          b.admissionId == null
              ? '/booking/${b.id}'
              : '/admissions/${b.admissionId}',
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.all(14.w),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: CircleAvatar(
                      radius: 24,
                      backgroundColor: colors.primary.withValues(alpha: .12),
                      foregroundColor: colors.primary,
                      child: Text(
                        initials,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.customer,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (b.phone.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(
                                Icons.phone_outlined,
                                size: 14,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 5),
                              Expanded(child: Text(b.phone, style: muted)),
                            ],
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              spaceIcon,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                [
                                  b.space,
                                  if (b.option?.isNotEmpty == true &&
                                      b.option != b.space)
                                    b.option!,
                                ].where((v) => v.isNotEmpty).join(' · '),
                                style: muted,
                              ),
                            ),
                          ],
                        ),
                        if (b.business.isNotEmpty && b.business != b.space)
                          Padding(
                            padding: const EdgeInsets.only(top: 3),
                            child: Text(b.business, style: muted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Tooltip(
                    message: '$status · ${b.reference}',
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 88),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
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
            ),
            Divider(
              height: 1,
              color: colors.outlineVariant.withValues(alpha: .6),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(date(b.start), style: theme.textTheme.bodySmall),
                  Text(
                    time,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (b.admissionId != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: CalendarAttendance(
                  admissionId: b.admissionId!,
                  visitId: b.id,
                  attendance: b.admissionAttendance ?? 'unmarked',
                  cancelled: b.status == 'cancelled',
                ),
              ),
            if (b.admissionId == null && amount != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    Text(
                      '${b.refund > 0
                          ? 'Refund due'
                          : b.balance > 0
                          ? 'Amount due'
                          : b.status == 'cancelled'
                          ? 'Booking total'
                          : 'Paid'} · ${bookingMoney(amount, currency)}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: b.balance > 0 || b.refund > 0
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                    if (canCollect && b.collectible)
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
                ),
              ),
          ],
        ),
      ),
    );
  }
}
