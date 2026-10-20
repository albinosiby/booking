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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/core/settings/application_setting.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/auth/repositories/auth_repository_interface.dart';
import 'package:eden_booking/modules/businesses/cubit/business_management_cubit.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/businesses/screens/business_management_screen.dart';
import 'package:eden_booking/modules/businesses/screens/business_detail_screen.dart';
import 'package:eden_booking/modules/profile/screens/profile_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/business_order.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

class ManagementSource extends Fake implements WorkspaceRepository {
  bool owner = true, fail = false;
  int revision = 2, saves = 0;
  List<Business> businesses = const [
    Business(
      id: 'turf',
      name: 'Eden Turf',
      type: BusinessType.turf,
      status: 'ready',
      locationId: 'location',
      version: 1,
      resources: [Resource(id: 'ground', name: 'Ground 1', capacity: 10)],
    ),
    Business(
      id: 'pool',
      name: 'Eden Swimming',
      type: BusinessType.pool,
      status: 'draft',
      locationId: 'location',
      version: 1,
      resources: [],
    ),
  ];
  @override
  Future<Workspace> load() async => Workspace(
    organization: Organization(
      id: 'org',
      name: 'Eden',
      phone: '9876543210',
      currency: 'INR',
      businessOrderRevision: revision,
    ),
    membership: {
      'role': owner ? 'owner' : 'staff',
      'display_name': 'Alex',
      'email': 'owner@example.com',
      'permissions': ['view_bookings'],
    },
    businesses: List.unmodifiable(businesses),
    locations: const [
      {
        'id': 'location',
        'name': 'Main property',
        'address_line_1': 'Road 1',
        'city': 'Kochi',
        'country_code': 'IN',
        'postal_code': '682001',
        'timezone': 'Asia/Kolkata',
      },
    ],
  );
  @override
  Future<void> reorderBusinesses(List<String> ids, int expectedRevision) async {
    saves++;
    if (fail) throw const AppException('Connection lost.', code: 'NETWORK');
    if (expectedRevision != revision) {
      throw const AppException('The order changed.', code: 'CONFLICT');
    }
    final byId = {for (final b in businesses) b.id: b};
    businesses = [for (final id in ids) byId[id]!];
    revision++;
  }

  @override
  Future<void> renameBusiness(String id, String name) async {
    businesses = businesses
        .map(
          (b) => b.id != id
              ? b
              : Business(
                  id: b.id,
                  name: name,
                  type: b.type,
                  status: b.status,
                  locationId: b.locationId,
                  version: b.version,
                  resources: b.resources,
                ),
        )
        .toList();
  }
}

class DelayedOrderSource extends ManagementSource {
  final release = Completer<void>();
  int attempts = 0;
  @override
  Future<void> reorderBusinesses(List<String> ids, int expectedRevision) async {
    attempts++;
    await release.future;
    await super.reorderBusinesses(ids, expectedRevision);
  }
}

class ProfileAuth extends Fake implements AuthRepository {
  @override
  Stream<AppUser?> get changes => Stream.value(
    const AppUser(
      id: 'user',
      email: 'owner@example.com',
      name: 'Alex',
      verified: true,
    ),
  );
}

