import 'package:eden_booking/modules/configuration_drafts/models/configuration_draft.dart';
import 'package:eden_booking/modules/court/models/court_configuration.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/court/cubit/court_setup_cubit.dart';
import 'package:eden_booking/modules/court/models/court_screen_models.dart';
import 'package:eden_booking/modules/court/models/court_setup_state.dart';
import 'package:eden_booking/modules/court/screens/court_setup_screen.dart';
import 'package:eden_booking/modules/court/screens/court_pricing_screen.dart';
import 'package:eden_booking/modules/court/widgets/court_editors.dart';
import 'package:eden_booking/modules/turf/cubit/turf_setup_cubit.dart';
import 'package:eden_booking/modules/turf/models/turf_configuration.dart';
import 'package:eden_booking/modules/pool/cubit/pool_setup_cubit.dart';
import 'package:eden_booking/modules/hall/cubit/hall_setup_cubit.dart';
import 'turf_setup_test.dart' as turf;
import 'court_setup_test.dart' as court;
import 'pool_setup_test.dart' as pool;
import 'hall_setup_test.dart' as hall;

Future<void> host(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(theme: darkTheme(), home: child),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  test(
    'court opening day changes prune existing and new rules without losing prices or other courts',
    () async {
      final source = court.CourtSource(),
          workspace = WorkspaceCubit(court.CourtSource());
      await workspace.load();
      final repository = court.FakeCourtRepository(source);
      final c = CourtSetupCubit(workspace, repository, 'courts');
      addTearDown(c.close);
      addTearDown(workspace.close);
      c.addCourt();
      final id = c.state.selectedId!;
      court.priceCourt(c, id, '650');
      c.addCourt();
      final other = c.state.selectedId!;
      court.priceCourt(c, other, '700');
      c.updateCourt(
        id,
        (p) => p.copyWith(hours: p.hours.copyWith(days: [1, 2, 3, 4, 5, 6])),
      );
      var first = c.state.draft.courts.first;
      expect(first.tariffs.single.hours.days, [1, 2, 3, 4, 5, 6]);
      expect(first.tariffs.single.rates.single.price, '650');
      expect(c.state.draft.courts.last.tariffs.single.hours.days, contains(7));
      c.addTariff(id);
      expect(c.state.draft.courts.first.tariffs.last.hours.days, [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      c.tariffHours(
        id,
        first.tariffs.first.id,
        first.tariffs.first.hours.copyWith(days: [7]),
      );
      first = c.state.draft.courts.first;
      expect(first.tariffs.first.hours.days, isEmpty);
      expect(first.tariffs.first.rates.single.price, '650');
      c.updateCourt(
        id,
        (p) => p.copyWith(hours: p.hours.copyWith(days: [1, 2, 3, 4, 5, 6, 7])),
      );
      expect(c.state.draft.courts.first.tariffs.first.hours.days, isEmpty);
      expect(repository.writes, 0);
    },
  );

  test(
    'legacy local drafts normalize closed pricing days on recovery',
    () async {
      final source = court.CourtSource();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final repository = court.FakeCourtRepository(source);
      final c = CourtSetupCubit(workspace, repository, 'courts');
      addTearDown(c.close);
      addTearDown(workspace.close);
      final legacy = CourtConfiguration(
        courts: [
          CourtResource(
            id: 'old',
            name: 'Court 1',
            hours: CourtHours(days: [1, 2, 3, 4, 5, 6]),
            tariffs: [
              CourtTariff(
                id: 'rate',
                hours: CourtHours(),
                rates: const [CourtRate(60, '650')],
              ),
            ],
          ),
        ],
      );
      c.restoreLocalDraft(
        ConfigurationDraft(
          baseVersion: 1,
          configuration: legacy.toJson(localDraft: true),
          navigation: const {},
        ),
      );
      expect(c.state.draft.courts.single.tariffs.single.hours.days, [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(
        c.state.draft.courts.single.tariffs.single.rates.single.price,
        '650',
      );
      expect(repository.writes, 0);
    },
  );

  test(
    'turf rules follow effective opening days and linked cricket without changing other halves',
    () async {
      final source = turf.TurfSource(),
          workspace = WorkspaceCubit(turf.TurfSource());
      await workspace.load();
      final repository = turf.FakeTurfRepository(source);
      final c = TurfSetupCubit(workspace, repository, 'turf');
      addTearDown(c.close);
      addTearDown(workspace.close);
      for (final o
          in c.state.draft.offerings
              .where((o) => o.sport == TurfSport.football)
              .toList()) {
        c.price(o.id, 60, '600');
      }
      c.useFootballForCricket(true);
      final target = c.state.draft.offerings.firstWhere(
        (o) => o.sport == TurfSport.football,
      );
      c.offeringHours(
        target.id,
        c.state.draft.operating.copyWith(days: [1, 2, 3, 4, 5, 6]),
      );
      var changed = c.state.draft.offerings.where(
        (o) => o.layoutId == target.layoutId,
      );
      expect(
        changed.every((o) => !o.pricingRules.single.days.contains(7)),
        isTrue,
      );
      expect(
        changed.every((o) => o.pricingRules.single.rates.single.price == '600'),
        isTrue,
      );
      expect(
        c.state.draft.offerings
            .where((o) => o.layoutId != target.layoutId)
            .every((o) => o.pricingRules.single.days.contains(7)),
        isTrue,
      );
      c.hours(c.state.draft.operating.copyWith(days: [1, 2, 3, 4, 5]));
      expect(
        c.state.draft.offerings.every(
          (o) => o.pricingRules.single.days.length == 5,
        ),
        isTrue,
      );
      expect(repository.writes, 0);
    },
  );

  test(
    'pool tariffs group offers and plans follow common eligible opening days',
    () async {
      final source = pool.PoolSource(),
          workspace = WorkspaceCubit(pool.PoolSource());
      await workspace.load();
      final repository = pool.FakePoolRepository(source);
      final c = PoolSetupCubit(workspace, repository, 'pools');
      addTearDown(c.close);
      addTearDown(workspace.close);
      c.addPool();
      final a = c.state.selectedId!;
      c.addTariff(a);
      c.tariffPrice(a, c.state.draft.pools.first.tariffs.first.id, 60, '100');
      c.addPool();
      final b = c.state.selectedId!;
      c.addOffer();
      final offer = c.state.draft.offers.single.id;
      c.updateOffer(offer, (o) => o.copyWith(poolIds: [a, b], price: '2500'));
      c.addPlan(false);
      final plan = c.state.draft.plans.single.id;
      c.updatePlan(plan, (p) => p.copyWith(poolIds: [a, b], price: '2000'));
      c.updatePool(
        a,
        (p) => p.copyWith(hours: p.hours.copyWith(days: [1, 2, 3, 4, 5, 6])),
      );
      c.updatePool(
        b,
        (p) => p.copyWith(hours: p.hours.copyWith(days: [1, 2, 3, 4, 5, 7])),
      );
      expect(c.state.draft.pools.first.tariffs.single.hours.days, [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      expect(c.state.draft.offers.single.hours.days, [1, 2, 3, 4, 5]);
      expect(c.state.draft.plans.single.hours.days, [1, 2, 3, 4, 5]);
      expect(c.state.draft.offers.single.price, '2500');
      expect(c.state.draft.plans.single.price, '2000');
      expect(repository.writes, 0);
    },
  );

  test(
    'hall session and full-day prices follow hall and option opening days',
    () async {
      final source = hall.HallSource(),
          workspace = WorkspaceCubit(hall.HallSource());
      await workspace.load();
      final repository = hall.FakeHallRepository(source);
      final c = HallSetupCubit(workspace, repository, 'halls');
      addTearDown(c.close);
      addTearDown(workspace.close);
      c.addHall();
      final id = c.state.selectedId!;
      c.addTariff(id);
      final initial = c.state.draft.halls.single;
      for (final o in [...initial.sessions, initial.fullDay]) {
        c.enablePackage(id, o.id, true);
      }
      c.updateHall(
        id,
        (p) => p.copyWith(hours: p.hours.copyWith(days: [1, 2, 3, 4, 5, 6])),
      );
      var p = c.state.draft.halls.single;
      expect(p.tariffs.single.hours.days, [1, 2, 3, 4, 5, 6]);
      for (final o in [...p.sessions, p.fullDay]) {
        expect(o.hours.days, [1, 2, 3, 4, 5, 6]);
        expect(o.prices.single.days, [1, 2, 3, 4, 5, 6]);
      }
      final session = p.sessions.first.id;
      c.updatePackage(
        id,
        session,
        (o) => o.copyWith(hours: o.hours.copyWith(days: [6])),
      );
      p = c.state.draft.halls.single;
      expect(p.sessions.first.prices.single.days, [6]);
      expect(p.fullDay.prices.single.days, [1, 2, 3, 4, 5, 6]);
      expect(repository.writes, 0);
    },
  );

  testWidgets('pricing day presets cannot select a closed Sunday', (
    tester,
  ) async {
    List<int> selected = [];
    await host(
      tester,
      Scaffold(
        body: AppWeekdayPicker(
          days: const [],
          allowedDays: const [1, 2, 3, 4, 5, 6],
          onChanged: (days) => selected = days,
        ),
      ),
    );
    expect(find.text('Sun'), findsNothing);
    await tester.tap(find.text('Weekend'));
    expect(selected, [6]);
    await tester.tap(find.text('All open days'));
    expect(selected, [1, 2, 3, 4, 5, 6]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'court pricing hides closed days immediately after opening hours change',
    (tester) async {
      final source = court.CourtSource(),
          workspace = WorkspaceCubit(court.CourtSource());
      await workspace.load();
      final repository = court.FakeCourtRepository(source);
      final c = CourtSetupCubit(workspace, repository, 'courts');
      addTearDown(c.close);
      addTearDown(workspace.close);
      c.addCourt();
      final id = c.state.selectedId!;
      court.priceCourt(c, id, '650');
      c.open(CourtSection.pricing, id: id);
      await host(
        tester,
        Scaffold(
          body: SingleChildScrollView(
            child: BlocBuilder<CourtSetupCubit, CourtSetupState>(
              bloc: c,
              builder: (_, s) => CourtPricingScreen(
                model: s.pricingModel,
                cubit: c,
                disabled: s.disabled,
              ),
            ),
          ),
        ),
      );
      final opening = find.byType(CourtHoursEditor).first;
      final sunday = find.descendant(of: opening, matching: find.text('Sun'));
      await tester.ensureVisible(sunday);
      await tester.tap(sunday);
      await tester.pumpAndSettle();
      final rule = find.byType(CourtHoursEditor).last;
      expect(
        find.descendant(of: rule, matching: find.text('Sun')),
        findsNothing,
      );
      expect(
        find.descendant(of: opening, matching: find.text('Sun')),
        findsOneWidget,
      );
      expect(
        c.state.draft.courts.single.tariffs.single.hours.days,
        isNot(contains(7)),
      );
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'empty court list shows only add action and no continue or save footer',
    (tester) async {
      final source = court.CourtSource(),
          workspace = WorkspaceCubit(court.CourtSource());
      await workspace.load();
      final repository = court.FakeCourtRepository(source);
      final c = CourtSetupCubit(workspace, repository, 'courts');
      c.open(CourtSection.courts);
      getIt.registerFactoryParam<CourtSetupCubit, WorkspaceCubit, String>(
        (_, _) => c,
      );
      await host(
        tester,
        BlocProvider.value(
          value: workspace,
          child: const CourtSetupScreen(businessId: 'courts'),
        ),
      );
      expect(find.text('Nothing added yet'), findsOneWidget);
      expect(find.text('Add court'), findsOneWidget);
      expect(find.text('Continue'), findsNothing);
      expect(find.text('Save changes'), findsNothing);
      expect(find.text('Reload saved settings'), findsNothing);
      await tester.tap(find.text('Add court'));
      await tester.pumpAndSettle();
      expect(find.text('Court name'), findsOneWidget);
      expect(find.text('Continue to timing & pricing'), findsOneWidget);
      expect(repository.writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await workspace.close();
    },
  );
}
