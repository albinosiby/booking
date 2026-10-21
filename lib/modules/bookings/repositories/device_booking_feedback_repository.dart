import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'booking_feedback_repository.dart';

class DeviceBookingFeedbackRepository implements BookingFeedbackRepository {
  DeviceBookingFeedbackRepository({MethodChannel? channel})
    : channel = channel ?? const MethodChannel('booking_os/feedback');
  final MethodChannel channel;
  final Set<String> _played = {};
  @override
  Future<void> created(String bookingId) async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        !_played.add(bookingId)) {
      return;
    }
    while (_played.length > 64) {
      _played.remove(_played.first);
    }
    try {
      await channel.invokeMethod<void>('playBookingSuccess');
    } on MissingPluginException {
      // Older installs need a native rebuild; booking success is unaffected.
    } on PlatformException {
      // Optional audio must never turn a saved booking into an error.
      debugPrint('Booking success sound unavailable.');
    }
  }
}
