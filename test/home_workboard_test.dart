import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/admissions/repositories/admission_repository.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/modules/dashboard/screens/home_screen.dart';
import 'package:eden_booking/modules/dashboard/widgets/home_parts.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;
import 'membership_only_test.dart' show MembershipRepositoryFake;
import 'subscription_plans_test.dart' show SubscriptionFake, term;

/// Pumps Home with [members] and returns the last route Home opened.
Future<Uri? Function()> pumpHome(
  WidgetTester tester,
  MembershipActions members, {
  List<String>? permissions,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final source = BookingSource(), repo = FakeBookingRepository();
  if (permissions != null) {
    source.value = Workspace(
      organization: source.value.organization,
      membership: {'role': 'staff', 'permissions': permissions},
      businesses: source.value.businesses,
    );
  }
  getIt.registerSingleton<WorkspaceRepository>(source);
  registerFeatureDependencies(getIt);
  await getIt.unregister<BookingRepository>();
  getIt.registerSingleton<BookingRepository>(repo);
  await getIt.unregister<HomeCubit>();
  getIt.registerFactoryParam<HomeCubit, WorkspaceCubit, void>(
    (workspace, _) => HomeCubit(SessionDashboardRepository(workspace), repo),
  );
  final workspace = WorkspaceCubit(source);
  await workspace.load();
  addTearDown(workspace.close);
  addTearDown(repo.events.close);
  Uri? destination;
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => HomeScreen(memberships: members),
      ),
      GoRoute(
        path: '/admissions/new',
        builder: (_, state) {
          destination = state.uri;
          return const Scaffold(body: Text('Renewal form'));
        },
      ),
      GoRoute(
        path: '/admissions/:id',
        builder: (_, state) {
          destination = state.uri;
          return const Scaffold(body: Text('Membership detail'));
        },
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    BlocProvider.value(
      value: workspace,
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
  return () => destination;
}

void main() {
  tearDown(() => getIt.reset());

  test('Home formats money, dates and times for people', () {
    expect(homeMoney(150000, 'INR'), '₹1,500');
    expect(homeMoney(123456789, 'INR'), '₹1,234,567.89');
    expect(homeMoney(5000, 'USD'), 'USD 50');
    expect(homeDate('2030-07-01', today: '2030-07-01'), 'today');
    expect(homeDate('2030-07-02', today: '2030-07-01'), 'tomorrow');
    expect(homeDate('2030-06-30', today: '2030-07-01'), 'yesterday');
    expect(homeDate('2030-07-21', today: '2030-07-01'), '21 Jul');
    expect(homeDate('2031-01-05', today: '2030-07-01'), '5 Jan 2031');
    expect(homeTime('17:30'), '5:30 PM');
    expect(homeTime('00:15'), '12:15 AM');
  });

  testWidgets(
    'Collect payments lists started fees and collects an entered amount',
    (tester) async {
      final r = SubscriptionFake()
        ..dueSoon = [term()]
        ..unpaid = [term(id: 'old', status: 'expired')];
      await pumpHome(tester, r);
      expect(find.text('Collect payments'), findsOneWidget);
      expect(find.text('Renewals'), findsOneWidget);
      // Collect lists the started month; Renewals the next fee.
      final row = find.byKey(const ValueKey('unpaid-old'));
      expect(
        find.descendant(of: row, matching: find.text('₹700')),
        findsOneWidget,
      );
      expect(find.text('Monthly fee due now'), findsOneWidget);
      expect(find.text('Next fee 1 Jul'), findsOneWidget);
      expect(find.text('₹1,500'), findsOneWidget);
      // A subscription with months left is collected, not renewed.
      expect(find.text('Renew & collect'), findsNothing);
      final collect = find.byKey(const ValueKey('collect-old'));
      await tester.ensureVisible(collect);
      await tester.tap(collect);
      await tester.pumpAndSettle();
      expect(find.text('Collect from Rahul'), findsOneWidget);
      expect(
        find.text('Remaining after this: INR 0.00'),
        findsOneWidget,
        reason: 'the full due amount is prefilled',
      );
      await tester.enterText(find.widgetWithText(TextField, '700.00'), '300');
      await tester.pumpAndSettle();
      expect(find.text('Remaining after this: INR 400.00'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(r.collected.single.$1, 'old');
      expect(r.collected.single.$2.single.minor, 30000);
      expect(find.text('Payment recorded.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final canRenew in [false, true]) {
    testWidgets(
      'Renewals keep the ${canRenew ? 'renew-only' : 'collection-only'} permission flow',
      (tester) async {
        await pumpHome(
          tester,
          MembershipRepositoryFake(),
          permissions: [
            'view_bookings',
            canRenew ? 'manage_subscriptions' : 'collect_payments',
          ],
        );
        expect(find.text('Renew & collect'), findsNothing);
        expect(find.text('Renew'), canRenew ? findsOneWidget : findsNothing);
        expect(
          find.text('Collect amount'),
          canRenew ? findsNothing : findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final width in [320.0, 1280.0]) {
    testWidgets('Renewals fit $width and open renewal and detail', (
      tester,
    ) async {
      final opened = await pumpHome(
        tester,
        MembershipRepositoryFake(),
        width: width,
      );
      expect(find.text('Renewals'), findsOneWidget);
      expect(find.text('Expired yesterday'), findsOneWidget);
      await tester.ensureVisible(find.text('Renew & collect'));
      await tester.tap(find.text('Renew & collect'));
      await tester.pumpAndSettle();
      expect(opened()?.queryParameters['renewal_id'], 'membership');
      expect(opened()?.queryParameters['collect'], 'true');
      GoRouter.of(tester.element(find.text('Renewal form'))).pop();
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('expired-membership'));
      await tester.ensureVisible(row);
      await tester.tap(find.descendant(of: row, matching: find.text('Anjali')));
      await tester.pumpAndSettle();
      expect(opened()?.path, '/admissions/membership');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
