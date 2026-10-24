import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/workspace/repositories/rest_workspace_repository.dart';
import 'package:eden_booking/modules/businesses/cubit/business_management_cubit.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/modules/bookings/repositories/rest_booking_repository.dart';
import 'package:eden_booking/modules/bookings/screens/booking_form_screen.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_form_sections.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/accounts/repositories/rest_accounts_repository.dart';
import 'package:eden_booking/modules/accounts/widgets/accounts_widgets.dart';
import 'package:eden_booking/modules/team/cubit/staff_assignment_cubit.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:eden_booking/utils/services/retained_read_cache.dart';
import 'business_management_test.dart' show ManagementSource;
import 'booking_module_test.dart' show FakeBookingRepository;
import 'cached_transport_test.dart' show TestAuth;
import 'repository_cache_test.dart' show MemorySnapshotStore;

class OrderAdapter implements HttpClientAdapter {
  List<String> order = ['turf', 'pool'];
  int revision = 1;
  final writes = <Map<String, dynamic>>[];
  final reads = <String>[];
  List<Map<String, dynamic>> get businesses => [
    for (final id in order)
      {
        'id': id,
        'name': id,
        'type': id,
        'status': 'ready',
        'location_id': 'location',
        'version': 1,
        'resources': [],
        'timezone': 'Asia/Kolkata',
        'today': '2030-06-04',
      },
  ];
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object body;
    if (options.method == 'PUT') {
      expect(options.path, '/businesses/order');
      final input = Map<String, dynamic>.from(
        options.data is String ? jsonDecode(options.data) : options.data,
      );
      expect(input['revision'], revision);
      writes.add(input);
      order = List<String>.from(input['business_ids']);
      revision++;
      body = {'business_ids': order, 'revision': revision};
    } else {
      reads.add(options.path);
      body = switch (options.path) {
        '/workspace' || '/workspace/session' => {
          'organization': {
            'id': 'org',
            'name': 'Eden',
            'contact_phone': '9876543210',
            'currency': 'INR',
            'business_order_revision': revision,
          },
          'membership': {'role': 'owner'},
          'businesses': businesses,
          'locations': [],
        },
        '/bookings/catalog' => {
          'currency': 'INR',
          'can_manage': true,
          'can_collect': true,
          'can_refund': true,
          'can_finance': true,
          'businesses': businesses,
          'filter_businesses': businesses,
        },
        '/accounts/catalog' => {
          'name': 'Eden',
          'currency': 'INR',
          'timezone': 'Asia/Kolkata',
          'today': '2030-06-04',
          'can_view': true,
          'can_manage': true,
          'can_expense': true,
          'can_income': true,
          'accounts': [],
          'businesses': businesses,
          'routes': [],
        },
        _ => throw StateError('Unexpected request ${options.path}'),
      };
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        'content-type': ['application/json'],
        'cache-control': ['private, no-store'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test(
    'PUT saves order and invalidates retained booking and finance catalogs',
    () async {
      final auth = TestAuth(), adapter = OrderAdapter();
      final api = RestApiService(
        auth,
        dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
          ..httpClientAdapter = adapter,
        readCache: RetainedReadCache(
          store: MemorySnapshotStore(),
          identity: () => auth.currentUser?.id,
          now: () => DateTime.utc(2030, 6, 4),
        ),
      );
      final source = RestWorkspaceRepository(api),
          booking = RestBookingRepository(api),
          finance = RestAccountsRepository(api);
      final session = WorkspaceCubit(source);
      await session.load();
      expect(session.state.error, isNull);
      expect((await booking.catalog()).businesses.map((b) => b.id), [
        'turf',
        'pool',
      ]);
      expect((await finance.catalog()).businesses.map((b) => b.id), [
        'turf',
        'pool',
      ]);
      await booking.catalog();
      await finance.catalog();
      expect(adapter.reads.where((p) => p.endsWith('/catalog')).length, 2);
      final management = BusinessManagementCubit(
        session,
        LocalApiBusinessRepository(source),
      );
      management.moveBusiness(0, 1);
      expect(await management.saveOrder(), isTrue);
      expect(adapter.writes, [
        {
          'business_ids': ['pool', 'turf'],
          'revision': 1,
        },
      ]);
      expect((await booking.catalog()).businesses.map((b) => b.id), [
        'pool',
        'turf',
      ]);
      expect((await finance.catalog()).businesses.map((b) => b.id), [
        'pool',
        'turf',
      ]);
      expect(adapter.reads.where((p) => p.endsWith('/catalog')).length, 4);
      final reopened = WorkspaceCubit(source);
      await reopened.load();
      expect(reopened.state.data.businesses.map((b) => b.id), ['pool', 'turf']);
      await management.close();
      await session.close();
      await reopened.close();
      await api.dispose();
      await auth.events.close();
    },
  );

  testWidgets(
    'open booking form and finance selector follow saved order without losing selections',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await getIt.reset();
      final source = ManagementSource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      final bookings = FakeBookingRepository()
        ..catalogOverride = const BookingCatalog(
          canView: true,
          canManage: true,
          businesses: [
            BookingBusiness(
              id: 'turf',
              name: 'Eden Turf',
              type: 'turf',
              timezone: 'Asia/Kolkata',
              today: '2030-06-04',
              spaces: [],
            ),
            BookingBusiness(
              id: 'pool',
              name: 'Eden Swimming',
              type: 'pool',
              timezone: 'Asia/Kolkata',
              today: '2030-06-04',
              spaces: [],
            ),
          ],
        );
      await getIt.unregister<BookingRepository>();
      getIt.registerSingleton<BookingRepository>(bookings);
      late BookingFormCubit form;
      await getIt.unregister<BookingFormCubit>();
      getIt.registerFactoryParam<
        BookingFormCubit,
        WorkspaceSession,
        BookingLaunch
      >((s, launch) => form = BookingFormCubit(s, bookings, launch));
      final session = WorkspaceCubit(source);
      await session.load();
      final finance = FinanceCatalog(
        businesses: [
          FinanceBusiness('turf', 'Eden Turf', []),
          FinanceBusiness('pool', 'Eden Swimming', []),
        ],
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: Column(
                children: [
                  FinanceScopePicker(
                    catalog: finance,
                    business: 'turf',
                    space: null,
                    onChanged: (_, _) {},
                  ),
                  const Expanded(child: BookingFormScreen()),
                ],
              ),
            ),
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
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      form.chooseBusiness('turf');
      form.customerName('Keep this customer');
      form.notes('Keep these notes');
      await tester.pumpAndSettle();
      final originalForm = form;
      expect(
        tester
            .widget<BookingBusinessCards>(find.byType(BookingBusinessCards))
            .businesses
            .map((b) => b.id),
        ['turf', 'pool'],
      );
      final management = BusinessManagementCubit(
        session,
        LocalApiBusinessRepository(source),
      );
      final staff = StaffAssignmentCubit(
        session,
        LocalApiTeamRepository(source),
      )..selectBusiness('turf', true);
      final home = HomeCubit(SessionDashboardRepository(session));
      management.moveBusiness(0, 1);
      expect(await management.saveOrder(), isTrue);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<BookingBusinessCards>(find.byType(BookingBusinessCards))
            .businesses
            .map((b) => b.id),
        ['pool', 'turf'],
      );
      final picker = tester.widget<AppPicker>(
        find
            .byWidgetPredicate((w) => w is AppPicker && w.label == 'Business')
            .first,
      );
      expect(picker.items.map((i) => i.value), ['', 'pool', 'turf']);
      expect(picker.value, 'turf');
      expect(identical(form, originalForm), isTrue);
      expect(form.state.draft.businessId, 'turf');
      expect(form.state.draft.customer.name, 'Keep this customer');
      expect(form.state.draft.notes, 'Keep these notes');
      expect(staff.state.data.businesses.map((b) => b.id), ['pool', 'turf']);
      expect(staff.state.businesses, {'turf'});
      expect(home.state.data.businesses.map((b) => b.id), ['pool', 'turf']);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await tester.runAsync(() async {
        await management.close();
        await staff.close();
        await home.close();
      });
      await session.close();
      await bookings.events.close();
      await getIt.reset();
    },
  );
}
