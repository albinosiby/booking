import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../bookings/models/booking_models.dart';

/// Admission sessions are stored as bookings with a zero total; the plan's
/// price and payments live on the admission, so show that instead of a price.
extension CustomerPlanSessionBooking on BookingRecord {
  bool get planSession => admissionId != null;
}

String _attendance(String? value) => switch (value) {
  'present' => 'Present',
  'absent' => 'Absent',
  _ => 'Unmarked',
};

/// Price column replacement for a plan session row.
class CustomerPlanSession extends StatelessWidget {
  const CustomerPlanSession({
    super.key,
    required this.booking,
    this.alignEnd = false,
  });
  final BookingRecord booking;

  /// Right-aligns the text, for the desktop price column.
  final bool alignEnd;
  @override
  Widget build(BuildContext context) {
    final b = booking, theme = Theme.of(context), colors = theme.colorScheme;
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    return Column(
      key: ValueKey('customer-plan-session-${b.id}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Text(
          'Plan session',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          [
            if (b.optionName.isNotEmpty) b.optionName,
            _attendance(b.admissionAttendance),
          ].join(' · '),
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: muted,
        ),
        Text(
          'Price and payments are on the admission',
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
          style: muted,
        ),
        const SizedBox(height: 4),
        TextButton.icon(
          key: ValueKey('customer-open-admission-${b.id}'),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: () => context.push('/admissions/${b.admissionId}'),
          iconAlignment: IconAlignment.end,
          icon: const Icon(Icons.arrow_forward, size: 16),
          label: const Text('Open admission'),
        ),
      ],
    );
  }
}