ThemeData managementPreviewTheme() {
  final theme = darkTheme();
  if (!const bool.fromEnvironment('BUSINESS_PREVIEWS')) return theme;
  const textStyle = WidgetStatePropertyAll(
    TextStyle(fontFamily: 'Roboto', fontSize: 15, fontWeight: FontWeight.w700),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(textStyle: textStyle),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(textStyle: textStyle),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: textStyle,
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('BUSINESS_PREVIEWS')) return;
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File(
        '/tmp/home-preview-fonts/${font.value}',
      ).readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  tearDown(() => getIt.reset());
  test(
    'reorder is a draft until saved, supports cancel and survives refresh',
    () async {
      final source = ManagementSource();
      final session = WorkspaceCubit(source);
      await session.load();
      final cubit = BusinessManagementCubit(
        session,
        LocalApiBusinessRepository(source),
      );
      cubit.startReorder();
      cubit.reorder(0, 1);
      cubit.startReorder();
      expect(cubit.state.businesses.first.id, 'pool');
      expect(session.state.data.businesses.first.id, 'turf');
      cubit.cancelReorder();
      expect(cubit.state.businesses.first.id, 'turf');
      cubit.startReorder();
      cubit.reorder(0, 1);
      expect(await cubit.saveOrder(), isTrue);
      await session.load();
      expect(session.state.data.businesses.map((b) => b.id), ['pool', 'turf']);
      expect(source.revision, 3);
      expect(cubit.state.reordering, isFalse);
      await cubit.close();
      await session.close();
    },
  );
  test(
    'stale order cannot overwrite another device and access changes discard drafts',
    () async {
      final source = ManagementSource();
      final session = WorkspaceCubit(source);
      await session.load();
      final cubit = BusinessManagementCubit(
        session,
        LocalApiBusinessRepository(source),
      );
      cubit.startReorder();
      cubit.reorder(0, 1);
      source.revision++;
      await session.load();
      await Future<void>.delayed(Duration.zero);
      expect(await cubit.saveOrder(), isFalse);
      expect(source.saves, 0);
      expect(cubit.state.message, contains('changed'));
      cubit.startReorder();
      source.owner = false;
      await session.load();
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.reordering, isFalse);
      cubit.startReorder();
      expect(cubit.state.reordering, isFalse);
      expect(await cubit.rename('turf', 'Changed'), isFalse);
      await cubit.close();
      await session.close();
    },
  );
  test(
    'failed order save retains the server order and reports the failure',
    () async {
      final source = ManagementSource()..fail = true;
      final session = WorkspaceCubit(source);
      await session.load();
      final cubit = BusinessManagementCubit(
        session,
        LocalApiBusinessRepository(source),
      );
      cubit.startReorder();
      cubit.reorder(0, 1);
      expect(await cubit.saveOrder(), isFalse);
      expect(cubit.state.businesses.first.id, 'turf');
      expect(cubit.state.error, isNotNull);
      await cubit.close();
      await session.close();
    },
  );
  test(
    'business grouping preserves time order and the relative order of staff subsets',
    () {
      final records = [
        ('pool', '09:00'),
        ('turf', '08:00'),
        ('pool', '10:00'),
        ('hall', '11:00'),
      ];
      expect(orderByBusiness(records, (b) => b.$1, ['turf', 'pool']), [
        records[1],
        records[0],
        records[2],
        records[3],
      ]);
      expect(
        orderByBusiness(['pool', 'hall'], (id) => id, ['turf', 'pool', 'hall']),
        ['pool', 'hall'],
      );
    },
  );
  test(
    'accessibility and repeated moves share one draft and persist once',
    () async {
      final source = ManagementSource();
      final session = WorkspaceCubit(source);
      await session.load();
      final cubit = BusinessManagementCubit(
        session,
        LocalApiBusinessRepository(source),
      );
      cubit.moveBusiness(0, 0);
      expect(cubit.state.reordering, isFalse);
      cubit.moveBusiness(1, 0);
      expect(cubit.state.businesses.first.id, 'pool');
      cubit.moveBusiness(0, 1);
      expect(cubit.state.businesses.first.id, 'turf');
      cubit.moveBusiness(0, 1);
      expect(cubit.state.businesses.first.id, 'pool');
      expect(source.saves, 0);
      cubit.cancelReorder();
      expect(cubit.state.businesses.first.id, 'turf');
      cubit.moveBusiness(0, 1);
      expect(await cubit.saveOrder(), isTrue);
      final reopened = WorkspaceCubit(source);
      await reopened.load();
      expect(reopened.state.data.businesses.first.id, 'pool');
      expect(source.saves, 1);
      await cubit.close();
      await reopened.close();
      await session.close();
    },
  );
  test(
    'a duplicate save or cancel cannot discard an in-flight order',
    () async {
      final source = DelayedOrderSource();
      final session = WorkspaceCubit(source);
      await session.load();
      final cubit = BusinessManagementCubit(
        session,
        LocalApiBusinessRepository(source),
      );
      cubit.moveBusiness(0, 1);
      final pending = cubit.saveOrder();
      expect(await cubit.saveOrder(), isFalse);
      cubit.cancelReorder();
      cubit.moveBusiness(0, 1);
      expect(cubit.state.reordering, isTrue);
      expect(cubit.state.businesses.first.id, 'pool');
      expect(source.attempts, 1);
      source.release.complete();
      expect(await pending, isTrue);
      expect(source.saves, 1);
      expect(session.state.data.businesses.first.id, 'pool');
      expect(cubit.state.reordering, isFalse);
      await cubit.close();
      await session.close();
    },
  );
  testWidgets(
    'drag scrolls beyond the viewport and saves the complete business order',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source = ManagementSource()
        ..businesses = List.generate(
          8,
          (i) => Business(
            id: 'business-$i',
            name: 'Business $i',
            type: BusinessType.turf,
            status: 'ready',
            locationId: 'location',
            version: 1,
            resources: const [],
          ),
        );
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const BusinessManagementScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp.router(
              theme: managementPreviewTheme(),
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final start = tester.getCenter(find.text('Business 0'));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      for (var step = 1; step <= 12; step++) {
        await gesture.moveTo(
          Offset(start.dx, start.dy + (700 - start.dy) * step / 12),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }
      for (var frame = 0; frame < 140; frame++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(scroll.position.pixels, greaterThan(0));
      expect(find.text('Business 7'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(source.saves, 0);
      await tester.tap(find.text('Save order'));
      await tester.pumpAndSettle();
      expect(source.businesses.last.id, 'business-0');
      expect(source.saves, 1);
      expect(source.businesses.map((b) => b.id).toSet().length, 8);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await workspace.close();
    },
  );
  for (final width in [390.0, 320.0]) {
    testWidgets(
      'business management supports reorder, details and rename at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = ManagementSource();
        getIt.registerSingleton<WorkspaceRepository>(source);
        registerFeatureDependencies(getIt);
        final workspace = WorkspaceCubit(source);
        await workspace.load();
        addTearDown(workspace.close);
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) => const BusinessManagementScreen(),
            ),
            GoRoute(
              path: '/businesses/:id',
              builder: (_, s) =>
                  BusinessDetailScreen(id: s.pathParameters['id']!),
            ),
            GoRoute(
              path: '/businesses/:id/settings',
              builder: (_, _) =>
                  const Scaffold(body: Text('Configuration destination')),
            ),
            GoRoute(
              path: '/businesses/add',
              builder: (_, _) => const Scaffold(body: Text('Add destination')),
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
                theme: managementPreviewTheme(),
                routerConfig: router,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                  ),
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (const bool.fromEnvironment('BUSINESS_PREVIEWS')) {
          await tester.runAsync(() async {
            final render =
                boundary.currentContext!.findRenderObject()
                    as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/business-management-${width.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        expect(find.text('Reorder'), findsNothing);
        final first = find.text('Eden Turf').first;
        await tester.ensureVisible(first);
        await tester.pumpAndSettle();
        // Place the row fully inside the viewport before starting a drag;
        // a fling can scroll past it when large text makes the heading taller.
        final scroll = tester
            .state<ScrollableState>(
              find
                  .descendant(
                    of: find.byType(CustomScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .first,
            )
            .position;
        scroll.jumpTo(
          (scroll.pixels + tester.getCenter(first).dy - 250).clamp(
            scroll.minScrollExtent,
            scroll.maxScrollExtent,
          ),
        );
        await tester.pumpAndSettle();
        expect(first.hitTestable(), findsOneWidget);
        final start = tester.getCenter(first);
        final target = Offset(start.dx, 790);
        final gesture = await tester.startGesture(start);
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Save order'), findsOneWidget);
        for (var step = 1; step <= 12; step++) {
          await gesture.moveTo(
            Offset(start.dx, start.dy + (target.dy - 8 - start.dy) * step / 12),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }
        for (var frame = 0; frame < 100; frame++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await gesture.up();
        await tester.pumpAndSettle();
        expect(source.saves, 0);
        await tester.tap(find.text('Save order'));
        await tester.pumpAndSettle();
        expect(source.businesses.first.id, 'pool');
        await tester.ensureVisible(find.text('View details').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('View details').last);
        await tester.pumpAndSettle();
        expect(find.text('Eden Turf'), findsWidgets);
        expect(find.text('Ground 1'), findsOneWidget);
        await tester.ensureVisible(find.text('Rename business'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rename business'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextFormField), 'New turf name');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(source.businesses.last.name, 'New turf name');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  for (final owner in [true, false]) {
    testWidgets('Profile navigation respects owner=$owner', (tester) async {
      final source = ManagementSource()..owner = owner;
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      addTearDown(workspace.close);
      final auth = AuthCubit(ProfileAuth());
      addTearDown(auth.close);
      SharedPreferences.setMockInitialValues({});
      final settings = SettingsCubit(await SharedPreferences.getInstance());
      addTearDown(settings.close);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const ProfileScreen()),
          GoRoute(
            path: '/businesses',
            builder: (_, _) =>
                const Scaffold(body: Text('Management destination')),
          ),
        ],
      );
      addTearDown(router.dispose);
      final profileBoundary = GlobalKey();
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider.value(value: workspace),
            BlocProvider.value(value: auth),
            BlocProvider.value(value: settings),
          ],
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp.router(
              theme: managementPreviewTheme(),
              routerConfig: router,
              builder: (_, child) =>
                  RepaintBoundary(key: profileBoundary, child: child!),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('BUSINESS_PREVIEWS')) {
        await tester.runAsync(() async {
          final render =
              profileBoundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/profile-$owner.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(find.text('Eden Turf'), findsNothing);
      expect(
        find.text('Organization details'),
        owner ? findsOneWidget : findsNothing,
      );
      expect(find.text('Customers'), findsOneWidget);
      expect(find.text('Businesses'), owner ? findsOneWidget : findsNothing);
      if (owner) {
        await tester.ensureVisible(find.text('Businesses'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Businesses'));
        await tester.tap(find.text('Businesses'));
        await tester.pumpAndSettle();
        expect(find.text('Management destination'), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
