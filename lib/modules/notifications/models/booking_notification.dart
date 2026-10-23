import 'package:equatable/equatable.dart';

class BookingNotification extends Equatable {
  const BookingNotification({
    required this.eventId,
    required this.bookingId,
    required this.userId,
    required this.kind,
    this.title,
    this.body,
  });
  final String eventId, bookingId, userId, kind;
  final String? title, body;
  static final _uuid = RegExp(
    r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$',
  );
  static BookingNotification? fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    final event = data['event_id'],
        booking = data['booking_id'],
        user = data['recipient_user_id'],
        kind = data['event_type'];
    if (event is! String ||
        !_uuid.hasMatch(event) ||
        booking is! String ||
        !_uuid.hasMatch(booking) ||
        user is! String ||
        user.isEmpty ||
        !const ['created', 'cancelled', 'rescheduled'].contains(kind)) {
      return null;
    }
    return BookingNotification(
      eventId: event,
      bookingId: booking,
      userId: user,
      kind: kind as String,
      title: title,
      body: body,
    );
  }

  Map<String, String> toData() => {
    'event_id': eventId,
    'booking_id': bookingId,
    'recipient_user_id': userId,
    'event_type': kind,
  };
  @override
  List<Object?> get props => [eventId, bookingId, userId, kind, title, body];
}
