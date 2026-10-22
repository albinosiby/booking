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
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/screens/admissions_screen.dart';
import 'package:eden_booking/modules/admissions/screens/admission_form_screen.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:eden_booking/modules/admissions/repositories/rest_admission_repository.dart';
import 'booking_module_test.dart' show FakeBookingRepository;
import 'admissions_test.dart' show AdmissionsFake, workspace, example;

Admission student(
  String id, {
  String space = 'pool',
  String plan = 'plan',
  String kind = 'swimming',
}) {
  final a = example();
  return Admission(
    id: id,
    reference: 'AD-$id',
    businessId: 'business',
    poolId: space,
    planId: plan,
    customer: a.customer.copyWith(name: 'Student $id'),
    planName: plan == 'coaching' ? 'Swimming coaching' : 'Monthly swimming',
    kind: kind,
    coach: 'Coach Asha',
    mode: a.mode,
    status: a.status,
    start: a.start,
    expiry: a.expiry,
    allowance: a.allowance,
    used: a.used,
    remaining: a.remaining,
    total: a.total,
    paid: a.paid,
    balance: a.balance,
    version: a.version,
    duration: a.duration,
    time: a.time,
    weekdays: a.weekdays,
    poolName: 'Pool 1',
    businessName: 'Swimming Centre',
  );
}

