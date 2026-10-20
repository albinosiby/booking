import '../../workspace/repositories/refreshable_reads.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/booking_models.dart';
import 'booking_repository.dart';

class RestBookingRepository implements BookingRepository, RefreshableReads {
  RestBookingRepository(this.api);
  final RestApiService api;
  @override
  void invalidateReads() => api.invalidateReads(notify: false);
  @override
  Stream<void> get changes => api.readUpdates
      .where((key) => key == '*' || key.startsWith('/bookings'))
      .map((_) {});
  String uri(String path, Map<String, Object?> q) => Uri(
    path: path,
    queryParameters: {
      for (final e in q.entries)
        if (e.value != null) e.key: '${e.value}',
    },
  ).toString();
  @override
  Future<BookingCatalog> catalog() async => BookingCatalog.fromJson(
    Map<String, dynamic>.from(await api.retainedRead('/bookings/catalog')),
  );
  @override
  Future<Map<String, int>> dateCounts({
    required String date,
    required String dateUntil,
    String? businessId,
    String? spaceId,
    String? query,
    String? status,
  }) async {
    final j = await api.retainedRead(
      uri('/bookings/date-counts', {
        'date': date,
        'date_until': dateUntil,
        'business_id': businessId,
        'resource_id': spaceId,
        'q': query,
        'status': status,
      }),
    );
    return Map.unmodifiable({
      for (final row in j['items'] as List)
        row['date'] as String: row['count'] as int,
    });
  }

  @override
  Future<List<BookingSlot>> availability(
    BookingSelection s, {
    String? excludeId,
    bool endTimes = false,
  }) async {
    final j = await api.request(
      '/bookings/availability',
      readOnly: true,
      method: 'POST',
      data: {
        'selection': {...s.toJson()}..remove('discount'),
        'exclude_booking_id': excludeId,
        if (endTimes) 'end_times': true,
      },
    );
    return List.unmodifiable(
      (j['slots'] as List).map(
        (s) => BookingSlot.fromJson(Map<String, dynamic>.from(s)),
      ),
    );
  }

  @override
  Future<BookingQuote> quote(BookingSelection s, {String? excludeId}) async =>
      BookingQuote.fromJson(
        Map<String, dynamic>.from(
          await api.request(
            '/bookings/quote',
            readOnly: true,
            method: 'POST',
            data: {'selection': s.toJson(), 'exclude_booking_id': excludeId},
          ),
        ),
      );
  @override
  Future<List<BookingCustomer>> customers(String phone) async {
    final j = await api.retainedRead(
      uri('/bookings/customers', {
        'q': phone.replaceAll(RegExp(r'[^0-9]'), ''),
      }),
      freshFor: const Duration(seconds: 30),
      retainFor: const Duration(minutes: 2),
    );
    return List.unmodifiable(
      (j['items'] as List).map(
        (c) => BookingCustomer.fromJson(Map<String, dynamic>.from(c)),
      ),
    );
  }

  @override
  Future<String> submit(BookingCommand c) async {
    final j = await api.request(c.endpoint, method: 'POST', data: c.body);
    return j['id'];
  }

  @override
  Future<String?> commandResult(String key) async {
    final j = await api.request('/bookings/commands/$key');
    if (j['id'] != null) api.invalidateReads();
    return j['id'];
  }

  @override
  Future<BookingRecord> detail(String id) async => BookingRecord.fromJson(
    Map<String, dynamic>.from(await api.retainedRead('/bookings/$id')),
  );
  @override
  Future<BookingPageResult> list({
    String? date,
    String? dateUntil,
    bool overlap = false,
    String? spaceId,
    String? businessId,
    String? query,
    String? status,
    int cursor = 0,
  }) async {
    final j = await api.retainedRead(
      uri('/bookings', {
        'date': date,
        'date_until': dateUntil,
        'overlap': overlap ? 'true' : null,
        'resource_id': spaceId,
        'business_id': businessId,
        'q': query,
        'status': status,
        'cursor': cursor,
      }),
    );
    return BookingPageResult(
      List.unmodifiable(
        (j['items'] as List).map(
          (b) => BookingRecord.fromJson(Map<String, dynamic>.from(b)),
        ),
      ),
      j['next_cursor'],
    );
  }

  @override
  Future<CollectionPage> collections({
    String? date,
    String? businessId,
    int cursor = 0,
  }) async {
    final j = await api.retainedRead(
      uri('/bookings/collections', {
        'date': date,
        'business_id': businessId,
        'cursor': cursor,
      }),
    );
    return CollectionPage(
      List.unmodifiable(
        (j['items'] as List).map(
          (p) => CollectionEntry.fromJson(Map<String, dynamic>.from(p)),
        ),
      ),
      j['next_cursor'],
      List.unmodifiable(
        (j['totals'] as List).map(
          (p) => CollectionTotal.fromJson(Map<String, dynamic>.from(p)),
        ),
      ),
    );
  }

  @override
  Future<OutstandingPage> outstanding({
    String? date,
    String? businessId,
    int cursor = 0,
  }) async {
    final j = await api.retainedRead(
      uri('/bookings/outstanding', {
        'date': date,
        'business_id': businessId,
        'cursor': cursor,
      }),
    );
    return OutstandingPage(
      List.unmodifiable(
        (j['items'] as List).map(
          (b) => BookingOutstanding.fromJson(Map<String, dynamic>.from(b)),
        ),
      ),
      j['next_cursor'],
      j['balance_total_minor'],
      j['refund_total_minor'],
    );
  }

  @override
  Future<BookingDashboard> dashboard({String? businessId}) async =>
      BookingDashboard.fromJson(
        Map<String, dynamic>.from(
          await api.retainedRead(
            uri('/bookings/dashboard', {'business_id': businessId}),
          ),
        ),
      );
}
