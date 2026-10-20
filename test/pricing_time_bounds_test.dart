import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/utils/helpers/operating_window.dart';
import 'package:eden_booking/utils/helpers/pricing_time_bounds.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/court/cubit/court_setup_cubit.dart';
import 'package:eden_booking/modules/pool/cubit/pool_setup_cubit.dart';
import 'package:eden_booking/modules/turf/cubit/turf_setup_cubit.dart';
import 'package:eden_booking/modules/turf/models/turf_configuration.dart';
import 'package:eden_booking/modules/hall/cubit/hall_setup_cubit.dart';
import 'turf_setup_test.dart' as turf;
import 'court_setup_test.dart' as court;
import 'pool_setup_test.dart' as pool;
import 'hall_setup_test.dart' as hall;

OperatingWindow window(
  String start,
  String end, {
  bool allDay = false,
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
}) => OperatingWindow(days: days, opens: start, closes: end, allDay: allDay);
PricingTimeBounds bounds(
  List<OperatingWindow> parents, {
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
}) => PricingTimeBounds(parents, days);

Future<void> host(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(320, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp(
        theme: darkTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 800),
            textScaler: TextScaler.linear(1.6),
          ),
          child: Scaffold(body: SingleChildScrollView(child: child)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test(
    '06:00 to midnight defaults and bounds preserve exact minutes and reject outside or zero ranges',
    () {
      final b = bounds([window('06:00', '00:00')]);
      expect(
        (b.defaultRange!.opens, b.defaultRange!.closes, b.defaultRange!.allDay),
        ('06:00', '00:00', false),
      );
      expect(b.allows('06:00', '00:00'), isTrue);
      expect(b.allows('09:12', '18:17'), isTrue);
      for (final range in [
        ('05:59', '12:00'),
        ('23:00', '00:01'),
        ('00:00', '06:00'),
        ('12:00', '12:00'),
      ]) {
        expect(b.allows(range.$1, range.$2), isFalse);
      }
      expect(b.allows('00:00', '00:00', allDay: true), isFalse);
    },
  );
  test(
    'overnight limits and full-day next-day closure use operating weekday semantics',
    () {
      final overnight = bounds([window('20:00', '02:00')]);
      expect(overnight.allows('23:00', '01:00'), isTrue);
      expect(overnight.allows('01:00', '02:00'), isTrue);
      expect(overnight.allows('22:00', '03:00'), isFalse);
      expect(overnight.allows('19:00', '01:00'), isFalse);
      expect(
        bounds([
          window('00:00', '00:00', allDay: true),
        ]).allows('22:00', '02:00'),
        isTrue,
      );
      final monday = bounds(
        [
          window('00:00', '00:00', allDay: true, days: [1]),
        ],
        days: [1],
      );
      expect(monday.allows('22:00', '00:00'), isTrue);
      expect(monday.allows('22:00', '02:00'), isFalse);
    },
  );
  test(
    'eligible pool default range is their shared interval, including overnight and no-overlap cases',
    () {
      var b = bounds([window('08:00', '18:00'), window('10:00', '20:00')]);
      expect(
        (b.defaultRange!.opens, b.defaultRange!.closes),
        ('10:00', '18:00'),
      );
      expect(b.allows('09:00', '12:00'), isFalse);
      b = bounds([window('20:00', '02:00'), window('22:00', '03:00')]);
      expect(
        (b.defaultRange!.opens, b.defaultRange!.closes),
        ('22:00', '02:00'),
      );
      b = bounds([
        window('00:00', '00:00', allDay: true),
        window('20:00', '02:00'),
      ]);
      expect(
        (b.defaultRange!.opens, b.defaultRange!.closes),
        ('20:00', '02:00'),
      );
      expect(
        bounds([
          window('06:00', '10:00'),
          window('18:00', '22:00'),
        ]).defaultRange,
        isNull,
      );
    },
  );
  testWidgets(
    'price range dialog rejects outside values and only commits a valid midnight range',
    (tester) async {
      (String, String, bool)? saved;
      await host(
        tester,
        AppPricingTimeRange(
          opens: '06:00',
          closes: '00:00',
          bounds: bounds([window('06:00', '00:00')]),
          onChanged: (a, b, c) => saved = (a, b, c),
        ),
      );
      await tester.tap(find.text('06:00–24:00'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      expect(fields, findsNWidgets(4));
      expect(find.byType(SwitchListTile), findsNothing);
      await tester.enterText(fields.at(0), '05');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(
        find.textContaining('Choose a non-zero time range'),
        findsOneWidget,
      );
      await tester.enterText(fields.at(0), '06');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(saved, ('06:00', '00:00', false));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'overnight dialog accepts a contained range and opening-hours reset fixes a legacy invalid range',
    (tester) async {
      (String, String, bool)? saved;
      await host(
        tester,
        AppPricingTimeRange(
          opens: '20:00',
          closes: '02:00',
          bounds: bounds([window('20:00', '02:00')]),
          onChanged: (a, b, c) => saved = (a, b, c),
        ),
      );
      await tester.tap(find.text('20:00–02:00'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '23');
      await tester.enterText(fields.at(2), '03');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(fields.at(2), '01');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(saved, ('23:00', '01:00', false));
      saved = null;
      await host(
        tester,
        AppPricingTimeRange(
          opens: '00:00',
          closes: '00:00',
          allDay: true,
          bounds: bounds([window('06:00', '00:00')]),
          onChanged: (a, b, c) => saved = (a, b, c),
        ),
      );
      await tester.tap(find.text('Use opening hours'));
      await tester.pumpAndSettle();
      expect(saved, ('06:00', '00:00', false));
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'all-day price option is available only for an all-day opening schedule',
    (tester) async {
      (String, String, bool)? saved;
      await host(
        tester,
        AppPricingTimeRange(
          opens: '06:00',
          closes: '00:00',
          bounds: bounds([window('00:00', '00:00', allDay: true)]),
          onChanged: (a, b, c) => saved = (a, b, c),
        ),
      );
      await tester.tap(find.text('06:00–24:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(saved, ('00:00', '00:00', true));
      expect(tester.takeException(), isNull);
    },
  );
  test(
    'court full-opening rules follow changed hours but custom bands and amounts are retained',
    () async {
      final source = court.CourtSource(),
          w = WorkspaceCubit(court.CourtSource());
      await w.load();
      final repo = court.FakeCourtRepository(source);
      final c = CourtSetupCubit(w, repo, 'courts');
      addTearDown(c.close);
      addTearDown(w.close);
      c.addCourt();
      final id = c.state.selectedId!;
      court.priceCourt(c, id, '650');
      c.updateCourt(
        id,
        (p) => p.copyWith(hours: p.hours.copyWith(closes: '00:00')),
      );
      expect(c.state.draft.courts.single.tariffs.single.hours.closes, '00:00');
      c.addTariff(id);
      final custom = c.state.draft.courts.single.tariffs.last;
      c.tariffHours(
        id,
        custom.id,
        custom.hours.copyWith(opens: '09:00', closes: '12:00'),
      );
      c.updateCourt(
        id,
        (p) => p.copyWith(
          hours: p.hours.copyWith(opens: '08:00', closes: '22:00'),
        ),
      );
      final p = c.state.draft.courts.single;
      expect(
        (p.tariffs.first.hours.opens, p.tariffs.first.hours.closes),
        ('08:00', '22:00'),
      );
      expect(p.tariffs.first.rates.single.price, '650');
      expect(
        (p.tariffs.last.hours.opens, p.tariffs.last.hours.closes),
        ('09:00', '12:00'),
      );
      c.addTariff(id);
      expect(c.state.draft.courts.single.tariffs.last.hours, p.hours);
      expect(repo.writes, 0);
    },
  );
  test(
    'pool admissions offers and plans follow opening defaults and common eligible pool hours',
    () async {
      final source = pool.PoolSource(), w = WorkspaceCubit(pool.PoolSource());
      await w.load();
      final repo = pool.FakePoolRepository(source);
      final c = PoolSetupCubit(w, repo, 'pools');
      addTearDown(c.close);
      addTearDown(w.close);
      c.addPool();
      final a = c.state.selectedId!;
      c.addTariff(a);
      c.addOffer();
      c.addPlan(false);
      c.updatePool(
        a,
        (p) => p.copyWith(
          hours: p.hours.copyWith(opens: '08:00', closes: '20:00'),
        ),
      );
      expect(c.state.draft.pools.single.tariffs.single.hours.opens, '08:00');
      expect(c.state.draft.offers.single.hours.closes, '20:00');
      expect(c.state.draft.plans.single.hours.closes, '20:00');
      c.addPool();
      final b = c.state.selectedId!;
      c.updatePool(
        b,
        (p) => p.copyWith(
          hours: p.hours.copyWith(opens: '10:00', closes: '18:00'),
        ),
      );
      c.updateOffer(
        c.state.draft.offers.single.id,
        (o) => o.copyWith(poolIds: [a, b], price: '2500'),
      );
      final offer = c.state.draft.offers.single;
      expect((offer.hours.opens, offer.hours.closes), ('10:00', '18:00'));
      expect(offer.price, '2500');
      expect(repo.writes, 0);
    },
  );
  test(
    'turf full-opening rules follow offering hours and linked Cricket retains the same amount',
    () async {
      final source = turf.TurfSource(), w = WorkspaceCubit(turf.TurfSource());
      await w.load();
      final repo = turf.FakeTurfRepository(source);
      final c = TurfSetupCubit(w, repo, 'turf');
      addTearDown(c.close);
      addTearDown(w.close);
      for (final o
          in c.state.draft.offerings
              .where((o) => o.sport == TurfSport.football)
              .toList()) {
        c.price(o.id, 60, '600');
      }
      c.useFootballForCricket(true);
      final target = c.state.draft.offerings.first;
      c.offeringHours(
        target.id,
        c.state.draft.operating.copyWith(closes: '00:00'),
      );
      for (final o in c.state.draft.offerings.where(
        (o) => o.layoutId == target.layoutId,
      )) {
        expect(o.pricingRules.single.closes, '00:00');
        expect(o.pricingRules.single.rates.single.price, '600');
      }
      expect(repo.writes, 0);
    },
  );
  test(
    'hall hourly and full-opening package times follow changed hall hours',
    () async {
      final source = hall.HallSource(), w = WorkspaceCubit(hall.HallSource());
      await w.load();
      final repo = hall.FakeHallRepository(source);
      final c = HallSetupCubit(w, repo, 'halls');
      addTearDown(c.close);
      addTearDown(w.close);
      c.addHall();
      final id = c.state.selectedId!;
      c.addTariff(id);
      final initial = c.state.draft.halls.single;
      c.updatePackage(
        id,
        initial.fullDay.id,
        (o) => o.copyWith(hours: initial.hours),
      );
      c.updateHall(
        id,
        (p) => p.copyWith(
          hours: p.hours.copyWith(opens: '08:00', closes: '20:00'),
        ),
      );
      final p = c.state.draft.halls.single;
      expect(
        (p.tariffs.single.hours.opens, p.tariffs.single.hours.closes),
        ('08:00', '20:00'),
      );
      expect(
        (p.fullDay.hours.opens, p.fullDay.hours.closes),
        ('08:00', '20:00'),
      );
      expect(
        (p.sessions.first.hours.opens, p.sessions.first.hours.closes),
        ('09:00', '13:00'),
      );
      expect(repo.writes, 0);
    },
  );
}
