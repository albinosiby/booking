import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/customers/cubit/customer_cubits.dart';
import 'package:eden_booking/modules/customers/models/customer_models.dart';
import 'package:eden_booking/modules/customers/repositories/customer_repository.dart';
import 'package:eden_booking/modules/customers/screens/customers_screen.dart';
import 'package:eden_booking/modules/customers/screens/customer_detail_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

const customer = CustomerSummary(
  id: 'customer',
  name: 'Alex',
  phone: '9876543210',
);

class CustomersRepo implements CustomerRepository {
  final events = StreamController<void>.broadcast();
  final queries = <String>[];
  final pages = <String?>[];
  final pending = <String, Completer<CustomerPage>>{};
  List<BookingRecord> bookings = [];
  @override
  Stream<void> get changes => events.stream;
  @override
  void invalidate() {}
  @override
  Future<CustomerPage> search({String query = '', String? after}) async {
    queries.add(query);
    if (pending.containsKey(query)) return pending[query]!.future;
    return CustomerPage(
      query.isEmpty || customer.phone.startsWith(query) ? [customer] : [],
      null,
    );
  }

  @override
  Future<CustomerHistoryPage> history(String id, {String? cursor}) async {
    pages.add(cursor);
    return CustomerHistoryPage(
      customer: customer,
      currency: 'INR',
      items: cursor == null ? bookings.take(1) : bookings.skip(1),
      next: cursor == null && bookings.length > 1 ? 'next' : null,
    );
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);
void main() {
  test(
    'out-of-order searches and access changes cannot restore stale customers',
    () async {
      final session = WorkspaceCubit(BookingSource());
      await session.load();
      final repo = CustomersRepo();
      final cubit = CustomerListCubit(session, repo);
      repo.pending['98'] = Completer<CustomerPage>();
      cubit.search('98');
      final old = cubit.load();
      cubit.search('123');
      await cubit.load();
      repo.pending['98']!.complete(CustomerPage([customer], null));
      await old;
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.query, '123');
      cubit.search('987');
      await cubit.load();
      expect(cubit.state.items, [customer]);
      session.clear();
      await tick();
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.error, contains('access'));
      await cubit.close();
      await session.close();
      await repo.events.close();
    },
  );
  test(
    'history appends pages and payment events refresh loaded bookings',
    () async {
      final session = WorkspaceCubit(BookingSource());
      await session.load();
      final repo = CustomersRepo();
      final fake = FakeBookingRepository();
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
      fake.records['two'] = fake.row(
        'two',
        selection,
        const BookingCustomer(name: 'Alex', phone: '9876543210'),
      );
      repo.bookings = [await fake.detail('one'), await fake.detail('two')];
      final cubit = CustomerDetailCubit(session, repo, 'customer');
      await cubit.load();
      expect(cubit.state.bookings.length, 1);
      await cubit.load(more: true);
      expect(cubit.state.bookings.length, 2);
      expect(repo.pages, [null, 'next']);
      repo.bookings = [
        BookingRecord.fromJson({
          ...fake.records['one']!,
          'payment_status': 'paid',
          'net_paid_minor': 50000,
          'balance_minor': 0,
          'refund_due_minor': 0,
        }),
      ];
      repo.events.add(null);
      await tick();
      expect(repo.pages.last, isNull);
      expect(cubit.state.bookings.single.paymentStatus, 'paid');
      session.clear();
      await tick();
      expect(cubit.state.customer, isNull);
      expect(cubit.state.bookings, isEmpty);
      await cubit.close();
      await session.close();
      await repo.events.close();
      await fake.events.close();
    },
  );
  testWidgets(
    'phone search opens history with date, time, space and paid status at narrow width',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await getIt.reset();
      final session = WorkspaceCubit(BookingSource());
      await session.load();
      final repo = CustomersRepo();
      final fake = FakeBookingRepository();
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
            builder: (_, s) =>
                CustomerDetailScreen(id: s.pathParameters['id']!),
          ),
        ],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: session,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.light),
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '987');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(repo.queries.last, '987');
      await tester.ensureVisible(find.text('9876543210'));
      await tester.tap(find.text('9876543210'));
      await tester.pumpAndSettle();
      expect(find.text('Booking history'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Unpaid'), 180);
      expect(find.text('Badminton · Court 1'), findsOneWidget);
      expect(find.textContaining('2030-06-04'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await session.close();
      await repo.events.close();
      await fake.events.close();
      await getIt.reset();
    },
  );
  for (final size in const [Size(390, 900), Size(1440, 1000)]) {
    testWidgets('admission sessions show the plan instead of a zero price at '
        '${size.width}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await getIt.reset();
      final session = WorkspaceCubit(BookingSource());
      await session.load();
      final repo = CustomersRepo();
      final fake = FakeBookingRepository();
      const selection = BookingSelection(
        businessId: 'business',
        resourceId: 'space',
        optionId: 'hourly',
        date: '2030-06-04',
        time: '09:00',
        duration: 60,
        people: 1,
      );
      fake.records['visit'] = fake.row(
        'visit',
        selection,
        const BookingCustomer(name: 'Alex', phone: '9876543210'),
      );
      repo.bookings = [
        BookingRecord.fromJson({
          ...fake.records['visit']!,
          'admission_id': 'adm-1',
          'admission_attendance': 'present',
          'total_minor': 0,
          'net_paid_minor': 0,
          'balance_minor': 0,
          'refund_due_minor': 0,
          'payment_status': 'paid',
        }),
      ];
      getIt.registerFactoryParam<CustomerDetailCubit, WorkspaceSession, String>(
        (s, id) => CustomerDetailCubit(s, repo, id),
      );
      final router = GoRouter(
        initialLocation: '/customers/customer',
        routes: [
          GoRoute(
            path: '/customers/:id',
            builder: (_, s) =>
                CustomerDetailScreen(id: s.pathParameters['id']!),
          ),
          GoRoute(
            path: '/admissions/:id',
            builder: (_, s) =>
                Scaffold(body: Text('Admission ${s.pathParameters['id']}')),
          ),
        ],
      );
      addTearDown(router.dispose);
      addTearDown(session.close);
      addTearDown(repo.events.close);
      addTearDown(fake.events.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: session,
          child: ScreenUtilInit(
            designSize: size,
            builder: (_, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.light),
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('customer-plan-session-visit')),
        findsOneWidget,
      );
      expect(find.text('Plan session'), findsOneWidget);
      expect(find.textContaining('Present'), findsOneWidget);
      expect(find.text('Total: INR 0.00'), findsNothing);
      expect(find.text('Paid'), findsNothing);
      if (size.width > 1000) {
        expect(find.text('Plan sessions'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      final open = find.byKey(const ValueKey('customer-open-admission-visit'));
      await tester.ensureVisible(open);
      await tester.tap(open);
      await tester.pumpAndSettle();
      expect(find.text('Admission adm-1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await getIt.reset();
    });
  }
}
