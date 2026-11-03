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
import 'package:eden_booking/modules/dashboard/repositories/home_hero_repository.dart';
import 'package:eden_booking/modules/booking_website/repositories/website_image_events.dart';
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

class RefreshBookingSource extends BookingSource {
  int loads = 0;
  bool failNext = false;

  @override
  Future<Workspace> load() async {
    loads++;
    if (failNext) {
      failNext = false;
      throw const AppException('Offline during refresh', code: 'NETWORK');
    }
    return super.load();
  }
}

class HomeHeroSource implements HomeHeroRepository {
  final responses = <Future<Uint8List?>>[];
  int calls = 0;

  @override
  Future<Uint8List?> load() {
    calls++;
    return responses.removeAt(0);
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
    'Home reloads the hero after a photo change and ignores a stale scope',
    () async {
      final source = BookingSource(), workspace = WorkspaceCubit(source);
      await workspace.load();
      final hero = HomeHeroSource();
      final events = WebsiteImageEvents();
      final first = Uint8List.fromList([1, 2, 3]);
      final updated = Uint8List.fromList([4, 5, 6]);
      final other = Uint8List.fromList([7, 8, 9]);
      final stale = Completer<Uint8List?>();
      hero.responses.addAll([
        Future.value(first),
        Future.value(updated),
        stale.future,
        Future.value(other),
      ]);
      final cubit = HomeCubit(
        SessionDashboardRepository(workspace),
        null,
        null,
        hero,
        events,
      );
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.heroImage, first);
      events.changed();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.heroImage, updated);
      events.changed();
      await Future<void>.delayed(Duration.zero);
      source.value = Workspace(
        organization: const Organization(
          id: 'other',
          name: 'Other',
          phone: '9876543210',
          currency: 'INR',
        ),
        membership: const {'role': 'owner'},
        businesses: source.value.businesses,
      );
      await workspace.load();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.heroImage, other);
      stale.complete(first);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.heroImage, other);
      expect(hero.calls, 4);
      await cubit.close();
      await workspace.close();
      await events.dispose();
    },
  );

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

  testWidgets(
    'Home shows no loaders and a calm fallback when a section fails',
    (tester) async {
      final source = BookingSource(), repo = HomeBookings();
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
      final gate = Completer<OutstandingPage>();
      repo.pending = gate;
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(home: const HomeScreen()),
          ),
        ),
      );
      await tester.pump();
      // Still loading balances: the page shows its layout, not a loader.
      expect(find.byType(AppLoadingState), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.text('Collect payments'), findsOneWidget);
      repo.pending = null;
      repo.dueFailure = const AppException('Offline', code: 'NETWORK');
      gate.completeError(repo.dueFailure!);
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsNothing);
      expect(find.byType(AppErrorWidget), findsNothing);
      expect(
        find.text('Couldn’t load payments to collect right now.'),
        findsOneWidget,
      );
      repo.dueFailure = null;
      expect(find.text('Try again'), findsOneWidget);
      await tester.ensureVisible(find.text('Try again'));
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(
        find.text('Couldn’t load payments to collect right now.'),
        findsNothing,
      );
      expect(find.text('Customer booking'), findsWidgets);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('pulling down refreshes a short Home page and can retry', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = RefreshBookingSource();
    source.value = Workspace(
      organization: source.value.organization,
      membership: const {'role': 'owner'},
      businesses: const [],
    );
    final repo = HomeBookings();
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
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    await tester.pumpWidget(
      BlocProvider.value(
        value: workspace,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(home: const HomeScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scroll = find.byType(SingleChildScrollView).first;
    expect(
      tester.widget<SingleChildScrollView>(scroll).physics,
      isA<AlwaysScrollableScrollPhysics>(),
    );
    final initialLoads = source.loads;
    final initialDueCalls = repo.cursors.length;
    source.failNext = true;
    await tester.drag(scroll, const Offset(0, 360));
    await tester.pumpAndSettle();
    expect(source.loads, initialLoads + 1);
    expect(repo.cursors.length, greaterThan(initialDueCalls));
    expect(find.text('Offline during refresh'), findsOneWidget);
    await tester.drag(scroll, const Offset(0, 360));
    await tester.pumpAndSettle();
    expect(source.loads, initialLoads + 2);
    expect(find.text('Offline during refresh'), findsNothing);
    expect(tester.takeException(), isNull);
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
              builder: (_, _) {
                final previewTheme =
                    const bool.fromEnvironment('HOME_PREVIEWS') &&
                        size.width == 390
                    ? AppTheme.build(Brightness.light)
                    : darkTheme();
                return MaterialApp.router(
                  theme: previewTheme.copyWith(
                    textTheme: previewTheme.textTheme.apply(
                      fontFamily: 'Roboto',
                    ),
                  ),
                  routerConfig: router,
                  builder: (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(
                        size.width == 320 ? 1.6 : 1,
                      ),
                    ),
                    child: RepaintBoundary(key: boundary, child: child!),
                  ),
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('All businesses'), findsNothing);
        expect(find.text('Upcoming today'), findsNothing);
        expect(find.text('Outstanding'), findsOneWidget);
        expect(find.text('Across all bookings'), findsOneWidget);
        expect(find.text('Bookings today'), findsOneWidget);
        expect(find.text('Received today'), findsOneWidget);
        if (size.width < 900) {
          final before = tester.getTopLeft(find.text('Collect payments')).dy;
          await tester.ensureVisible(find.text('Outstanding'));
          await tester.tap(find.text('Outstanding'));
          await tester.pumpAndSettle();
          final after = tester.getTopLeft(find.text('Collect payments')).dy;
          expect(after, lessThan(before));
        }
        expect(find.text('No more bookings today.'), findsOneWidget);
        // Wide: schedule left, Collect right. Phone: Collect first.
        final upcoming = tester.getTopLeft(find.text('Today’s schedule'));
        final payments = tester.getTopLeft(find.text('Collect payments'));
        if (size.width > 900) {
          expect(upcoming.dy, payments.dy);
          expect(payments.dx, greaterThan(upcoming.dx));
        } else {
          expect(upcoming.dy, greaterThan(payments.dy));
        }
        expect(tester.takeException(), isNull);
        if (const bool.fromEnvironment('HOME_PREVIEWS')) {
          tester
              .state<ScrollableState>(find.byType(Scrollable).first)
              .position
              .jumpTo(0);
          await tester.pumpAndSettle();
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
        expect(find.text('Collect payment'), findsOneWidget);
        expect(find.text('Payment history'), findsNothing);
        expect(find.text('Booking history'), findsNothing);
        await tester.tap(find.byTooltip('Close payment form'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.byKey(const ValueKey('booking-summary-collect')),
        );
        await tester.tap(find.byKey(const ValueKey('booking-summary-collect')));
        await tester.pumpAndSettle();
        expect(find.text('Collect payment').hitTestable(), findsOneWidget);
        expect(repo.submitted, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
