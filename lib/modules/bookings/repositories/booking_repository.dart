import '../models/booking_models.dart';

abstract interface class BookingRepository {
  Stream<void> get changes;
  Future<BookingCatalog> catalog();
  Future<Map<String, int>> dateCounts({
    required String date,
    required String dateUntil,
    String? businessId,
    String? spaceId,
    String? query,
    String? status,
  });
  Future<List<BookingSlot>> availability(
    BookingSelection selection, {
    String? excludeId,
    bool endTimes = false,
  });
  Future<BookingQuote> quote(BookingSelection selection, {String? excludeId});
  Future<List<BookingCustomer>> customers(String phone);
  Future<String> submit(BookingCommand command);
  Future<String?> commandResult(String key);
  Future<BookingRecord> detail(String id);
  Future<BookingPageResult> list({
    String? date,
    String? dateUntil,
    bool overlap = false,
    String? spaceId,
    String? businessId,
    String? query,
    String? status,
    int cursor = 0,
  });
  Future<CollectionPage> collections({
    String? date,
    String? businessId,
    int cursor = 0,
  });
  Future<OutstandingPage> outstanding({
    String? date,
    String? businessId,
    int cursor = 0,
  });
  Future<BookingDashboard> dashboard({String? businessId});
}
