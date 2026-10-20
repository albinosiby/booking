import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/modules/dashboard/screens/home_screen.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/screens/booking_detail_screen.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

BookingOutstanding due(String id, {int balance = 25000, int refund = 0}) =>
    BookingOutstanding(
      id: id,
      reference: 'BK-$id',
      status: 'confirmed',
      customer: 'Customer $id',
      business: 'Badminton',
      space: 'Court 1',
      localStart: '2030-06-04T09:00',
      balance: balance,
      refund: refund,
    );

class HomeBookings extends FakeBookingRepository {
  OutstandingPage page = OutstandingPage([due('booking')], null, 25000, 0);
  Completer<OutstandingPage>? pending;
  Object? dueFailure;
  final cursors = <int>[];
  @override
  Future<OutstandingPage> outstanding({
    String? date,
    String? businessId,
    int cursor = 0,
  }) async {
    expect(date, isNull);
    expect(businessId, isNull);
    cursors.add(cursor);
    if (dueFailure != null) throw dueFailure!;
    return pending == null ? page : await pending!.future;
  }
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('HOME_PREVIEWS')) return;
    final fontDir = Platform.environment['REVIEW_FONT_DIR']!;
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File('$fontDir/${font.value}').readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  tearDown(() => getIt.reset());

  test(
    'Home paginates balances, excludes refunds and refreshes after payments',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = HomeBookings()
        ..page = OutstandingPage(
          [due('one'), due('refund', balance: 0, refund: 900)],
          100,
          30000,
          900,
        );
      final cubit = HomeCubit(SessionDashboardRepository(workspace), repo);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.dueBookings.map((b) => b.id), ['one']);
      expect(cubit.state.dueTotal, 30000);
      expect(cubit.state.dashboard, isNotNull);
      repo.page = OutstandingPage(
        [due('two', balance: 5000)],
        null,
        30000,
        900,
      );
      await cubit.loadDue(more: true);
      expect(repo.cursors, [0, 100]);
      expect(cubit.state.dueBookings.map((b) => b.id), ['one', 'two']);
      expect(cubit.state.dueNext, isNull);
      repo.page = const OutstandingPage([], null, 0, 0);
      repo.events.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.dueBookings, isEmpty);
      expect(cubit.state.dueTotal, 0);
      await cubit.close();
      await workspace.close();
      await repo.events.close();
    },
  );

  test(
    'collection failures preserve schedule and scope changes discard late balances',
    () async {
      final source = BookingSource(), repo = HomeBookings();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final cubit = HomeCubit(SessionDashboardRepository(workspace), repo);
      await Future<void>.delayed(Duration.zero);
      final dashboard = cubit.state.dashboard;
      repo.dueFailure = const AppException('Offline', code: 'NETWORK');
      await cubit.loadDue();
      expect(cubit.state.dashboard, same(dashboard));
      expect(cubit.state.dueBookings, hasLength(1));
      expect(cubit.state.dueError, 'Offline');
      repo.dueFailure = null;
      final gate = Completer<OutstandingPage>();
      repo.pending = gate;
      final loading = cubit.loadDue();
      source.value = Workspace(
        organization: source.value.organization,
        membership: const {
          'role': 'staff',
          'permissions': ['view_bookings'],
        },
        businesses: source.value.businesses,
      );
      await workspace.load();
      gate.complete(OutstandingPage([due('late')], null, 25000, 0));
      await loading;
      expect(cubit.state.dueBookings, isEmpty);
      expect(cubit.state.dueTotal, isNull);
      await cubit.close();
      await workspace.close();
      await repo.events.close();
    },
  );

  test('booking-only staff do not request financial balances', () async {
    final source = BookingSource();
    source.value = Workspace(
      organization: source.value.organization,
      membership: const {
        'role': 'staff',
        'permissions': ['view_bookings'],
      },
      businesses: source.value.businesses,
    );
    final workspace = WorkspaceCubit(source);
    await workspace.load();
    final repo = HomeBookings();
    final cubit = HomeCubit(SessionDashboardRepository(workspace), repo);
    await Future<void>.delayed(Duration.zero);
    expect(repo.cursors, isEmpty);
    expect(cubit.state.dueBookings, isEmpty);
    await cubit.close();
    await workspace.close();
    await repo.events.close();
  });

  for (final size in [
    const Size(1280, 1000),
    const Size(390, 844),
    const Size(320, 800),
  ]) {
    testWidgets(
      'Home layout and Collect open payment editor at ${size.width}px',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = BookingSource(), repo = HomeBookings();
        const selection = BookingSelection(
          businessId: 'business',
          resourceId: 'space',
          optionId: 'court',
          date: '2030-06-04',
          time: '09:00',
          duration: 60,
          people: 1,
        );
        repo.records['booking'] = repo.row(
          'booking',
          selection,
          const BookingCustomer(name: 'Customer booking', phone: '9876543210'),
        );
        getIt.registerSingleton<WorkspaceRepository>(source);
        registerFeatureDependencies(getIt);
        await getIt.unregister<BookingRepository>();
        getIt.registerSingleton<BookingRepository>(repo);
        await getIt.unregister<HomeCubit>();
        getIt.registerFactoryParam<HomeCubit, WorkspaceCubit, void>(
          (workspace, _) =>
              HomeCubit(SessionDashboardRepository(workspace), repo),
        );
        final workspace = WorkspaceCubit(source);
        await workspace.load();
        addTearDown(workspace.close);
        addTearDown(repo.events.close);
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
            GoRoute(
              path: '/booking/:id',
              builder: (_, s) => BookingDetailScreen(
                id: s.pathParameters['id']!,
                collectOnOpen: s.uri.queryParameters['action'] == 'collect',
              ),
            ),
          ],
        );
        addTearDown(router.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(
          BlocProvider.value(
            value: workspace,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp.router(
                theme: darkTheme().copyWith(
                  textTheme: darkTheme().textTheme.apply(fontFamily: 'Roboto'),
                ),
                routerConfig: router,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(size.width == 320 ? 1.6 : 1),
                  ),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('All businesses'), findsNothing);
        expect(find.text('Upcoming today'), findsNothing);
        expect(find.text('Outstanding'), findsNothing);
        expect(find.text('Due amount to collect'), findsOneWidget);
        expect(
          tester.widget<AppEmptyState>(find.byType(AppEmptyState)).showCard,
          isFalse,
        );
        final upcoming = tester.getTopLeft(
          find.text('Upcoming space bookings'),
        );
        final payments = tester.getTopLeft(find.text('Payments to collect'));
        if (size.width > 900) {
          expect(upcoming.dy, payments.dy);
          expect(payments.dx, greaterThan(upcoming.dx));
        } else {
          expect(payments.dy, greaterThan(upcoming.dy));
        }
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('HOME_PREVIEWS')) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
              '/tmp/home-${size.width.toInt()}.png',
            ).writeAsBytes(data!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.ensureVisible(find.text('Collect'));
        await tester.tap(find.text('Collect'));
        await tester.pumpAndSettle();
        expect(find.text('Record split payment'), findsOneWidget);
        await tester.ensureVisible(
          find.byKey(const ValueKey('history-collect')),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('history-collect')));
        await tester.pumpAndSettle();
        expect(find.text('Record split payment').hitTestable(), findsOneWidget);
        expect(repo.submitted, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
