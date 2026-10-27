import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/court/models/court_configuration.dart';

CourtResource court({
  String id = 'c1',
  String name = 'Court 1',
  String environment = 'unspecified',
  String surface = '',
  bool enabled = true,
  String price = '500',
  CourtHours? hours,
  List<int> durations = const [60],
  int defaultDuration = 60,
  int before = 0,
  int after = 5,
  List<CourtTariff>? tariffs,
}) => CourtResource(
  id: id,
  name: name,
  environment: environment,
  surface: surface,
  enabled: enabled,
  hours: hours,
  durations: durations,
  defaultDuration: defaultDuration,
  before: before,
  after: after,
  tariffs:
      tariffs ??
      [
        CourtTariff(
          id: 't-$id',
          hours: hours ?? CourtHours(),
          rates: durations.map((d) => CourtRate(d, price)),
        ),
      ],
);

CourtPlan plan({
  String id = 'plan',
  String kind = 'coaching',
  String name = 'Junior',
  String allowance = '12',
  String seats = '8',
  String expiryMode = 'after_months',
  String days = '45',
  String months = '1',
  String years = '1',
  String? date,
  String price = '3000',
  bool track = true,
  bool enabled = true,
  int classDuration = 60,
  List<String> ids = const ['c1'],
}) => CourtPlan(
  id: id,
  kind: kind,
  name: name,
  allowance: allowance,
  seats: seats,
  expiryMode: expiryMode,
  expiryDays: days,
  expiryMonths: months,
  expiryYears: years,
  expiryDate: date,
  price: price,
  trackAttendance: track,
  enabled: enabled,
  classDuration: classDuration,
  courtIds: ids,
);

String? check(
  Iterable<CourtResource> courts, {
  Iterable<CourtPlan> plans = const [],
  bool complete = true,
  String? today,
}) => CourtConfiguration(
  courts: courts,
  plans: plans,
).validate(complete: complete, today: today);

