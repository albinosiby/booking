import '../models/booking_notification.dart';

abstract interface class NotificationRepository {
  Future<bool> initialize();
  Stream<void> get tokenChanges;
  Stream<BookingNotification> get foregroundMessages;
  Stream<BookingNotification> get openedMessages;
  Future<BookingNotification?> initialMessage();
  Future<bool> register(String userId);
  Future<void> unregister();
  Future<void> show(BookingNotification notification);
  Future<void> dispose();
}
