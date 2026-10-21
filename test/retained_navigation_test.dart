import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_list_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_list_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_agenda_view.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'booking_module_test.dart' show BookingSource;
import 'retained_page_state_test.dart' show DeferredBookings;

void main() {
  for (final size in const [Size(390, 844), Size(1280, 800)]) {
    testWidgets('tab navigation retains nested pages and entered filters at '
        '${size.width}px', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: '/home/details',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, shell) => AdaptiveScaffold(shell: shell),
            branches: [
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/home',
                    builder: (_, _) => const Text('Home content'),
                    routes: [
                      GoRoute(
                        path: 'details',
                        builder: (_, _) => const Text('Retained details'),
                      ),
                    ],
                  ),
                ],
              ),
              StatefulShellBranch(
                routes: [
                  GoRoute(
                    path: '/calendar',
                    builder: (_, _) =>
                        const TextField(key: ValueKey('retained-filter')),
                  ),
                ],
              ),
              for (final path in ['/bookings', '/accounts', '/profile'])
                StatefulShellBranch(
                  routes: [
                    GoRoute(
                      path: path,
                      builder: (_, _) => Text('$path content'),
                    ),
                  ],
                ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Retained details'), findsOneWidget);
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('retained-filter')),
        'Court 2',
      );
      await tester.tap(find.text('Home'));
      await tester.pumpAndSettle();
      expect(find.text('Retained details'), findsOneWidget);
      await tester.tap(find.text('Calendar'));
      await tester.pumpAndSettle();
      expect(find.text('Court 2'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('booking cards stay visible while a refresh request is pending', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final workspace = WorkspaceCubit(BookingSource());
    await workspace.load();
    final repository = DeferredBookings();
    const selection = BookingSelection(
      businessId: 'business',
      resourceId: 'space',
      optionId: 'court',
      date: '2030-06-04',
      time: '09:00',
      duration: 60,
      people: 1,
    );
    repository.records['booking'] = repository.row(
      'booking',
      selection,
      const BookingCustomer(name: 'Visible guest', phone: '9876543210'),
    );
    final cubit = BookingListCubit(
      workspace,
      repository,
      BookingListMode.bookings,
    );
    await cubit.load();
    addTearDown(cubit.close);
    addTearDown(workspace.close);
    addTearDown(repository.events.close);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          home: BlocBuilder<BookingListCubit, BookingListModel>(
            bloc: cubit,
            builder: (_, s) =>
                BookingAgendaView(state: s, cubit: cubit, calendar: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Visible guest'), findsOneWidget);
    repository.pendingList = Completer();
    final pending = cubit.load();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    expect(cubit.state.loading, true);
    expect(find.text('Visible guest'), findsOneWidget);
    expect(find.text('RESERVATIONS'), findsOneWidget);
    expect(find.byType(AppRefreshIndicator), findsOneWidget);
    repository.pendingList!.complete(const BookingPageResult([], null));
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Visible guest'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
