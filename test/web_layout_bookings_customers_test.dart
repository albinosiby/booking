import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_list_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_agenda_view.dart';
import 'package:eden_booking/modules/customers/cubit/customer_cubits.dart';
import 'package:eden_booking/modules/customers/screens/customer_detail_screen.dart';
import 'package:eden_booking/modules/customers/screens/customers_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'booking_agenda_test.dart' show DateRepository;
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;
import 'customers_test.dart' show CustomersRepo;

void desktopView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  tearDown(() => getIt.reset());

  testWidgets('desktop Bookings list shows toolbar, stats and a date grid', (
    tester,
  ) async {
    desktopView(tester);
    final w = WorkspaceCubit(BookingSource());
    await w.load();
    addTearDown(w.close);
    final repo = DateRepository()
      ..seed('2030-06-04', 'Tuesday guest')
      ..seed('2030-06-05', 'Wednesday guest');
    final cubit = BookingListCubit(w, repo, BookingListMode.bookings);
    addTearDown(cubit.close);
    await cubit.load();
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(1440, 1000),
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
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('booking-list-toolbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('booking-list-stats')), findsOneWidget);
    expect(find.text('Search bookings'), findsOneWidget);
    expect(find.text('All spaces'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('booking-day-group-2030-06-04')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('booking-day-group-2030-06-05')),
      findsOneWidget,
    );
    expect(find.text('Tuesday guest'), findsOneWidget);
    expect(find.text('Wednesday guest'), findsOneWidget);
    expect(find.byTooltip('Filter bookings'), findsOneWidget);
    expect(find.byTooltip('Choose booking date'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(tester.takeException(), isNull);

    cubit.date('2030-06-04');
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);
    expect(find.text('Wednesday guest'), findsNothing);
    await tester.tap(find.byTooltip('Show all dates'));
    await tester.pumpAndSettle();
    expect(cubit.state.date, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop Customers shows a directory table and two-pane detail', (
    tester,
  ) async {
    desktopView(tester);
    final session = WorkspaceCubit(BookingSource());
    await session.load();
    addTearDown(session.close);
    final repo = CustomersRepo();
    addTearDown(repo.events.close);
    final fake = FakeBookingRepository();
    addTearDown(fake.events.close);
    const selection = BookingSelection(
      businessId: 'business',
      resourceId: 'space',
      optionId: 'hourly',
      date: '2030-06-04',
      time: '09:00',
      duration: 60,
      people: 1,
    );
    fake.records['one'] = fake.row(
      'one',
      selection,
      const BookingCustomer(name: 'Alex', phone: '9876543210'),
    );
    repo.bookings = [await fake.detail('one')];
    getIt.registerFactoryParam<CustomerListCubit, WorkspaceSession, void>(
      (s, _) => CustomerListCubit(s, repo),
    );
    getIt.registerFactoryParam<CustomerDetailCubit, WorkspaceSession, String>(
      (s, id) => CustomerDetailCubit(s, repo, id),
    );
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CustomersScreen()),
        GoRoute(
          path: '/customers/:id',
          builder: (_, s) => CustomerDetailScreen(id: s.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      BlocProvider.value(
        value: session,
        child: ScreenUtilInit(
          designSize: const Size(1440, 1000),
          builder: (_, _) => MaterialApp.router(
            theme: AppTheme.build(Brightness.light),
            routerConfig: router,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-toolbar')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-list-stats')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-table')), findsOneWidget);
    expect(find.text('PHONE NUMBER'), findsOneWidget);
    expect(find.text('9876543210'), findsOneWidget);
    expect(find.text('Refresh'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byType(TextField), '987');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.queries.last, '987');

    await tester.tap(find.byKey(const ValueKey('customer-row-customer')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-profile-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-history-list')), findsOneWidget);
    expect(find.text('Booking history'), findsOneWidget);
    expect(find.text('Badminton · Court 1'), findsOneWidget);
    expect(find.textContaining('2030-06-04'), findsOneWidget);
    expect(find.text('Unpaid'), findsOneWidget);
    expect(find.byKey(const ValueKey('web-back')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
