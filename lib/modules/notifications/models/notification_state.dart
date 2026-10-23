import 'package:equatable/equatable.dart';
import 'booking_notification.dart';

class NotificationState extends Equatable {
  const NotificationState({
    this.ready = false,
    this.registered = false,
    this.error,
    this.pending,
  });
  final bool ready, registered;
  final String? error;
  final BookingNotification? pending;
  @override
  List<Object?> get props => [ready, registered, error, pending];
}
