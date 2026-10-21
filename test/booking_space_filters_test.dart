import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_list_cubit.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

class FilterRepository extends FakeBookingRepository {
  final filters = <(String?, String?)>[];
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
    filters.add((businessId, spaceId));
    return const BookingPageResult([], null);
  }
}

void main() {
  test(
    'space chips distinguish repeated court names and use catalog permissions',
    () {
      BookingBusiness business(String id, String name) => BookingBusiness(
        id: id,
        name: name,
        type: 'badminton',
        timezone: 'Asia/Kolkata',
        today: '2030-06-04',
        spaces: [
          BookingSpace(
            id: '$id-court',
            name: 'Court 1',
            capacity: 1,
            options: const [],
          ),
        ],
      );
      final model = BookingListModel(
        catalog: BookingCatalog(
          businesses: [business('one', 'Badminton'), business('two', 'Tennis')],
        ),
      );
      expect(model.spaceFilters.map((s) => s.label), [
        'Badminton · Court 1',
        'Tennis · Court 1',
      ]);
      expect(() => model.spaceFilters.clear(), throwsUnsupportedError);
    },
  );
  test(
    'space selection supplies business and space, All spaces clears both',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = FilterRepository();
      final list = BookingListCubit(w, r, BookingListMode.bookings);
      list.filters(businessId: 'business', spaceId: 'space');
      await Future<void>.delayed(Duration.zero);
      expect(r.filters.last, ('business', 'space'));
      list.filters();
      await Future<void>.delayed(Duration.zero);
      expect(r.filters.last, (null, null));
      await list.close();
      await w.close();
    },
  );
}
