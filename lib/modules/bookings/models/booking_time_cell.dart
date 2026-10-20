import 'booking_models.dart';

/// One boundary in the persistent time grid, with separate start/end validity.
class BookingTimeCell {
  const BookingTimeCell({
    required this.slot,
    required this.date,
    required this.enabled,
    this.start = false,
    this.end = false,
    this.inRange = false,
    this.label,
  });
  final BookingSlot slot;
  final String date;
  final bool enabled, start, end, inRange;
  final String? label;
}
