import '../../../utils/services/rest_api_service.dart';
import '../../bookings/models/booking_models.dart';
import '../models/message_template.dart';
import 'message_repository.dart';

class RestMessageRepository implements MessageRepository {
  RestMessageRepository(this.api);
  final RestApiService api;
  @override
  Future<MessageTemplateCatalog> catalog({bool refresh = false}) async =>
      MessageTemplateCatalog.fromJson(
        Map<String, dynamic>.from(
          refresh
              ? await api.request('/message-templates')
              : await api.retainedRead(
                  '/message-templates',
                  freshFor: const Duration(minutes: 1),
                  retainFor: const Duration(days: 1),
                ),
        ),
      );
  @override
  Future<void> create({
    required String key,
    required String name,
    required String body,
    required String website,
  }) async {
    await api.request(
      '/message-templates',
      method: 'POST',
      data: {
        'command_key': key,
        'name': name,
        'body': body,
        'website_url': website,
      },
    );
  }

  @override
  Future<void> primary(String id) async {
    await api.request(
      '/message-templates/primary',
      method: 'PUT',
      data: {'id': id},
    );
  }

  @override
  Future<void> remove(String id) async {
    await api.request('/message-templates/$id', method: 'DELETE');
  }

  @override
  Future<BookingRecord> booking(String id) async => BookingRecord.fromJson(
    Map<String, dynamic>.from(await api.request('/bookings/$id')),
  );
}
