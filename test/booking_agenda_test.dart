import 'dart:async';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/dashboard/screens/home_screen.dart';
import 'package:eden_booking/modules/bookings/screens/booking_list_screen.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_list_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_agenda_view.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

class DateRepository extends FakeBookingRepository {
  final requests = <String?>[];
  bool failList = false;
  final countRequests = <String?>[];
  Completer<Map<String, int>>? nextCounts;
  @override
  Future<Map<String, int>> dateCounts({
    required String date,
    required String dateUntil,
    String? businessId,
    String? spaceId,
    String? query,
    String? status,
  }) async {
    countRequests.add(status);
    final pending = nextCounts;
    nextCounts = null;
    if (pending != null) return pending.future;
    final counts = <String, int>{};
    for (
      var day = DateTime.parse(date);
      !day.isAfter(DateTime.parse(dateUntil));
      day = day.add(const Duration(days: 1))
    ) {
      counts[bookingDate(day)] = records.values
          .where(
            (r) =>
                (r['selection'] as Map)['date'] == bookingDate(day) &&
                (status == null || r['status'] == status),
          )
          .length;
    }
    return counts;
  }

  final waiting = <String, Completer<BookingPageResult>>{};
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
    if (failList) throw const AppException('Could not load bookings. Retry.');
    requests.add(date);
    if (waiting.containsKey(date)) return waiting[date]!.future;
    final rows = await Future.wait(records.keys.map(detail));
    return BookingPageResult(
      rows.where((b) => date == null || b.selection.date == date).toList(),
      null,
    );
  }

  void seed(String date, String name) {
    final id = 'booking-$date';
    records[id] = row(
      id,
      BookingSelection(
        businessId: 'business',
        resourceId: 'space',
        optionId: 'hourly',
        date: date,
        time: '09:00',
        duration: 60,
        people: 1,
      ),
      BookingCustomer(name: name, phone: '9876543210'),
    );
  }
}

