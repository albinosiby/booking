import 'compact_booking_card.dart';
import '../models/compact_booking_model.dart';
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
  const BookingCard({
    super.key,
    required this.booking,
    required this.currency,
    this.canCollect = false,
  });
  final BookingRecord booking;
  final String currency;
  final bool canCollect;
  @override
  Widget build(BuildContext context) => CompactBookingCard(
    model: CompactBookingModel.booking(booking),
    currency: currency,
    canCollect: canCollect,
  );
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
    this.showNotes = true,
  });
  final BookingCustomer customer;
  final String notes;
  final bool enabled;
  final ValueChanged<String> onName, onPhone, onEmail, onNotes;
  final bool compact, showNotes;
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
          title: showNotes ? 'Email & notes · optional' : 'Email · optional',
          children: [
            ConfigurationField(
              label: 'Email · optional',
              value: customer.email,
              enabled: enabled,
              onChanged: onEmail,
              keyboardType: TextInputType.emailAddress,
            ),
            if (showNotes) const SizedBox(height: 12),
            if (showNotes)
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
        if (showNotes) const SizedBox(height: 16),
        if (showNotes)
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
