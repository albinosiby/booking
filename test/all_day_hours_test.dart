import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/turf/cubit/turf_setup_cubit.dart';
import 'turf_setup_test.dart' show TurfSource, FakeTurfRepository;
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/turf/models/turf_configuration.dart';
import 'package:eden_booking/modules/turf/widgets/turf_hours_editor.dart';
import 'package:eden_booking/modules/court/models/court_configuration.dart';
import 'package:eden_booking/modules/court/widgets/court_editors.dart';
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/pool/widgets/pool_editors.dart';

void main() {
  test(
    'full-day schedules have 1440 minutes, round trip explicitly and retain legacy validation',
    () {
      final turf = TurfHours(allDay: true, opens: '00:00', closes: '00:00');
      final court = CourtHours(allDay: true, opens: '00:00', closes: '00:00');
      final pool = PoolHours(allDay: true, opens: '00:00', closes: '00:00');
      expect(TurfHours.fromJson(turf.toJson()), turf);
      expect(CourtHours.fromJson(court.toJson()), court);
      expect(PoolHours.fromJson(pool.toJson()), pool);
      expect(turf.spanMinutes, 1440);
      expect(court.span, 1440);
      expect(pool.span, 1440);
      expect(court.validate(), isNull);
      expect(pool.validate(), isNull);
      expect(turf.validTimes, isTrue);
      expect(TurfHours(opens: '00:00', closes: '00:00').validTimes, isFalse);
      expect(CourtHours(opens: '00:00', closes: '00:00').validate(), isNotNull);
      expect(PoolHours(opens: '00:00', closes: '00:00').validate(), isNotNull);
      expect(TurfHours().toJson().containsKey('all_day'), isFalse);
      expect(CourtHours().toJson().containsKey('all_day'), isFalse);
      expect(PoolHours().toJson().containsKey('all_day'), isFalse);
      expect(CourtHours(days: [1]).within(court.copyWith(days: [2])), isFalse);
      expect(CourtHours().within(court), isTrue);
      expect(PoolHours().within(pool), isTrue);
      expect(
        turf
            .copyWith(allDay: false, opens: '06:00', closes: '23:00')
            .spanMinutes,
        1020,
      );
    },
  );
  test(
    'full-day containment and overlap include the following weekday and seasonal date',
    () {
      final parent = CourtHours(
        allDay: true,
        opens: '00:00',
        closes: '00:00',
        days: [1, 2],
      );
      final night = CourtHours(
        days: [1],
        opens: '22:00',
        closes: '02:00',
        dateFrom: '2030-06-03',
        dateUntil: '2030-06-03',
      );
      final morning = CourtHours(
        days: [2],
        opens: '01:00',
        closes: '03:00',
        dateFrom: '2030-06-04',
        dateUntil: '2030-06-04',
      );
      expect(night.within(parent), isTrue);
      expect(night.within(parent.copyWith(days: [1])), isFalse);
      expect(night.window.overlaps(morning.window), isTrue);
      expect(
        night.window.overlaps(morning.copyWith(opens: '02:00').window),
        isFalse,
      );
      final court = CourtResource(
        id: 'court',
        name: 'Court 1',
        hours: parent,
        tariffs: [
          CourtTariff(
            id: 'night',
            hours: night,
            rates: [const CourtRate(60, '500')],
          ),
          CourtTariff(
            id: 'morning',
            hours: morning,
            rates: [const CourtRate(60, '600')],
          ),
        ],
      );
      expect(
        CourtConfiguration(courts: [court]).validate(),
        contains('overlap'),
      );
    },
  );
  test(
    '24-hour turf mode preserves other overnight spaces and persists full-day price rules',
    () async {
      final source = TurfSource();
      final session = WorkspaceCubit(source);
      await session.load();
      final c = TurfSetupCubit(session, FakeTurfRepository(source), 'turf');
      addTearDown(c.close);
      addTearDown(session.close);
      c.hours(TurfHours(opens: '18:00', closes: '02:00', days: [1]));
      final first = c.state.draft.offerings.first;
      c.offeringHours(
        first.id,
        TurfHours(allDay: true, opens: '00:00', closes: '00:00', days: [1]),
      );
      expect(c.state.draft.operating.allDay, isTrue);
      expect(c.state.draft.operating.days, containsAll([1, 2]));
      for (final other in c.state.draft.offerings.skip(1)) {
        expect(other.hoursOverride!.opens, '18:00');
        expect(other.hoursOverride!.closes, '02:00');
        expect(other.hoursOverride!.days, [1]);
      }
      c.price(first.id, 60, '600');
      expect(c.state.draft.offerings.first.pricingRules.single.allDay, isTrue);
      expect(c.state.draft.validate(), isNull);
      expect(await c.saveProgress(), isTrue);
      final restored = TurfConfiguration.fromJson(source.configuration!);
      expect(restored.offerings.first.hoursOverride!.allDay, isTrue);
      expect(restored.offerings.first.pricingRules.single.allDay, isTrue);
    },
  );
  for (final kind in ['turf', 'court', 'pool']) {
    testWidgets('$kind hides time fields in full-day mode at 320px', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var turf = TurfHours(), court = CourtHours(), pool = PoolHours();
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => MaterialApp(
            theme: darkTheme(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setState) => switch (kind) {
                      'court' => CourtHoursEditor(
                        hours: court,
                        onChanged: (v) => setState(() => court = v),
                      ),
                      'pool' => PoolHoursEditor(
                        hours: pool,
                        onChanged: (v) => setState(() => pool = v),
                      ),
                      _ => TurfHoursEditor(
                        hours: turf,
                        onChanged: (v) => setState(() => turf = v),
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mode = find.text('Open 24 hours');
      await tester.ensureVisible(mode);
      await tester.tap(mode);
      await tester.pumpAndSettle();
      expect(find.textContaining('Start time ·'), findsNothing);
      expect(find.textContaining('End time ·'), findsNothing);
      expect(find.textContaining('Opens ·'), findsNothing);
      expect(find.textContaining('Closes ·'), findsNothing);
      expect(switch (kind) {
        'court' => court.allDay,
        'pool' => pool.allDay,
        _ => turf.allDay,
      }, isTrue);
      expect(tester.takeException(), isNull);
      final custom = find.text('Set opening & closing times');
      await tester.ensureVisible(custom);
      await tester.tap(custom);
      await tester.pumpAndSettle();
      expect(switch (kind) {
        'court' => court.allDay,
        'pool' => pool.allDay,
        _ => turf.allDay,
      }, isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
