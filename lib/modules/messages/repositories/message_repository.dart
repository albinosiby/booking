import '../../bookings/models/booking_models.dart';
import '../models/message_template.dart';

abstract interface class MessageRepository {
  Future<MessageTemplateCatalog> catalog({bool refresh = false});
  Future<void> create({
    required String key,
    required String name,
    required String body,
    required String website,
  });
  Future<void> primary(String id);
  Future<void> remove(String id);
  Future<BookingRecord> booking(String id);
}

abstract interface class MessageShareGateway {
  Future<bool> whatsapp(String message);
  Future<void> copy(String message);
}
