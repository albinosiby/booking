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
import 'package:eden_booking/modules/admissions/widgets/admission_cards.dart';
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
  String business = 'business',
  String status = 'active',
}) {
  final a = example();
  return Admission(
    id: id,
    reference: 'AD-$id',
    businessId: business,
    poolId: space,
    planId: plan,
    customer: a.customer.copyWith(name: 'Student $id'),
    planName: plan == 'coaching'
        ? 'Swimming coaching'
        : kind == 'play'
        ? 'Court membership'
        : 'Monthly swimming',
    kind: kind,
    coach: 'Coach Asha',
    mode: a.mode,
    status: status,
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
    poolName: space == 'court'
        ? 'Court 1'
        : space == 'pool-2'
        ? 'Pool 2'
        : 'Pool 1',
    businessName: business == 'business' ? 'Swimming Centre' : 'Sports Centre',
  );
}

class OverviewFake extends AdmissionsFake {
  bool manage = true, fail = false, deny = false;
  Completer<AdmissionPage>? delayedRoster;
  final calls =
      <
        ({
          String kind,
          String? business,
          String? plan,
          String? space,
          String? status,
          String query,
          int cursor,
          bool previous,
        })
      >[];
  final students = [
    student('A'),
    student('B'),
    student('C'),
    student('D', space: 'pool-2', plan: 'other'),
    student('E', plan: 'coaching', kind: 'coaching'),
    student('F', plan: 'removed'),
    student(
      'G',
      business: 'sports',
      space: 'court',
      plan: 'play',
      kind: 'play',
    ),
    student('H', status: 'cancelled'),
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
      AdmissionBusiness(
        'sports',
        'Sports Centre',
        '2030-06-04',
        'Asia/Kolkata',
        [
          AdmissionPool('court', 'Court 1', [60], 60),
        ],
        [
          AdmissionPlan(
            'play',
            'Court membership',
            'play',
            ['court'],
            10,
            100000,
            null,
            'Unassigned',
          ),
        ],
        spaceKind: 'court',
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
      kind: kind,
      business: businessId,
      plan: planId,
      space: spaceId,
      status: status,
      query: query,
      cursor: cursor,
      previous: previousPlans,
    ));
    if (deny) throw const AppException('Forbidden', code: 'FORBIDDEN');
    if (kind == 'swimming' && spaceId == null && delayedRoster != null) {
      return delayedRoster!.future;
    }
    if (fail && kind == 'swimming') {
      throw const AppException('Offline', code: 'NETWORK');
    }
    final filtered = students
        .where(
          (a) =>
              a.kind == kind &&
              (businessId == null || a.businessId == businessId) &&
              (spaceId == null || a.poolId == spaceId) &&
              (previousPlans
                  ? a.planId == 'removed'
                  : planId == null || a.planId == planId) &&
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

Future<void> chooseOverviewFilter(
  WidgetTester tester,
  String key,
  String option,
) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, option));
  await tester.pumpAndSettle();
}

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
      await repository.list(kind: 'play');
      expect(Uri.parse(api.paths.last).queryParameters, {
        'q': '',
        'kind': 'play',
        'cursor': '0',
      });
    },
  );

  test(
    'global Plans roster combines businesses and retains historical plans',
    () async {
      final session = await workspace(), repository = OverviewFake();
      final c = AdmissionCubit(session, repository);
      await c.loadOverview();
      expect(c.state.overview.businessId, isNull);
      expect(c.state.overview.spaceId, isNull);
      expect(c.state.overview.rosters.keys, ['swimming', 'play']);
      expect(c.state.overview.rosters['swimming']!.items.map((a) => a.id), [
        'A',
        'B',
      ]);
      expect(c.state.overview.rosters['play']!.items.single.id, 'G');
      expect(repository.calls.map((call) => call.kind), ['swimming', 'play']);
      expect(repository.calls.every((call) => call.business == null), isTrue);
      expect(repository.calls.every((call) => call.space == null), isTrue);
      expect(repository.calls.every((call) => call.plan == null), isTrue);
      expect(repository.calls.every((call) => !call.previous), isTrue);
      await c.loadMoreStudents();
      expect(c.state.overview.rosters['swimming']!.items.map((a) => a.id), [
        'A',
        'B',
        'C',
        'D',
      ]);
      expect(repository.calls.last, (
        kind: 'swimming',
        business: null,
        plan: null,
        space: null,
        status: null,
        query: '',
        cursor: 2,
        previous: false,
      ));
      await c.loadMoreStudents();
      expect(c.state.overview.rosters['swimming']!.items.map((a) => a.id), [
        'A',
        'B',
        'C',
        'D',
        'F',
        'H',
      ]);
      expect(c.state.overview.rosters['swimming']!.next, isNull);
      await c.close();
      await session.close();
    },
  );

  test(
    'tabs remember location filters and roster failures retain loaded data',
    () async {
      final session = await workspace(), repository = OverviewFake();
      final c = AdmissionCubit(session, repository);
      await c.loadOverview();
      repository.fail = true;
      await c.loadRoster('swimming');
      expect(c.state.overview.rosters['swimming']!.items.length, 2);
      expect(c.state.overview.rosters['swimming']!.error, 'Offline');
      repository.fail = false;
      await c.loadRoster('swimming');
      expect(c.state.overview.rosters['swimming']!.error, isNull);
      c.selectOverview(
        businessId: 'business',
        spaceId: 'pool-2',
        status: 'active',
      );
      await settleRequests();
      expect(c.state.overview.rosters['swimming']!.items.single.id, 'D');
      c.selectOverview(coaching: true);
      await settleRequests();
      expect(c.state.overview.spaceId, 'pool-2');
      expect(c.state.overview.status, 'active');
      c.selectOverview(spaceId: 'pool');
      await settleRequests();
      expect(c.state.overview.rosters['coaching']!.items.single.id, 'E');
      c.selectOverview(status: 'cancelled');
      await settleRequests();
      c.selectOverview(coaching: false);
      await settleRequests();
      expect(c.state.overview.spaceId, 'pool-2');
      expect(c.state.overview.status, 'active');
      c.selectOverview(coaching: true);
      await settleRequests();
      expect(c.state.overview.spaceId, 'pool');
      expect(c.state.overview.status, 'cancelled');
      c.selectOverview(clearSelection: true, clearStatus: true);
      await settleRequests();
      c.selectOverview(coaching: false);
      await settleRequests();
      expect(c.state.overview.spaceId, 'pool-2');
      c.selectOverview(coaching: true);
      await settleRequests();
      expect(c.state.overview.businessId, isNull);
      expect(c.state.overview.spaceId, isNull);
      expect(c.state.overview.status, isNull);
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
    c.selectOverview(businessId: 'business', spaceId: 'pool-2');
    await settleRequests();
    repository.delayedRoster!.complete(AdmissionPage([student('late')], null));
    await first;
    expect(c.state.overview.spaceId, 'pool-2');
    expect(c.state.overview.rosters['swimming']!.items.single.id, 'D');
    await c.close();
    await session.close();
  });

  test(
    'business changes clear incompatible spaces and clearing restores all',
    () async {
      final session = await workspace(), repository = OverviewFake();
      final c = AdmissionCubit(session, repository);
      await c.loadOverview();
      c.selectOverview(businessId: 'business', spaceId: 'pool-2');
      await settleRequests();
      c.selectOverview(businessId: 'sports');
      await settleRequests();
      expect(c.state.overview.businessId, 'sports');
      expect(c.state.overview.spaceId, isNull);
      expect(
        c.state.overview.rosters.values.expand((r) => r.items).map((a) => a.id),
        ['G'],
      );
      expect(repository.calls.last.business, 'sports');
      expect(repository.calls.last.space, isNull);
      c.selectOverview(
        query: 'Student H',
        status: 'cancelled',
        clearSelection: true,
      );
      await settleRequests();
      expect(c.state.overview.businessId, isNull);
      expect(c.state.overview.spaceId, isNull);
      expect(c.state.overview.rosters['swimming']!.items.single.id, 'H');
      expect(repository.calls.last.query, 'Student H');
      expect(repository.calls.last.status, 'cancelled');
      c.selectOverview(query: '', clearStatus: true);
      await settleRequests();
      expect(c.state.overview.status, isNull);
      expect(c.state.overview.rosters['play']!.items.single.id, 'G');
      await c.close();
      await session.close();
    },
  );

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
      final first = c.loadRoster('swimming', more: true);
      await c.loadRoster('swimming', more: true);
      expect(repository.calls.length, before + 1);
      repository.delayedRoster!.complete(
        AdmissionPage([student('B'), student('C')], null),
      );
      await first;
      expect(c.state.overview.rosters['swimming']!.items.map((a) => a.id), [
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
        expect(find.byType(AppPicker), findsNothing);
        expect(find.byTooltip('Filter admissions'), findsOneWidget);
        expect(
          tester.getTopLeft(find.byKey(const ValueKey('admission-search'))).dy,
          lessThan(
            tester.getTopLeft(find.byKey(const ValueKey('admission-tabs'))).dy,
          ),
        );
        expect(find.byType(AdmissionPlanCard), findsNothing);
        expect(find.text('Enroll student'), findsNothing);
        await captureOverview(tester, boundary, 'overview-${width.toInt()}');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('admission-A')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('admission-A')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await captureOverview(tester, boundary, 'plans-${width.toInt()}');
        await tester.tap(find.byKey(const ValueKey('admissions-new')));
        await tester.pumpAndSettle();
        final form = tester.widget<AdmissionFormScreen>(
          find.byType(AdmissionFormScreen),
        );
        expect(form.formKind, 'plans');
        expect(form.businessId, isNull);
        expect(form.poolId, isNull);
        expect(
          find.byWidgetPredicate(
            (w) => w is AppPicker && w.label == 'Admission type',
          ),
          findsOneWidget,
        );
        final planPicker = tester.widget<AppPicker>(
          find.byWidgetPredicate((w) => w is AppPicker && w.label == 'Plan'),
        );
        expect(planPicker.items.map((p) => p.value), ['plan']);
        if (const bool.fromEnvironment('ADMISSIONS_PREVIEWS')) {
          await Scrollable.ensureVisible(
            tester.element(find.byKey(const ValueKey('admission-type'))),
            alignment: .15,
          );
          await tester.pumpAndSettle();
          await captureOverview(
            tester,
            boundary,
            'form-plans-${width.toInt()}',
          );
        }
        router.pop();
        await tester.pumpAndSettle();
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 2000));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Coaching'));
        await tester.pumpAndSettle();
        expect(c.state.overview.coaching, isTrue);
        await captureOverview(tester, boundary, 'coaching-${width.toInt()}');
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('admission-E')),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('admission-E')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('admissions-new')));
        await tester.pumpAndSettle();
        final coachingForm = tester.widget<AdmissionFormScreen>(
          find.byType(AdmissionFormScreen),
        );
        expect(coachingForm.formKind, 'coaching');
        expect(coachingForm.businessId, isNull);
        expect(coachingForm.poolId, isNull);
        final coachingPicker = tester.widget<AppPicker>(
          find.byWidgetPredicate(
            (w) => w is AppPicker && w.label == 'Coaching plan',
          ),
        );
        expect(coachingPicker.items.map((p) => p.value), ['coaching']);
        if (const bool.fromEnvironment('ADMISSIONS_PREVIEWS')) {
          await Scrollable.ensureVisible(
            tester.element(find.byKey(const ValueKey('admission-type'))),
            alignment: .15,
          );
          await tester.pumpAndSettle();
          await captureOverview(
            tester,
            boundary,
            'form-coaching-${width.toInt()}',
          );
        }
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
      expect(c.state.overview.spaceId, isNull);
      expect(find.byKey(const ValueKey('admission-E')), findsOneWidget);
    },
  );

  testWidgets('search spans locations and stays shared between tabs', (
    tester,
  ) async {
    final repository = OverviewFake();
    final (c, _) = await pumpOverview(tester, repository);
    await tester.enterText(
      find.byKey(const ValueKey('admission-search')),
      'Student G',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(c.state.overview.query, 'Student G');
    expect(c.state.overview.rosters['play']!.items.single.id, 'G');
    expect(find.byKey(const ValueKey('admission-G')), findsOneWidget);
    expect(find.byKey(const ValueKey('admission-A')), findsNothing);
    await tester.tap(find.text('Coaching'));
    await tester.pumpAndSettle();
    expect(c.state.overview.query, 'Student G');
    expect(find.text('No students match these filters'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(c.state.overview.query, isEmpty);
    expect(c.state.overview.rosters['coaching']!.items.single.id, 'E');
    expect(find.byKey(const ValueKey('admission-E')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'filters apply atomically, cancel and clear at ${width.toInt()}px',
      (tester) async {
        final repository = OverviewFake();
        final boundary = GlobalKey();
        final (c, router) = await pumpOverview(
          tester,
          repository,
          size: Size(width, 1000),
          boundary: boundary,
        );
        final initialCalls = repository.calls.length;
        await tester.tap(find.byTooltip('Filter admissions'));
        await tester.pumpAndSettle();
        expect(find.text('All businesses'), findsOneWidget);
        expect(find.text('All pools or courts'), findsOneWidget);
        expect(find.text('All statuses'), findsOneWidget);
        await captureOverview(tester, boundary, 'filters-${width.toInt()}');
        await chooseOverviewFilter(
          tester,
          'admission-filter-business',
          'Swimming Centre',
        );
        await chooseOverviewFilter(tester, 'admission-filter-space', 'Pool 2');
        await chooseOverviewFilter(tester, 'admission-filter-status', 'Active');
        expect(c.state.overview.businessId, isNull);
        expect(repository.calls.length, initialCalls);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(c.state.overview.businessId, isNull);
        expect(c.state.overview.spaceId, isNull);
        expect(c.state.overview.status, isNull);
        expect(repository.calls.length, initialCalls);

        await tester.tap(find.byTooltip('Filter admissions'));
        await tester.pumpAndSettle();
        await chooseOverviewFilter(
          tester,
          'admission-filter-business',
          'Swimming Centre',
        );
        await chooseOverviewFilter(tester, 'admission-filter-space', 'Pool 2');
        await chooseOverviewFilter(tester, 'admission-filter-status', 'Active');
        await tester.tap(find.text('Apply filters'));
        await tester.pumpAndSettle();
        expect(c.state.overview.businessId, 'business');
        expect(c.state.overview.spaceId, 'pool-2');
        expect(c.state.overview.status, 'active');
        expect(c.state.overview.rosters['swimming']!.items.single.id, 'D');
        expect(find.byKey(const ValueKey('admission-D')), findsOneWidget);
        expect(find.byType(AppPicker), findsNothing);
        await tester.tap(find.byKey(const ValueKey('admissions-new')));
        await tester.pumpAndSettle();
        final form = tester.widget<AdmissionFormScreen>(
          find.byType(AdmissionFormScreen),
        );
        expect(form.formKind, 'plans');
        expect(form.businessId, 'business');
        expect(form.poolId, 'pool-2');
        router.pop();
        await tester.pumpAndSettle();
        expect(c.state.overview.spaceId, 'pool-2');

        await tester.tap(find.byTooltip('Filter admissions'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Clear filters'));
        await tester.pumpAndSettle();
        expect(c.state.overview.businessId, isNull);
        expect(c.state.overview.spaceId, isNull);
        expect(c.state.overview.status, isNull);
        expect(find.byType(AppPicker), findsNothing);
        expect(c.state.overview.rosters['play']!.items.single.id, 'G');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
