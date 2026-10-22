import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/screens/booking_form_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'booking_module_test.dart'
    show BookingSource, FakeBookingRepository, customer;

Future<(BookingFormCubit, GoRouter)> openForm(
  WidgetTester tester,
  FakeBookingRepository repository, {
  bool reducedMotion = false,
  String? rescheduleId,
}) async {
  final workspace = WorkspaceCubit(BookingSource());
  await workspace.load();
  addTearDown(workspace.close);
  late BookingFormCubit cubit;
  getIt.registerFactoryParam<BookingFormCubit, WorkspaceCubit, BookingLaunch>(
    (session, launch) => cubit = BookingFormCubit(session, repository, launch),
  );
  final router = GoRouter(
    initialLocation: '/booking/new',
    routes: [
      GoRoute(
        path: '/booking/new',
        builder: (_, _) => BookingFormScreen(
          launch: BookingLaunch(date: '2030-06-04', rescheduleId: rescheduleId),
        ),
      ),
      GoRoute(
        path: '/booking/:id',
        builder: (_, state) =>
            Scaffold(body: Text('Saved ${state.pathParameters['id']}')),
      ),
      GoRoute(
        path: '/other',
        builder: (_, _) => const Scaffold(body: Text('Other screen')),
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
          theme: lightTheme(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  customer(cubit);
  await cubit.review();
  await tester.pumpAndSettle();
  return (cubit, router);
}

void main() {
  tearDown(() => getIt.reset());

  for (final size in [const Size(390, 844), const Size(1440, 900)]) {
    testWidgets('success is centered and opens details after 2.8s at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = FakeBookingRepository();
      final (cubit, router) = await openForm(tester, repository);
      await tester.tap(find.text('Confirm booking'));
      await tester.pump();
      expect(find.byType(BookingSuccess), findsOneWidget);
      expect(
        tester.getCenter(find.byType(BookingSuccess)),
        size.center(Offset.zero),
      );
      expect(
        tester.getSize(find.byType(BookingSuccess)),
        const Size.square(240),
      );
      final barrier = find.byKey(const ValueKey('booking-success-barrier'));
      expect(tester.widget<ModalBarrier>(barrier).dismissible, isFalse);
      await tester.tapAt(const Offset(10, 100));
      await router.routerDelegate.popRoute();
      await cubit.confirm();
      await tester.pump(const Duration(milliseconds: 2700));
      expect(find.byType(BookingSuccess), findsOneWidget);
      expect(repository.records.length, 1);
      expect(router.routeInformationProvider.value.uri.path, '/booking/new');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(find.byType(BookingSuccess), findsNothing);
      expect(find.text('Saved ${cubit.state.resultId}'), findsOneWidget);
      expect(
        router.routeInformationProvider.value.uri.queryParameters['created'],
        '1',
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'unverified save waits for verified retry before showing success',
    (tester) async {
      final repository = FakeBookingRepository()
        ..loseResponse = true
        ..lookupFails = true;
      final (cubit, _) = await openForm(tester, repository);
      await cubit.confirm();
      await tester.pumpAndSettle();
      expect(find.byType(BookingSuccess), findsNothing);
      expect(cubit.state.resultId, isNull);
      repository.lookupFails = false;
      await cubit.confirm();
      await tester.pump();
      expect(find.byType(BookingSuccess), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2800));
      await tester.pumpAndSettle();
      expect(find.text('Saved ${cubit.state.resultId}'), findsOneWidget);
      expect(repository.records.length, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving the screen cancels pending success navigation', (
    tester,
  ) async {
    final (cubit, router) = await openForm(tester, FakeBookingRepository());
    await cubit.confirm();
    await tester.pump();
    expect(find.byType(BookingSuccess), findsOneWidget);
    router.go('/other');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Other screen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rescheduling opens details without the new booking animation', (
    tester,
  ) async {
    final repository = FakeBookingRepository();
    const id = 'existing-booking';
    repository.records[id] = repository.row(
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
      const BookingCustomer(name: 'Customer One', phone: '9876543210'),
    );
    final (cubit, _) = await openForm(tester, repository, rescheduleId: id);
    cubit.reason('Customer request');
    cubit.time('19:00');
    await cubit.review();
    await cubit.confirm();
    await tester.pumpAndSettle();
    expect(find.byType(BookingSuccess), findsNothing);
    expect(find.text('Saved $id'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows static confirmation and still proceeds', (
    tester,
  ) async {
    final (cubit, _) = await openForm(
      tester,
      FakeBookingRepository(),
      reducedMotion: true,
    );
    await cubit.confirm();
    await tester.pump();
    expect(find.byType(BookingSuccess), findsOneWidget);
    expect(tester.hasRunningAnimations, isFalse);
    expect(find.bySemanticsLabel('Booking confirmed'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2800));
    await tester.pumpAndSettle();
    expect(find.text('Saved ${cubit.state.resultId}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
