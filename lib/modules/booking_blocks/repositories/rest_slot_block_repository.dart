import '../../../utils/services/rest_api_service.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/repositories/booking_repository.dart';
import '../models/slot_block_models.dart';
import 'slot_block_repository.dart';

class RestSlotBlockRepository implements SlotBlockRepository {
  RestSlotBlockRepository(this.api, this.bookings);
  final RestApiService api;
  final BookingRepository bookings;
  @override
  Future<BookingCatalog> catalog() => bookings.catalog();
  @override
  Stream<void> get changes => api.readUpdates
      .where((p) => p == '*' || p.startsWith('/booking-blocks'))
      .map((_) {});
  @override
  Future<SlotBlockPage> list(
    String businessId,
    String date, {
    int cursor = 0,
  }) async {
    final j = await api.retainedRead(
      Uri(
        path: '/booking-blocks',
        queryParameters: {
          'business_id': businessId,
          'date': date,
          'cursor': '$cursor',
        },
      ).toString(),
    );
    return SlotBlockPage([
      for (final row in j['items'] as List)
        SlotBlock(
          id: row['id'],
          start: row['local_start'],
          end: row['local_end'],
          timezone: row['timezone'],
          creator: row['created_by'],
          createdAt: row['created_at'],
          allDay: row['all_day'],
          canUnblock: row['can_unblock'],
          spaces: List<String>.from(row['spaces']),
          sharedGround: row['shared_ground'] ?? false,
        ),
    ], j['next_cursor']);
  }

  @override
  Future<({List<BlockSlot> slots, int step})> slots(
    String businessId,
    String date,
    Iterable<String> spaces,
  ) async {
    final j = await api.request(
      Uri(
        path: '/booking-blocks/slots',
        queryParameters: {
          'business_id': businessId,
          'date': date,
          'resource_ids': ([...spaces]..sort()).join(','),
        },
      ).toString(),
    );
    return (
      slots: List<BlockSlot>.unmodifiable([
        for (final row in j['slots'] as List)
          BlockSlot(row['time'], row['status']),
      ]),
      step: j['step_minutes'] as int,
    );
  }

  @override
  Future<String> create(BlockRequest r) async {
    final j = await api.request(
      '/booking-blocks',
      method: 'POST',
      data: {
        'command_key': r.key,
        'business_id': r.businessId,
        'resource_ids': r.spaces,
        'date': r.date,
        'all_day': r.allDay,
        if (!r.allDay) ...{
          'start_time': r.start,
          'end_time': r.end,
          'end_date': r.endDate,
        },
      },
    );
    return j['id'];
  }

  @override
  Future<void> unblock(String id) async {
    await api.request(
      '/booking-blocks/$id/unblock',
      method: 'POST',
      data: const <String, Object?>{},
    );
  }
}
