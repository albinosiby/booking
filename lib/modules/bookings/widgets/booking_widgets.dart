export 'booking_payment_editor.dart';
export 'booking_payment_helpers.dart';
import 'booking_payment_helpers.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../models/booking_models.dart';

String bookingLocal(String value) {
  final p = value.split('T');
  if (p.length < 2 || p[1].length < 5) return value;
  return '${p[0]} ${TimeFormat.display(p[1].substring(0, 5))}';
}

void bookingBack(BuildContext context) =>
    context.canPop() ? context.pop() : context.go('/bookings');

class NewBookingFab extends StatelessWidget {
  const NewBookingFab({super.key, required this.onPressed});
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => FloatingActionButton.extended(
    heroTag: null,
    backgroundColor: Theme.of(context).colorScheme.primary,
    foregroundColor: Theme.of(context).colorScheme.onPrimary,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    elevation: 8,
    onPressed: onPressed,
    icon: const Icon(Icons.add_rounded),
    label: const Text(
      'New booking',
      style: TextStyle(fontWeight: FontWeight.w700),
    ),
  );
}

class BookingStatusChip extends StatelessWidget {
  const BookingStatusChip({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (status) {
      'confirmed' || 'paid' => colors.primary,
      'cancelled' || 'refund_due' => colors.error,
      _ => colors.onSurfaceVariant,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Text(
        paymentLabel(status),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking, required this.currency});
  final BookingRecord booking;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), b = booking;
    final local = DateTime.tryParse(b.localStart);
    final end = DateTime.tryParse(b.localEnd);
    final locale = MaterialLocalizations.of(context);
    final day = local == null
        ? b.selection.date
        : locale.formatMediumDate(local);
    final time = b.localStart.length >= 16
        ? TimeFormat.display(b.localStart.substring(11, 16))
        : '';
    final endTime = b.localEnd.length >= 16
        ? TimeFormat.display(b.localEnd.substring(11, 16))
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AppCard(
        onTap: () => context.push('/booking/${b.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                BookingStatusChip(status: b.status),
                Text(
                  b.reference,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              b.spaceName,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${b.businessName} · ${b.optionName}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.schedule_rounded,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$day · $time–$endTime${local != null && end != null && bookingDate(local) != bookingDate(end) ? ' (ends ${locale.formatMediumDate(end)})' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.person_outline_rounded, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(b.customer.name)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 16,
              runSpacing: 10,
              children: [
                Text(
                  bookingMoney(b.total, currency),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                BookingStatusChip(status: b.paymentStatus),
                if (b.balance > 0)
                  Text(
                    'Due ${bookingMoney(b.balance, currency)}',
                    style: theme.textTheme.bodySmall,
                  ),
                if (b.refundDue > 0)
                  Text(
                    'Refund ${bookingMoney(b.refundDue, currency)}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BookingDateButton extends StatelessWidget {
  const BookingDateButton({
    super.key,
    required this.date,
    required this.onChanged,
    this.futureOnly = false,
    this.enabled = true,
    this.label = 'Date',
  });
  final String? date;
  final ValueChanged<String> onChanged;
  final bool futureOnly, enabled;
  final String label;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.calendar_today_outlined),
    label: Text('$label · ${date ?? 'All dates'}'),
    onPressed: !enabled
        ? null
        : () async {
            final today = DateTime.now(),
                first = futureOnly
                    ? DateTime(today.year, today.month, today.day)
                    : DateTime(2000),
                last = DateTime(2100, 12, 31);
            var initial = DateTime.tryParse(date ?? '') ?? today;
            if (initial.isBefore(first)) initial = first;
            if (initial.isAfter(last)) initial = last;
            final d = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: first,
              lastDate: last,
            );
            if (d != null) onChanged(bookingDate(d));
          },
  );
}

class BookingCustomerFields extends StatelessWidget {
  const BookingCustomerFields({
    super.key,
    required this.customer,
    required this.notes,
    required this.enabled,
    required this.onName,
    required this.onPhone,
    required this.onEmail,
    required this.onNotes,
    this.compact = false,
  });
  final BookingCustomer customer;
  final String notes;
  final bool enabled;
  final ValueChanged<String> onName, onPhone, onEmail, onNotes;
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ConfigurationField(
        label: compact ? 'Full name' : 'Customer name',
        prefixIcon: compact ? Icons.person_outline : null,
        value: customer.name,
        enabled: enabled,
        onChanged: onName,
      ),
      const SizedBox(height: 16),
      ConfigurationField(
        label: 'Phone number',
        prefixIcon: compact ? Icons.phone_outlined : null,
        keyboardType: TextInputType.phone,
        value: customer.phone,
        enabled: enabled,
        onChanged: onPhone,
      ),
      const SizedBox(height: 16),
      if (compact)
        ReviewMore(
          title: 'Email & notes · optional',
          children: [
            ConfigurationField(
              label: 'Email · optional',
              value: customer.email,
              enabled: enabled,
              onChanged: onEmail,
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            ConfigurationField(
              label: 'Booking notes · optional',
              value: notes,
              enabled: enabled,
              onChanged: onNotes,
            ),
          ],
        )
      else ...[
        ConfigurationField(
          label: 'Email · optional',
          value: customer.email,
          enabled: enabled,
          onChanged: onEmail,
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Booking notes · optional',
          value: notes,
          enabled: enabled,
          onChanged: onNotes,
        ),
      ],
    ],
  );
}
