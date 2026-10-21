import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_list_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/accounts/cubit/accounts_cubits.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;
import 'accounts_module_test.dart' show FakeAccountsRepository;

class DeferredBookings extends FakeBookingRepository {
  Completer<BookingPageResult>? pendingList;
  Completer<BookingDashboard>? pendingDashboard;
  Object? failure;
  int dashboardLoads = 0;
  @override
  Future<BookingDashboard> dashboard({String? businessId}) {
    dashboardLoads++;
    return pendingDashboard?.future ?? super.dashboard(businessId: businessId);
  }

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
  }) {
    if (failure != null) return Future.error(failure!);
    return pendingList?.future ??
        super.list(
          date: date,
          dateUntil: dateUntil,
          overlap: overlap,
          spaceId: spaceId,
          businessId: businessId,
          query: query,
          status: status,
          cursor: cursor,
        );
  }
}

void main() {
  late WorkspaceCubit workspace;
  late DeferredBookings bookings;
  setUp(() async {
    workspace = WorkspaceCubit(BookingSource());
    await workspace.load();
    bookings = DeferredBookings();
    const selection = BookingSelection(
      businessId: 'business',
      resourceId: 'space',
      optionId: 'court',
      date: '2030-06-04',
      time: '09:00',
      duration: 60,
      people: 1,
    );
    bookings.records['booking'] = bookings.row(
      'booking',
      selection,
      const BookingCustomer(name: 'Customer One', phone: '9876543210'),
    );
  });
  tearDown(() async {
    await bookings.events.close();
    await workspace.close();
  });

  test(
    'bookings retain results while refreshing and after a network error',
    () async {
      final cubit = BookingListCubit(
        workspace,
        bookings,
        BookingListMode.bookings,
      );
      await cubit.load();
      final previous = cubit.state.bookings;
      expect(previous, hasLength(1));
      bookings.pendingList = Completer();
      final loading = cubit.load();
      expect(cubit.state.loading, true);
      expect(cubit.state.bookings, previous);
      await Future<void>.delayed(Duration.zero);
      bookings.pendingList!.completeError(
        const AppException('Offline', code: 'NETWORK'),
      );
      await loading;
      expect(cubit.state.bookings, previous);
      expect(cubit.state.error, 'Offline');
      await cubit.close();
    },
  );

  test(
    'changing the selected day never labels the old day’s results as new',
    () async {
      final cubit = BookingListCubit(
        workspace,
        bookings,
        BookingListMode.calendar,
      );
      await cubit.load();
      bookings.pendingList = Completer();
      cubit.date('2030-06-05');
      expect(cubit.state.date, '2030-06-05');
      expect(cubit.state.bookings, isEmpty);
      await Future<void>.delayed(Duration.zero);
      bookings.pendingList!.complete(const BookingPageResult([], null));
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
    },
  );

  test(
    'a loaded empty result stays identified as loaded during refresh',
    () async {
      bookings.records.clear();
      final cubit = BookingListCubit(
        workspace,
        bookings,
        BookingListMode.bookings,
      );
      await cubit.load();
      expect(cubit.state.hasLoaded, true);
      bookings.pendingList = Completer();
      final pending = cubit.load();
      expect(cubit.state.hasLoaded, true);
      expect(cubit.state.loading, true);
      await Future<void>.delayed(Duration.zero);
      bookings.pendingList!.complete(const BookingPageResult([], null));
      await pending;
      await cubit.close();
    },
  );
  test('permission failures remove retained bookings', () async {
    final cubit = BookingListCubit(
      workspace,
      bookings,
      BookingListMode.bookings,
    );
    await cubit.load();
    bookings.failure = const AppException('Removed', code: 'FORBIDDEN');
    await cubit.load();
    expect(cubit.state.bookings, isEmpty);
    expect(cubit.state.error, 'Removed');
    await cubit.close();
  });

  test(
    'Accounts keeps its totals during refresh and after connection failure',
    () async {
      final repository = FakeAccountsRepository();
      final cubit = AccountsOverviewCubit(workspace, repository, bookings);
      await cubit.load();
      final previous = cubit.state.overview;
      repository.delayed = Completer();
      final gate = repository.delayed!;
      final pending = cubit.load();
      expect(cubit.state.loading, true);
      expect(cubit.state.overview, same(previous));
      await Future<void>.delayed(Duration.zero);
      gate.completeError(const AppException('Offline', code: 'NETWORK'));
      await pending;
      expect(cubit.state.overview, same(previous));
      expect(cubit.state.error, 'Offline');
      await cubit.close();
      await repository.events.close();
    },
  );

  test(
    'Accounts keeps the summary visible while a new date range loads',
    () async {
      final repository = FakeAccountsRepository();
      final cubit = AccountsOverviewCubit(workspace, repository, bookings);
      await cubit.load();
      repository.delayed = Completer();
      final gate = repository.delayed!;
      final pending = cubit.load(
        filter: const FinanceFilter(from: '2026-09-01', until: '2026-09-30'),
      );
      // Shown faded and not tappable until the new range arrives.
      expect(cubit.state.overview, isNotNull);
      expect(cubit.state.loading, isTrue);
      await Future<void>.delayed(Duration.zero);
      gate.complete(repository.overviewValue);
      await pending;
      await cubit.close();
      await repository.events.close();
    },
  );

  test(
    'unchanged workspace refresh does not blank Home or reload its dashboard',
    () async {
      final cubit = HomeCubit(SessionDashboardRepository(workspace), bookings);
      await Future<void>.delayed(Duration.zero);
      final previous = cubit.state.dashboard;
      final calls = bookings.dashboardLoads;
      expect(previous, isNotNull);
      await workspace.load();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.dashboard, same(previous));
      expect(bookings.dashboardLoads, calls);
      await cubit.close();
    },
  );
}
