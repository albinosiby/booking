import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/businesses/screens/resource_setup_screen.dart';
import 'package:eden_booking/modules/turf/repositories/turf_repository.dart';
import 'package:eden_booking/modules/turf/screens/turf_setup_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'turf_setup_test.dart' show TurfSource, FakeTurfRepository;

/// Workspace with one generic (pool) business for the resource setup screen.
class ResourceSource extends Fake implements WorkspaceRepository {
  List<Resource> resources = const [
    Resource(id: 'lane-1', name: 'Pool 1', capacity: 20),
  ];
  Map<String, dynamic>? configuration;
  @override
  Future<Workspace> load() async => Workspace(
    organization: const Organization(
      id: 'org',
      name: 'Eden',
      phone: '12345678',
      currency: 'INR',
    ),
    membership: const {'role': 'owner'},
    locations: const [
      {
        'id': 'location',
        'name': 'Eden Arena',
        'city': 'Kochi',
        'timezone': 'Asia/Kolkata',
      },
    ],
    businesses: [
      Business(
        id: 'pool',
        name: 'Eden Swimming',
        type: BusinessType.pool,
        status: 'draft',
        locationId: 'location',
        version: 1,
        resources: resources,
        configuration: configuration,
      ),
    ],
  );
}

class FakeResourceBusinessRepository extends Fake
    implements BusinessRepository {}

void desktopView(WidgetTester tester) {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget app(WorkspaceCubit session, Widget home) => BlocProvider.value(
  value: session,
  child: ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (context, child) => MaterialApp(theme: darkTheme(), home: home),
  ),
);

Future<WorkspaceCubit> turfSession() async {
  final source = TurfSource();
  getIt.registerSingleton<WorkspaceRepository>(source);
  registerFeatureDependencies(getIt);
  await getIt.unregister<TurfRepository>();
  getIt.registerSingleton<TurfRepository>(FakeTurfRepository(source));
  final session = WorkspaceCubit(source);
  await session.load();
  addTearDown(session.close);
  return session;
}

Future<void> tapNav(WidgetTester tester, String key) async {
  final item = find.byKey(ValueKey(key));
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() async {
    await getIt.reset();
  });

  testWidgets(
    'turf setup wizard uses the configuration workspace with a step rail at 1440px',
    (tester) async {
      desktopView(tester);
      final session = await turfSession();
      await tester.pumpWidget(
        app(session, const TurfSetupScreen(businessId: 'turf')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('configuration-workspace')), findsOne);
      expect(find.byKey(const ValueKey('turf-step-progress')), findsOne);
      expect(find.byKey(const ValueKey('turf-nav-overview')), findsNothing);
      expect(find.text('Sports offered.'), findsOneWidget);
      // Future steps stay locked until Continue validates the current one.
      await tapNav(tester, 'turf-nav-grounds');
      expect(find.text('Sports offered.'), findsOneWidget);
      final next = find.descendant(
        of: find.byKey(const ValueKey('configuration-actions')),
        matching: find.text('Continue'),
      );
      await tester.ensureVisible(next);
      await tester.tap(next);
      await tester.pumpAndSettle();
      expect(find.text('Your physical grounds.'), findsOneWidget);
      // Past steps reopen from the rail, like the phone step chips.
      await tapNav(tester, 'turf-nav-sports');
      expect(find.text('Sports offered.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'turf settings rail opens sections and returns to the overview at 1440px',
    (tester) async {
      desktopView(tester);
      final session = await turfSession();
      await tester.pumpWidget(
        app(session, const TurfSetupScreen(businessId: 'turf', editMode: true)),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('configuration-workspace')), findsOne);
      expect(find.text('Turf settings'), findsWidgets);
      expect(find.byType(AppGrid), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      await tapNav(tester, 'turf-nav-pricing');
      expect(find.text('Timing & pricing.'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('configuration-actions')),
          matching: find.text('Save changes'),
        ),
        findsOneWidget,
      );
      await tapNav(tester, 'turf-nav-spaces');
      expect(find.text('Bookable spaces.'), findsOneWidget);
      await tapNav(tester, 'turf-nav-overview');
      expect(
        find.byKey(const ValueKey('turf-settings-section-4')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'generic resource setup uses the configuration workspace at 1440px',
    (tester) async {
      desktopView(tester);
      final source = ResourceSource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      await getIt.unregister<BusinessRepository>();
      getIt.registerSingleton<BusinessRepository>(
        FakeResourceBusinessRepository(),
      );
      final session = WorkspaceCubit(source);
      await session.load();
      addTearDown(session.close);
      await tester.pumpWidget(
        app(session, const ResourceSetupScreen(businessId: 'pool')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('configuration-workspace')), findsOne);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.text('Your pools'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('configuration-actions')),
          matching: find.text('Continue to rules'),
        ),
        findsOneWidget,
      );
      await tapNav(tester, 'resource-nav-rules');
      expect(find.text('Operating days'), findsOneWidget);
      expect(find.text('Save and review'), findsOneWidget);
      // Review stays locked until rules are saved, as on phones.
      await tapNav(tester, 'resource-nav-review');
      expect(find.text('Save rules and pricing before reviewing.'), findsOne);
      expect(find.text('Operating days'), findsOneWidget);
      await tapNav(tester, 'resource-nav-resources');
      expect(find.text('Your pools'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