void main() {
  tearDown(() => getIt.reset());
  test(
    'changing calendar date clears old results and rejects a late prior response',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final repo = DateRepository()
        ..seed('2030-06-04', 'Tuesday guest')
        ..seed('2030-06-05', 'Wednesday guest');
      final cubit = BookingListCubit(w, repo, BookingListMode.calendar);
      cubit.date('2030-06-04');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.bookings.single.customer.name, 'Tuesday guest');
      repo.waiting['2030-06-05'] = Completer<BookingPageResult>();
      cubit.date('2030-06-05');
      expect(cubit.state.bookings, isEmpty);
      expect(cubit.state.loading, isTrue);
      await Future<void>.delayed(Duration.zero);
      cubit.date('2030-06-04');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      repo.waiting['2030-06-05']!.complete(
        BookingPageResult([await repo.detail('booking-2030-06-05')], null),
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(cubit.state.date, '2030-06-04');
      expect(cubit.state.bookings.single.customer.name, 'Tuesday guest');
      await cubit.close();
      await w.close();
    },
  );

  test(
    'daily count requests follow filters and ignore an old response',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final repo = DateRepository()..seed('2030-06-04', 'Guest');
      final cubit = BookingListCubit(w, repo, BookingListMode.calendar);
      final old = Completer<Map<String, int>>();
      repo.nextCounts = old;
      cubit.countRange('2030-06-01', '2030-06-10');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      cubit.status('cancelled');
      await Future<void>.delayed(const Duration(milliseconds: 220));
      expect(repo.countRequests.last, 'cancelled');
      expect(cubit.state.dateCounts['2030-06-04'], 0);
      old.complete({'2030-06-04': 999});
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.dateCounts['2030-06-04'], 0);
      await cubit.close();
      await w.close();
    },
  );

  testWidgets(
    'calendar day selection loads only that date at narrow width with enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final repo = DateRepository()
        ..seed('2030-06-04', 'Tuesday guest')
        ..seed('2030-06-05', 'Wednesday guest');
      final cubit = BookingListCubit(w, repo, BookingListMode.calendar);
      cubit.date('2030-06-04');
      addTearDown(cubit.close);
      addTearDown(w.close);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: BlocBuilder<BookingListCubit, BookingListModel>(
              bloc: cubit,
              builder: (context, s) =>
                  BookingAgendaView(state: s, cubit: cubit, calendar: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsNothing);
      final day = find.byKey(const ValueKey('booking-day-2030-06-05'));
      await tester.ensureVisible(day);
      await tester.tap(day);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(cubit.state.dateCounts['2030-06-05'], 1);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('booking-count-2030-06-05')),
            )
            .data,
        '1',
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('booking-date-strip'))).height,
        lessThan(130),
      );
      expect(find.byType(CalendarDatePicker), findsNothing);
      expect(repo.requests.last, '2030-06-05');
      expect(find.text('Wednesday guest'), findsOneWidget);
      expect(find.text('Tuesday guest'), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      await tester.ensureVisible(find.text('Wednesday guest'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'date strip scrolls across year boundaries and recenters a distant selection',
    (tester) async {
      var selected = DateTime(2030, 12, 31);
      late StateSetter update;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return BookingCalendarPanel(
                    date: selected,
                    onChanged: (date) => setState(() => selected = date),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final nextYear = find.byKey(const ValueKey('booking-day-2031-01-01'));
      await tester.ensureVisible(nextYear);
      await tester.tap(nextYear);
      await tester.pumpAndSettle();
      expect(selected, DateTime(2031, 1, 1));
      final bounds = tester.getRect(
        find.byKey(const ValueKey('booking-date-strip')),
      );
      expect(
        bounds.contains(
          tester.getCenter(
            find.byKey(const ValueKey('booking-day-2031-01-01')),
          ),
        ),
        isTrue,
      );
      final before = tester
          .widget<ListView>(find.byKey(const ValueKey('booking-date-strip')))
          .controller!
          .offset;
      await tester.drag(
        find.byKey(const ValueKey('booking-date-strip')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      final after = tester
          .widget<ListView>(find.byKey(const ValueKey('booking-date-strip')))
          .controller!
          .offset;
      expect(after, greaterThan(before));
      expect(selected, DateTime(2031, 1, 1));
      update(() => selected = DateTime(2040, 2, 29));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('booking-day-2040-02-29')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(ValueKey('booking-day-${bookingDate(DateTime.now())}')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Calendar app-bar picker changes day while preserving the scrollable count row',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final repo = DateRepository()
        ..seed('2030-06-04', 'Tuesday guest')
        ..seed('2030-06-05', 'Wednesday guest');
      final cubit = BookingListCubit(w, repo, BookingListMode.calendar);
      cubit.date('2030-06-04');
      addTearDown(cubit.close);
      addTearDown(w.close);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: BlocBuilder<BookingListCubit, BookingListModel>(
              bloc: cubit,
              builder: (context, s) =>
                  BookingAgendaView(state: s, cubit: cubit, calendar: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Date ·'), findsNothing);
      expect(find.text('Week view'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
      for (final tip in ['Filter bookings', 'Refresh bookings']) {
        expect(
          tester
              .getRect(find.byType(AppBar))
              .contains(tester.getCenter(find.byTooltip(tip))),
          isTrue,
        );
      }
      expect(
        find.ancestor(
          of: find.byType(BookingCalendarPanel),
          matching: find.byType(AppCard),
        ),
        findsNothing,
      );
      final action = find.byTooltip('Choose calendar date');
      expect(
        tester.getRect(find.byType(AppBar)).contains(tester.getCenter(action)),
        isTrue,
      );
      expect(find.byKey(const ValueKey('booking-date-strip')), findsOneWidget);
      await tester.tap(action);
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('5'),
        ),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      expect(cubit.state.date, '2030-06-05');
      expect(find.text('Wednesday guest'), findsOneWidget);
      expect(find.text('Tuesday guest'), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('booking-count-2030-06-05')),
            )
            .data,
        '1',
      );
      expect(find.byKey(const ValueKey('booking-date-strip')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('desktop Calendar shows a month grid beside the day', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final w = WorkspaceCubit(BookingSource());
    await w.load();
    final repo = DateRepository()
      ..seed('2030-06-04', 'Tuesday guest')
      ..seed('2030-06-05', 'Wednesday guest');
    final cubit = BookingListCubit(w, repo, BookingListMode.calendar);
    cubit.date('2030-06-04');
    addTearDown(cubit.close);
    addTearDown(w.close);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1440, 1000),
        builder: (context, child) => MaterialApp(
          theme: darkTheme(),
          home: BlocBuilder<BookingListCubit, BookingListModel>(
            bloc: cubit,
            builder: (context, s) =>
                BookingAgendaView(state: s, cubit: cubit, calendar: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('booking-month-calendar')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('booking-date-strip')), findsNothing);
    expect(find.text('Tuesday guest'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('booking-month-day-2030-06-05')),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(cubit.state.date, '2030-06-05');
    expect(find.text('Wednesday guest'), findsOneWidget);
    expect(cubit.state.dateCounts['2030-06-05'], 1);
    await tester.tap(find.byTooltip('Next month'));
    await tester.pumpAndSettle();
    expect(find.text('July 2030'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'desktop month stays fixed while bookings scroll and short screens keep Today reachable',
    (tester) async {
      tester.view.physicalSize = const Size(1440, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      addTearDown(workspace.close);
      final repo = DateRepository()..seed('2030-06-05', 'Wednesday guest');
      for (var i = 0; i < 20; i++) {
        final id = 'scroll-booking-$i';
        repo.records[id] = repo.row(
          id,
          const BookingSelection(
            businessId: 'business',
            resourceId: 'space',
            optionId: 'hourly',
            date: '2030-06-04',
            time: '09:00',
            duration: 60,
            people: 1,
          ),
          BookingCustomer(name: 'Calendar guest $i', phone: '9876543210'),
        );
      }
      final cubit = BookingListCubit(workspace, repo, BookingListMode.calendar);
      addTearDown(cubit.close);
      cubit.date('2030-06-04');
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(1440, 900),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            home: BlocBuilder<BookingListCubit, BookingListModel>(
              bloc: cubit,
              builder: (context, state) =>
                  BookingAgendaView(state: state, cubit: cubit, calendar: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pumpAndSettle();
      final calendar = find.byKey(const ValueKey('booking-month-calendar'));
      final heading = find.textContaining('Bookings for ');
      final monthPosition = tester.getTopLeft(calendar);
      final headingPosition = tester.getTopLeft(heading);
      final results = find.byKey(
        const ValueKey('booking-calendar-results-2030-06-04'),
      );
      ScrollPosition position(Finder parent) => tester
          .state<ScrollableState>(
            find
                .descendant(of: parent, matching: find.byType(Scrollable))
                .first,
          )
          .position;
      await tester.drag(results, const Offset(0, -550));
      await tester.pumpAndSettle();
      expect(position(results).pixels, greaterThan(100));
      expect(tester.getTopLeft(calendar), monthPosition);
      expect(tester.getTopLeft(heading), headingPosition);
      await tester.tap(
        find.byKey(const ValueKey('booking-month-day-2030-06-05')),
      );
      await tester.pumpAndSettle();
      final nextDay = find.byKey(
        const ValueKey('booking-calendar-results-2030-06-05'),
      );
      expect(find.text('Wednesday guest'), findsOneWidget);
      expect(position(nextDay).pixels, 0);
      tester.view.physicalSize = const Size(1440, 520);
      await tester.pumpAndSettle();
      final monthPane = find.byKey(
        const PageStorageKey('booking-calendar-month-pane'),
      );
      await tester.ensureVisible(find.text('Today'));
      await tester.pumpAndSettle();
      expect(position(monthPane).pixels, greaterThan(0));
      expect(
        tester
            .getRect(monthPane)
            .contains(tester.getCenter(find.text('Today'))),
        isTrue,
      );
      expect(position(nextDay).pixels, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty Calendar centers plain text below standalone day cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final w = WorkspaceCubit(BookingSource());
    await w.load();
    final cubit = BookingListCubit(
      w,
      DateRepository(),
      BookingListMode.calendar,
    );
    cubit.date('2030-06-04');
    addTearDown(cubit.close);
    addTearDown(w.close);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          theme: darkTheme(),
          home: BlocBuilder<BookingListCubit, BookingListModel>(
            bloc: cubit,
            builder: (context, s) =>
                BookingAgendaView(state: s, cubit: cubit, calendar: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final empty = find.byKey(const ValueKey('calendar-empty-message'));
    expect(empty, findsOneWidget);
    expect(find.byType(SliverFillRemaining), findsOneWidget);
    expect(
      find.ancestor(of: empty, matching: find.byType(AppCard)),
      findsNothing,
    );
    expect(
      find.ancestor(
        of: find.byType(BookingCalendarPanel),
        matching: find.byType(AppCard),
      ),
      findsNothing,
    );
    final center = find
        .ancestor(of: empty, matching: find.byType(Center))
        .first;
    expect(
      (tester.getCenter(empty) - tester.getCenter(center)).distance,
      lessThan(1),
    );
    expect(
      tester.getCenter(empty).dy,
      greaterThan(
        tester
            .getBottomLeft(find.byKey(const ValueKey('booking-date-strip')))
            .dy,
      ),
    );
    await tester.tap(find.byTooltip('Filter bookings'));
    await tester.pumpAndSettle();
    expect(find.text('Search customer, phone or reference'), findsOneWidget);
    expect(find.text('Booking status'), findsOneWidget);
    await tester.tap(find.text('Apply filters'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('calendar-empty-message')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Bookings empty text is centered without a card and genuine failures remain retryable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final repo = DateRepository();
      final cubit = BookingListCubit(w, repo, BookingListMode.bookings);
      await cubit.load();
      addTearDown(cubit.close);
      addTearDown(w.close);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            home: BlocBuilder<BookingListCubit, BookingListModel>(
              bloc: cubit,
              builder: (context, s) =>
                  BookingAgendaView(state: s, cubit: cubit, calendar: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final empty = find.byKey(const ValueKey('bookings-empty-message'));
      expect(empty, findsOneWidget);
      expect(
        find.ancestor(of: empty, matching: find.byType(AppCard)),
        findsNothing,
      );
      expect(find.byType(AppErrorWidget), findsNothing);
      expect(find.textContaining('0 loaded'), findsNothing);
      final center = find
          .ancestor(of: empty, matching: find.byType(Center))
          .first;
      expect(
        (tester.getCenter(empty) - tester.getCenter(center)).distance,
        lessThan(1),
      );
      repo.failList = true;
      await cubit.load();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bookings-empty-message')),
        findsNothing,
      );
      expect(find.text('Could not load bookings. Retry.'), findsOneWidget);
      expect(find.byType(AppErrorWidget), findsOneWidget);
      repo.failList = false;
      await cubit.load();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('bookings-empty-message')),
        findsOneWidget,
      );
      expect(find.byType(AppErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Bookings app-bar calendar filters dates, can clear and cancel without the old date row',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final repo = DateRepository()
        ..seed('2030-06-04', 'Tuesday guest')
        ..seed('2030-06-05', 'Wednesday guest');
      final cubit = BookingListCubit(w, repo, BookingListMode.bookings);
      cubit.date('2030-06-04');
      addTearDown(cubit.close);
      addTearDown(w.close);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: BlocBuilder<BookingListCubit, BookingListModel>(
              bloc: cubit,
              builder: (context, s) =>
                  BookingAgendaView(state: s, cubit: cubit, calendar: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.textContaining('Date ·'), findsNothing);
      final icon = find.byTooltip('Choose booking date');
      expect(
        tester.getRect(find.byType(AppBar)).contains(tester.getCenter(icon)),
        isTrue,
      );
      await tester.tap(icon);
      await tester.pumpAndSettle();
      expect(find.byType(CalendarDatePicker), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(CalendarDatePicker),
          matching: find.text('5'),
        ),
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(cubit.state.date, '2030-06-05');
      expect(find.text('Wednesday guest'), findsOneWidget);
      expect(find.text('Tuesday guest'), findsNothing);
      await tester.ensureVisible(find.byType(InputChip));
      await tester.tap(find.byTooltip('Show all dates'));
      await tester.pumpAndSettle();
      expect(cubit.state.date, isNull);
      expect(find.byType(InputChip), findsNothing);
      await tester.tap(icon);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(cubit.state.date, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final home in [true, false]) {
    testWidgets(
      '${home ? 'Home' : 'Bookings'} has a floating booking action that opens the full-screen page',
      (tester) async {
        final source = BookingSource(), repo = DateRepository();
        getIt.registerSingleton<WorkspaceRepository>(source);
        registerFeatureDependencies(getIt);
        await getIt.unregister<BookingRepository>();
        getIt.registerSingleton<BookingRepository>(repo);
        final w = WorkspaceCubit(source);
        await w.load();
        addTearDown(w.close);
        final router = GoRouter(
          initialLocation: '/',
          routes: [
            GoRoute(
              path: '/',
              builder: (_, s) =>
                  home ? const HomeScreen() : const BookingListScreen(),
            ),
            GoRoute(
              path: '/booking/new',
              builder: (_, s) =>
                  const Scaffold(body: Text('Full-screen booking destination')),
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          BlocProvider.value(
            value: w,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, child) =>
                  MaterialApp.router(theme: darkTheme(), routerConfig: router),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(FloatingActionButton), findsOneWidget);
        await tester.tap(find.byType(FloatingActionButton));
        await tester.pumpAndSettle();
        expect(find.text('Full-screen booking destination'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