class OverviewFake extends AdmissionsFake {
  bool manage = true, fail = false, deny = false;
  Completer<AdmissionPage>? delayedRoster;
  final calls = <({String? plan, String? space, int cursor, bool previous})>[];
  final students = [
    student('A'),
    student('B'),
    student('C'),
    student('D', space: 'pool-2', plan: 'other'),
    student('E', plan: 'coaching', kind: 'coaching'),
    student('F', plan: 'removed'),
  ];
  @override
  Future<AdmissionCatalog> catalog() async => AdmissionCatalog(
    canManage: manage,
    canAttend: true,
    canCollect: true,
    owner: manage,
    businesses: const [
      AdmissionBusiness(
        'business',
        'Swimming Centre',
        '2030-06-04',
        'Asia/Kolkata',
        [
          AdmissionPool('pool', 'Pool 1', [60], 60),
          AdmissionPool('pool-2', 'Pool 2', [60], 60),
        ],
        [
          AdmissionPlan(
            'plan',
            'Monthly swimming',
            'swimming',
            ['pool'],
            25,
            300000,
            null,
            'Unassigned',
            expiryMode: 'after_months',
            expiryMonths: 1,
          ),
          AdmissionPlan(
            'other',
            'Weekend swimming',
            'swimming',
            ['pool-2'],
            8,
            120000,
            null,
            'Unassigned',
            expiryMode: 'after_months',
            expiryMonths: 1,
          ),
          AdmissionPlan(
            'coaching',
            'Swimming coaching',
            'coaching',
            ['pool', 'pool-2'],
            12,
            400000,
            60,
            'Coach Asha',
            expiryMode: 'after_months',
            expiryMonths: 1,
            seats: 8,
          ),
        ],
      ),
    ],
  );
  @override
  Future<AdmissionPage> list({
    String query = '',
    String kind = 'swimming',
    String? status,
    String? businessId,
    String? spaceId,
    String? planId,
    bool previousPlans = false,
    int cursor = 0,
  }) async {
    calls.add((
      plan: planId,
      space: spaceId,
      cursor: cursor,
      previous: previousPlans,
    ));
    if (deny) throw const AppException('Forbidden', code: 'FORBIDDEN');
    if (planId == 'plan' && delayedRoster != null) return delayedRoster!.future;
    if (fail && planId == 'plan') {
      throw const AppException('Offline', code: 'NETWORK');
    }
    final filtered = students
        .where(
          (a) =>
              a.kind == kind &&
              a.businessId == businessId &&
              a.poolId == spaceId &&
              (previousPlans ? a.planId == 'removed' : a.planId == planId) &&
              (status == null || a.status == status) &&
              a.customer.name.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    final page = filtered.skip(cursor).take(2).toList();
    return AdmissionPage(
      page,
      cursor + page.length < filtered.length ? cursor + page.length : null,
    );
  }
}

Future<void> settleRequests() => Future<void>.delayed(Duration.zero);

Future<void> captureOverview(
  WidgetTester tester,
  GlobalKey boundary,
  String name,
) async {
  if (!const bool.fromEnvironment('ADMISSIONS_PREVIEWS')) return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = File('.local/admissions-previews/$name.png');
    await output.parent.create(recursive: true);
    await output.writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

ThemeData overviewTheme(bool dark) {
  final theme = AppTheme.build(dark ? Brightness.dark : Brightness.light);
  if (!const bool.fromEnvironment('ADMISSIONS_PREVIEWS')) return theme;
  const buttonText = WidgetStatePropertyAll(
    TextStyle(fontFamily: 'Roboto', fontSize: 15, fontWeight: FontWeight.w700),
  );
  return theme.copyWith(
    textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
    filledButtonTheme: FilledButtonThemeData(
      style: theme.filledButtonTheme.style?.copyWith(textStyle: buttonText),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: theme.outlinedButtonTheme.style?.copyWith(textStyle: buttonText),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (theme.textButtonTheme.style ?? const ButtonStyle()).copyWith(
        textStyle: buttonText,
      ),
    ),
    floatingActionButtonTheme: theme.floatingActionButtonTheme.copyWith(
      extendedTextStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class RosterApi extends Fake implements RestApiService {
  final paths = <String>[];
  @override
  Future<dynamic> retainedRead(
    String path, {
    Duration freshFor = const Duration(seconds: 20),
    Duration retainFor = const Duration(minutes: 15),
  }) async {
    paths.add(path);
    return {'items': [], 'next_cursor': null};
  }
}

Future<(AdmissionCubit, GoRouter)> pumpOverview(
  WidgetTester tester,
  OverviewFake repository, {
  Size size = const Size(390, 900),
  bool dark = false,
  double textScale = 1,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final session = await workspace();
  addTearDown(session.close);
  late AdmissionCubit overview;
  var created = false;
  getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>((s, _) {
    final controller = AdmissionCubit(s, repository);
    if (!created) {
      overview = controller;
      created = true;
    }
    return controller;
  });
  final router = GoRouter(
    initialLocation: '/admissions',
    routes: [
      GoRoute(path: '/admissions', builder: (_, _) => const AdmissionsScreen()),
      GoRoute(
        path: '/admissions/new',
        builder: (_, s) => AdmissionFormScreen(
          formKind: s.uri.queryParameters['kind'],
          businessId: s.uri.queryParameters['business_id'],
          poolId: s.uri.queryParameters['space_id'],
          planId: s.uri.queryParameters['plan_id'],
        ),
      ),
      GoRoute(
        path: '/admissions/:id',
        builder: (_, s) => Scaffold(
          appBar: AppBar(),
          body: Text('Detail ${s.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => BlocProvider.value(
        value: session,
        child: MaterialApp.router(
          theme: overviewTheme(dark),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  return (overview, router);
}

void main() {
  tearDown(getIt.reset);
  setUpAll(() async {
    if (!const bool.fromEnvironment('ADMISSIONS_PREVIEWS')) return;
    const directory = String.fromEnvironment('ADMISSIONS_FONT_DIR');
    for (final entry in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File('$directory/${entry.value}').readAsBytes();
      await (FontLoader(
        entry.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });

  test(
    'roster transport includes every scope and page in the retained read key',
    () async {
      final api = RosterApi();
      final repository = RestAdmissionRepository(api, FakeBookingRepository());
      await repository.list(
        kind: 'coaching',
        businessId: 'business',
        spaceId: 'court',
        planId: 'batch',
        status: 'active',
        query: 'Anjali',
        cursor: 50,
      );
      expect(Uri.parse(api.paths.single).queryParameters, {
        'kind': 'coaching',
        'business_id': 'business',
        'resource_id': 'court',
        'plan_id': 'batch',
        'status': 'active',
        'q': 'Anjali',
        'cursor': '50',
      });
      await repository.list(previousPlans: true, spaceId: 'pool-2');
      expect(
        Uri.parse(api.paths.last).queryParameters['previous_plans'],
        'true',
      );
      expect(api.paths.first, isNot(api.paths.last));
    },
  );

  test(
    'each plan paginates independently and previous plans remain available',
    () async {
      final session = await workspace(), repository = OverviewFake();
      final c = AdmissionCubit(session, repository);
      await c.loadOverview();
      expect(c.state.overview.businessId, 'business');
      expect(c.state.overview.spaceId, 'pool');
      expect(c.state.overview.rosters.keys, ['plan', 'previous-plans']);
      expect(c.state.overview.rosters['plan']!.items.map((a) => a.id), [
        'A',
        'B',
      ]);
      expect(c.state.overview.rosters['previous-plans']!.items.single.id, 'F');
      await c.loadRoster('plan', more: true);
      expect(c.state.overview.rosters['plan']!.items.map((a) => a.id), [
        'A',
        'B',
        'C',
      ]);
      expect(c.state.overview.rosters['plan']!.next, isNull);
      expect(repository.calls.last, (
        plan: 'plan',
        space: 'pool',
        cursor: 2,
        previous: false,
      ));
      await c.close();
      await session.close();
    },
  );

  test(
    'tabs remember their spaces and roster failures retain loaded data',
    () async {
      final session = await workspace(), repository = OverviewFake();
      final c = AdmissionCubit(session, repository);
      await c.loadOverview();
      repository.fail = true;
      await c.loadRoster('plan');
      expect(c.state.overview.rosters['plan']!.items.length, 2);
      expect(c.state.overview.rosters['plan']!.error, 'Offline');
      repository.fail = false;
      await c.loadRoster('plan');
      expect(c.state.overview.rosters['plan']!.error, isNull);
      c.selectOverview(spaceId: 'pool-2');
      await settleRequests();
      expect(c.state.overview.rosters['other']!.items.single.id, 'D');
      c.selectOverview(coaching: true);
      await settleRequests();
      expect(c.state.overview.spaceId, 'pool-2');
      c.selectOverview(spaceId: 'pool');
      await settleRequests();
      expect(c.state.overview.rosters['coaching']!.items.single.id, 'E');
      c.selectOverview(coaching: false);
      await settleRequests();
      expect(c.state.overview.spaceId, 'pool-2');
      await c.close();
      await session.close();
    },
  );

  test('late roster responses cannot replace a newly selected space', () async {
    final session = await workspace(),
        repository = OverviewFake()..delayedRoster = Completer<AdmissionPage>();
    final c = AdmissionCubit(session, repository);
    final first = c.loadOverview();
    await settleRequests();
    c.selectOverview(spaceId: 'pool-2');
    await settleRequests();
    repository.delayedRoster!.complete(AdmissionPage([student('late')], null));
    await first;
    expect(c.state.overview.spaceId, 'pool-2');
    expect(c.state.overview.rosters.containsKey('plan'), isFalse);
    expect(c.state.overview.rosters['other']!.items.single.id, 'D');
    await c.close();
    await session.close();
  });

  test('access failures clear all previously loaded rosters', () async {
    final session = await workspace(), repository = OverviewFake();
    final c = AdmissionCubit(session, repository);
    await c.loadOverview();
    repository.deny = true;
    await c.loadOverview();
    expect(c.state.overview.rosters, isEmpty);
    expect(c.state.catalog.businesses, isEmpty);
    expect(c.state.error, contains('Access denied'));
    await c.close();
    await session.close();
  });

  test(
    'repeated load-more taps share one request without duplicate students',
    () async {
      final session = await workspace(), repository = OverviewFake();
      final c = AdmissionCubit(session, repository);
      await c.loadOverview();
      repository.delayedRoster = Completer<AdmissionPage>();
      final before = repository.calls.length;
      final first = c.loadRoster('plan', more: true);
      await c.loadRoster('plan', more: true);
      expect(repository.calls.length, before + 1);
      repository.delayedRoster!.complete(
        AdmissionPage([student('B'), student('C')], null),
      );
      await first;
      expect(c.state.overview.rosters['plan']!.items.map((a) => a.id), [
        'A',
        'B',
        'C',
      ]);
      await c.close();
      await session.close();
    },
  );

  test(
    'admission forms restrict plan choices while retaining the selected space',
    () async {
      final session = await workspace();
      final c = AdmissionCubit(session, OverviewFake());
      await c.loadForm(
        formKind: 'plans',
        businessId: 'business',
        poolId: 'pool-2',
      );
      expect(c.state.availablePlans.map((p) => p.id), ['other']);
      expect(c.state.draft.planId, 'other');
      c.plan('coaching');
      expect(c.state.draft.planId, 'other');
      await c.loadForm(
        formKind: 'coaching',
        businessId: 'business',
        poolId: 'pool',
      );
      expect(c.state.availablePlans.map((p) => p.id), ['coaching']);
      expect(c.state.draft.planId, 'coaching');
      await c.loadForm(
        formKind: 'plans',
        businessId: 'business',
        poolId: 'pool',
        planId: 'coaching',
      );
      expect(c.state.draft.planId, isNull);
      await c.close();
      await session.close();
    },
  );

  for (final (width, dark, scale) in [
    (320.0, false, 1.4),
    (390.0, true, 1.0),
    (1440.0, true, 1.0),
  ]) {
    testWidgets(
      'plans and coaching fit ${width.toInt()}px and FAB opens matching forms',
      (tester) async {
        final boundary = GlobalKey();
        final (c, router) = await pumpOverview(
          tester,
          OverviewFake(),
          size: Size(width, 1000),
          dark: dark,
          textScale: scale,
          boundary: boundary,
        );
        expect(find.text('Admissions'), findsNothing);
        expect(find.text('Plans'), findsOneWidget);
        expect(find.text('Coaching'), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsOneWidget);
        await captureOverview(tester, boundary, 'overview-${width.toInt()}');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('plan-plan')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('plan-plan')), findsOneWidget);
        expect(find.byKey(const ValueKey('admission-A')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureOverview(tester, boundary, 'plans-${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('admissions-new')));
        await tester.pumpAndSettle();
        expect(find.text('New plan admission'), findsOneWidget);
        final form = tester.widget<AdmissionFormScreen>(
          find.byType(AdmissionFormScreen),
        );
        expect(form.formKind, 'plans');
        expect(form.poolId, 'pool');
        final planPicker = tester.widget<AppPicker>(
          find.byWidgetPredicate((w) => w is AppPicker && w.label == 'Plan'),
        );
        expect(planPicker.items.map((p) => p.value), ['plan']);
        router.pop();
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Coaching'));
        await tester.pumpAndSettle();
        expect(c.state.overview.coaching, isTrue);
        await captureOverview(tester, boundary, 'coaching-${width.toInt()}');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('plan-coaching')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('plan-coaching')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('admissions-new')));
        await tester.pumpAndSettle();
        expect(find.text('New coaching admission'), findsOneWidget);
        final coachingPicker = tester.widget<AppPicker>(
          find.byWidgetPredicate((w) => w is AppPicker && w.label == 'Plan'),
        );
        expect(coachingPicker.items.map((p) => p.value), ['coaching']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'student detail return preserves tab and space, read-only access hides FAB',
    (tester) async {
      final repository = OverviewFake()..manage = false;
      final (c, router) = await pumpOverview(tester, repository);
      expect(find.byType(FloatingActionButton), findsNothing);
      c.selectOverview(coaching: true);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('admission-E')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('admission-E')));
      await tester.pumpAndSettle();
      expect(find.text('Detail E'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      expect(c.state.overview.coaching, isTrue);
      expect(c.state.overview.spaceId, 'pool');
      expect(find.byKey(const ValueKey('admission-E')), findsOneWidget);
    },
  );
}