void main() {
  test('baseline valid', () => expect(check([court()]), isNull));

  group('Court name and surface', () {
    test('name bounds, whitespace, unicode', () {
      for (final n in ['', ' ', 'a', '   a   ']) {
        expect(check([court(name: n)]), isNotNull, reason: '"$n"');
      }
      for (final n in ['ab', 'a' * 100, 'Terrain 🎾', '球场 1', ' Centre ']) {
        expect(check([court(name: n)]), isNull, reason: n);
      }
      expect(check([court(name: 'a' * 101)]), isNotNull);
    });
    test('surface optional, max 80 characters trimmed', () {
      expect(check([court(surface: '')]), isNull);
      expect(check([court(surface: ' ' * 200)]), isNull);
      expect(check([court(surface: 'a' * 80)]), isNull);
      expect(check([court(surface: 'a' * 81)]), isNotNull);
      expect(check([court(surface: 'Clay 🟤')]), isNull);
    });
    test('environment must be a known value', () {
      for (final e in ['indoor', 'outdoor', 'unspecified']) {
        expect(check([court(environment: e)]), isNull);
      }
      expect(check([court(environment: 'roof')]), isNotNull);
      expect(check([court(environment: '')]), isNotNull);
    });
    test('duplicate names rejected regardless of case/space/enabled', () {
      expect(
        check([court(id: 'a', name: 'Centre'), court(id: 'b', name: ' CENTRE ')]),
        'Use unique court names and identifiers.',
      );
      expect(
        check([
          court(id: 'a', name: 'Centre'),
          court(id: 'b', name: 'centre', enabled: false),
        ]),
        isNotNull,
      );
    });
    test('duplicate ids rejected', () {
      expect(
        check([court(id: 'a', name: 'One'), court(id: 'a', name: 'Two')]),
        isNotNull,
      );
    });
    test('limits: 51 courts rejected', () {
      final courts = [
        for (var i = 0; i < 51; i++) court(id: 'c$i', name: 'Court ${i + 10}'),
      ];
      expect(check(courts), 'Use at most 50 courts per business.');
    });
    test('none enabled when completing', () {
      expect(check([court(enabled: false)]), 'Enable at least one court.');
      expect(check([court(enabled: false)], complete: false), isNull);
    });
  });

  group('Court durations, buffers, hours', () {
    test('duration bounds and counts', () {
      expect(check([court(durations: [29], defaultDuration: 29)]), isNotNull);
      expect(check([court(durations: [30], defaultDuration: 30)]), isNull);
      expect(
        check([
          court(
            durations: [1441],
            defaultDuration: 1441,
            hours: CourtHours(opens: '00:00', closes: '00:00', allDay: true),
          ),
        ]),
        isNotNull,
      );
      final many = [for (var i = 0; i < 11; i++) 30 + i * 30];
      expect(
        check([court(durations: many, defaultDuration: 30)], complete: false),
        isNotNull,
        reason: 'more than 10 durations',
      );
    });
    test('negative / huge buffers', () {
      expect(check([court(before: -5)]), isNotNull);
      expect(check([court(after: 241)]), isNotNull);
      expect(check([court(before: 240, after: 240)]), isNull);
    });
    test('default duration must be allowed', () {
      expect(
        check([court(durations: [60], defaultDuration: 90)], complete: false),
        isNotNull,
      );
    });
    test('hours validation', () {
      expect(CourtHours(opens: '10:00', closes: '10:00').validate(), isNotNull);
      expect(CourtHours(days: []).validate(), isNotNull);
      expect(CourtHours(days: [1, 1]).validate(), isNotNull);
      expect(CourtHours(days: [8]).validate(), isNotNull);
      expect(CourtHours(opens: '25:00').validate(), isNotNull);
      expect(CourtHours(opens: '22:00', closes: '02:00').validate(), isNull);
      expect(CourtHours(opens: '22:00', closes: '02:00').span, 240);
      expect(
        CourtHours(dateFrom: '2030-03-01', dateUntil: '2030-02-01').validate(),
        isNotNull,
      );
      expect(
        CourtHours(dateFrom: '2030-02-29', dateUntil: '2030-03-01').validate(),
        isNotNull,
      );
    });
    test('duration cannot exceed the daily window', () {
      expect(
        check([
          court(
            hours: CourtHours(opens: '10:00', closes: '10:30'),
            durations: [60],
            defaultDuration: 60,
          ),
        ]),
        isNotNull,
      );
    });
  });

  group('Court prices', () {
    test('valid and invalid amounts', () {
      for (final ok in ['0', '1', '99.9', '99.99', ' 10 ', '1000000']) {
        expect(check([court(price: ok)]), isNull, reason: ok);
      }
      for (final bad in ['', '-1', '1.005', 'x', '٣', '💸', '1000000.01']) {
        expect(check([court(price: bad)]), isNotNull, reason: bad);
      }
    });
    test('blank price incomplete only', () {
      expect(check([court(price: '')], complete: false), isNull);
      expect(check([court(price: '')], complete: true), isNotNull);
    });
    test('disabled court with blank price may complete', () {
      expect(check([court(price: '', enabled: false), court(id: 'x', name: 'Other')]), isNull);
    });
    test('overlapping price rules and the 40 rule cap', () {
      CourtTariff t(String id, String a, String b, {List<int>? days}) =>
          CourtTariff(
            id: id,
            hours: CourtHours(opens: a, closes: b, days: days ?? [1, 2, 3, 4, 5, 6, 7]),
            rates: const [CourtRate(60, '1')],
          );
      expect(
        check([court(tariffs: [t('a', '06:00', '12:00'), t('b', '11:00', '14:00')])]),
        'Price rules overlap for Court 1.',
      );
      expect(
        check([
          court(tariffs: [
            t('a', '06:00', '12:00', days: [1]),
            t('b', '06:00', '12:00', days: [2]),
          ]),
        ]),
        isNull,
      );
      expect(
        check([
          court(tariffs: [for (var i = 0; i < 41; i++) t('t$i', '06:00', '07:00')]),
        ], complete: false),
        isNotNull,
      );
      expect(
        check([court(tariffs: [t('same', '06:00', '08:00'), t('same', '09:00', '10:00')])]),
        isNotNull,
        reason: 'duplicate tariff ids',
      );
    });
  });

  group('Court plans', () {
    String? run(CourtPlan p, {bool complete = true, String? today}) =>
        check([court()], plans: [p], complete: complete, today: today);

    test('valid coaching and play plans', () {
      expect(run(plan()), isNull);
      expect(run(plan(kind: 'play')), isNull);
    });
    test('name bounds', () {
      for (final n in ['', ' ', 'a', 'a' * 101]) {
        expect(run(plan(name: n)), isNotNull, reason: '"$n"');
      }
    });
    test('classes 1..10000', () {
      for (final v in ['', '0', '-1', '10001', '1.5', 'x', '٣']) {
        expect(run(plan(allowance: v)), isNotNull, reason: v);
      }
      expect(run(plan(allowance: '10000')), isNull);
    });
    test('seats 1..500 for coaching only', () {
      for (final v in ['', '0', '-1', '501', '2.5', 'x']) {
        expect(run(plan(seats: v)), isNotNull, reason: v);
      }
      expect(run(plan(seats: '500')), isNull);
      expect(run(plan(kind: 'play', seats: 'x')), isNull);
    });
    test('class duration 30..1440', () {
      expect(run(plan(classDuration: 29)), isNotNull);
      expect(run(plan(classDuration: 1441)), isNotNull);
    });
    test('attendance off ignores allowance and seats', () {
      expect(run(plan(track: false, allowance: '0', seats: '0')), isNull);
    });
    test('validity ceilings per unit', () {
      expect(run(plan(expiryMode: 'after_months', months: '120')), isNull);
      expect(run(plan(expiryMode: 'after_months', months: '121')), isNotNull);
      expect(run(plan(expiryMode: 'after_years', years: '11')), isNotNull);
      expect(run(plan(expiryMode: 'after_start', days: '3651')), isNotNull);
      for (final m in ['after_start', 'after_months', 'after_years']) {
        for (final bad in ['0', '-1', '', 'x', '1.5']) {
          expect(
            run(plan(expiryMode: m, days: bad, months: bad, years: bad)),
            isNotNull,
            reason: '$m $bad',
          );
        }
      }
    });
    test('fixed date: format, completeness, and past dates with `today`', () {
      expect(run(plan(expiryMode: 'fixed_date', date: '2031-01-01'), today: '2030-01-01'), isNull);
      expect(run(plan(expiryMode: 'fixed_date', date: '2031-02-31')), isNotNull);
      expect(run(plan(expiryMode: 'fixed_date', date: '1/1/2031')), isNotNull);
      expect(run(plan(expiryMode: 'fixed_date')), isNotNull);
      expect(run(plan(expiryMode: 'fixed_date'), complete: false), isNull);
      expect(run(plan(expiryMode: 'fixed_date', date: '2020-01-01'), today: '2030-01-01'), isNotNull);
      expect(run(plan(expiryMode: 'fixed_date', date: '2030-01-01'), today: '2030-01-01'), isNull,
          reason: 'expiry day itself is included');
    });
    test('price rules', () {
      for (final v in ['-1', '1.234', 'abc', '1000001']) {
        expect(run(plan(price: v), complete: false), isNotNull, reason: v);
      }
      expect(run(plan(price: ''), complete: false), isNull);
      expect(run(plan(price: '')), isNotNull);
      expect(run(plan(price: '0')), isNull);
    });
    test('unknown / duplicate court references', () {
      expect(run(plan(ids: const ['ghost'])), isNotNull);
      expect(run(plan(ids: const ['c1', 'c1'])), isNotNull);
      expect(run(plan(ids: const [])), isNotNull);
      expect(run(plan(ids: const []), complete: false), isNull);
    });
    test('plan on a disabled court rejected', () {
      expect(
        check([court(enabled: false)], plans: [plan()], complete: false),
        isNotNull,
      );
    });
    test('more than 50 plans', () {
      final plans = [for (var i = 0; i < 51; i++) plan(id: 'p$i', name: 'Plan $i')];
      expect(check([court()], plans: plans), 'Use at most 50 coaching plans.');
    });
    test('plan and court ids must not collide', () {
      expect(check([court(id: 'same')], plans: [plan(id: 'same', ids: const ['same'])]), isNotNull);
    });
    test('validity label reflects the draft', () {
      expect(plan(expiryMode: 'fixed_date').validityLabel, 'Expires not set');
      expect(plan(months: '3').validityLabel, '3 calendar months from activation');
    });
  });

  group('Court serialisation', () {
    test('server json trims text and stores minor units', () {
      final j = court(name: '  Centre  ', surface: ' Clay ', price: '19.99').toJson();
      expect(j['name'], 'Centre');
      expect(j['surface'], 'Clay');
      expect(j['tariffs'][0]['rates'][0]['price_minor'], 1999);
    });
    test('local draft preserves unparsed text', () {
      final cfg = CourtConfiguration(
        courts: [court(name: ' ')],
        plans: [plan(allowance: 'abc', seats: '', price: '1.234')],
      );
      final back = CourtConfiguration.fromJson(cfg.toJson(localDraft: true));
      expect(back.courts.first.name, ' ');
      expect(back.plans.first.allowance, 'abc');
      expect(back.plans.first.seats, '');
      expect(back.plans.first.price, '1.234');
    });
    test('plan json: unparseable numbers become null, not zero', () {
      final j = plan(allowance: 'x', price: 'y', seats: 'z').toJson();
      expect(j['allowance'], isNull);
      expect(j['price_minor'], isNull);
      expect(j['class_seats'], isNull);
    });
    test('removing a court strips references and the coach', () {
      final cfg = CourtConfiguration(
        courts: [court(id: 'c1'), court(id: 'c2', name: 'Two')],
        plans: [plan(ids: const ['c1']).copyWith(coachId: 'coach')],
      ).withoutCourt('c1');
      expect(cfg.plans.first.courtIds, isEmpty);
      expect(cfg.plans.first.coachId, isNull);
    });
  });
}
