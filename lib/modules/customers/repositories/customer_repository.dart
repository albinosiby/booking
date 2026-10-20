import '../../../utils/services/rest_api_service.dart';
import '../../bookings/models/booking_models.dart';
import '../models/customer_models.dart';

abstract interface class CustomerRepository {
  Stream<void> get changes;
  Future<CustomerPage> search({String query = '', String? after});
  Future<CustomerHistoryPage> history(String id, {String? cursor});
  void invalidate();
}

class RestCustomerRepository implements CustomerRepository {
  RestCustomerRepository(this.api);
  final RestApiService api;
  @override
  Stream<void> get changes => api.readUpdates
      .where((key) => key == '*' || key.startsWith('/bookings'))
      .map((_) {});
  String path(String path, Map<String, String?> query) => Uri(
    path: path,
    queryParameters: {
      for (final e in query.entries)
        if (e.value != null) e.key: e.value!,
    },
  ).toString();
  @override
  Future<CustomerPage> search({String query = '', String? after}) async {
    final j = await api.retainedRead(
      path('/bookings/customer-directory', {'q': query, 'after': after}),
      freshFor: const Duration(seconds: 10),
      retainFor: const Duration(minutes: 2),
    );
    return CustomerPage(
      (j['items'] as List).map(
        (c) => CustomerSummary.fromJson(Map<String, dynamic>.from(c)),
      ),
      j['next'],
    );
  }

  @override
  Future<CustomerHistoryPage> history(String id, {String? cursor}) async {
    final j = await api.retainedRead(
      path('/bookings/customer-directory/$id', {'cursor': cursor}),
      freshFor: const Duration(seconds: 10),
      retainFor: const Duration(minutes: 2),
    );
    return CustomerHistoryPage(
      customer: CustomerSummary.fromJson(
        Map<String, dynamic>.from(j['customer']),
      ),
      currency: j['currency'],
      items: (j['items'] as List).map(
        (b) => BookingRecord.fromJson(Map<String, dynamic>.from(b)),
      ),
      next: j['next'],
    );
  }

  @override
  void invalidate() => api.invalidateReads(notify: false);
}
