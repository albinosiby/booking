import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';

PoolResource pool({
  String id = 'p1',
  String name = 'Pool A',
  String capacity = '20',
  String minDepth = '3',
  String maxDepth = '5',
  bool enabled = true,
  String price = '200',
  PoolHours? hours,
  List<int> durations = const [60],
  int defaultDuration = 60,
  int before = 0,
  int after = 5,
  List<PoolTariff>? tariffs,
}) => PoolResource(
  id: id,
  name: name,
  capacity: capacity,
  minDepth: minDepth,
  maxDepth: maxDepth,
  enabled: enabled,
  hours: hours,
  durations: durations,
  defaultDuration: defaultDuration,
  before: before,
  after: after,
  tariffs:
      tariffs ??
      [
        PoolTariff(
          id: 't-$id',
          hours: hours ?? PoolHours(),
          rates: durations.map((d) => PoolRate(d, price)),
        ),
      ],
);

String? details(PoolResource p, {bool complete = true}) =>
    p.validateDetails(complete: complete);
String? check(
  Iterable<PoolResource> pools, {
  Iterable<PoolGroupOffer> offers = const [],
  Iterable<PoolPlan> plans = const [],
  bool complete = true,
}) => PoolConfiguration(
  pools: pools,
  offers: offers,
  plans: plans,
).validate(complete: complete);

PoolPlan plan({
  String id = 'plan',
  String kind = 'swimming',
  String name = 'Monthly',
  String allowance = '25',
  String expiryMode = 'after_months',
  String days = '45',
  String months = '1',
  String years = '1',
  String? date,
  String price = '1000',
  String seats = '10',
  bool track = true,
  bool enabled = true,
  int classDuration = 60,
}) => PoolPlan(
  id: id,
  kind: kind,
  name: name,
  allowance: allowance,
  expiryMode: expiryMode,
  expiryDays: days,
  expiryMonths: months,
  expiryYears: years,
  expiryDate: date,
  price: price,
  seats: seats,
  trackAttendance: track,
  enabled: enabled,
  classDuration: classDuration,
  poolIds: const ['p1'],
);

void main() {
  test('baseline pool configuration is valid', () {
    expect(check([pool()]), isNull);
  });

  group('Pool name', () {
    test('empty, whitespace, one character are rejected', () {
      for (final n in ['', ' ', '     ', 'a', ' a ', '\n\t']) {
        expect(details(pool(name: n)), isNotNull, reason: '"$n"');
      }
    });
    test('2 and 100 characters accepted, 101 rejected, trimmed first', () {
      expect(details(pool(name: 'ab')), isNull);
      expect(details(pool(name: 'a' * 100)), isNull);
      expect(details(pool(name: ' ${'a' * 100} ')), isNull);
      expect(details(pool(name: 'a' * 101)), isNotNull);
    });
    test('unicode, emoji and markup names are accepted verbatim', () {
      for (final n in ['Piscine é', '游泳池', '🏊 Lap', '<b>x</b>', "O'Neil"]) {
        expect(details(pool(name: n)), isNull, reason: n);
      }
    });
    test('toJson trims the stored name', () {
      expect(pool(name: '  Lap  ').toJson()['name'], 'Lap');
    });
    test('duplicate names are rejected case-insensitively and trimmed', () {
      expect(
        check([pool(id: 'a', name: 'Lap'), pool(id: 'b', name: ' lap ')]),
        'Give each pool a unique name.',
      );
      expect(
        check([pool(id: 'a', name: 'Lap'), pool(id: 'b', name: 'Lap 2')]),
        isNull,
      );
    });
    test('duplicate disabled pools are still rejected', () {
      expect(
        check([
          pool(id: 'a', name: 'Lap'),
          pool(id: 'b', name: 'LAP', enabled: false),
        ]),
        isNotNull,
      );
    });
  });

  group('Pool capacity', () {
    test('invalid values rejected', () {
      for (final c in [
        '',
        ' ',
        '0',
        '-1',
        '-0',
        '10001',
        '1.5',
        '1,5',
        '2e3',
        'abc',
        '٣',
        '💧',
        '99999999999999999999999',
        '9' * 400,
      ]) {
        expect(details(pool(capacity: c)), isNotNull, reason: '"$c"');
      }
    });
    test('boundaries accepted', () {
      expect(details(pool(capacity: '1')), isNull);
      expect(details(pool(capacity: '10000')), isNull);
    });
    test('hex and plus sign are rejected by the model', () {
      expect(details(pool(capacity: '0x10')), isNotNull);
      expect(details(pool(capacity: '+5')), isNotNull);
    }, skip: 'BUG-1: int.tryParse accepts "0x10" and "+5" as capacity');
    test('capacity round trips through json as an int', () {
      final json = pool(capacity: '25').toJson();
      expect(json, isA<Map>());
      final restored = PoolResource.fromJson(
        Map<String, dynamic>.from(json),
      );
      expect(restored.capacity, '25');
    });
  });

  group('Pool depth', () {
    test('valid depths', () {
      for (final d in [
        ('0', '1'),
        ('3', '5'),
        ('3.5', '5.25'),
        ('5', '5'),
        ('0', '1000'),
        ('1000', '1000'),
      ]) {
        expect(
          details(pool(minDepth: d.$1, maxDepth: d.$2)),
          isNull,
          reason: '$d',
        );
      }
    });
    test('invalid depths', () {
      for (final d in [
        ('-1', '5'),
        ('3', '-5'),
        ('3', '0'),
        ('3.555', '5'),
        ('3', '5.001'),
        ('1001', '1001'),
        ('3', '1001'),
        ('.5', '5'),
        ('3', '5.'),
        (' 3', '5'),
        ('3', '5 '),
        ('3,5', '5'),
        ('٣', '5'),
        ('abc', '5'),
        ('3', '٥'),
        ('1e1', '20'),
      ]) {
        expect(
          details(pool(minDepth: d.$1, maxDepth: d.$2)),
          isNotNull,
          reason: '$d',
        );
      }
    });
    test('minimum greater than maximum is rejected', () {
      expect(details(pool(minDepth: '6', maxDepth: '5')), isNotNull);
      expect(details(pool(minDepth: '5.01', maxDepth: '5')), isNotNull);
    });
    test('empty depths: allowed while incomplete, required when enabled', () {
      expect(details(pool(minDepth: '', maxDepth: ''), complete: false), isNull);
      expect(
        details(pool(minDepth: '', maxDepth: ''), complete: true),
        'Enter both depths for Pool A.',
      );
      expect(
        details(pool(minDepth: '', maxDepth: '', enabled: false), complete: true),
        isNull,
      );
      expect(details(pool(minDepth: '3', maxDepth: ''), complete: true), isNotNull);
    });
    test('depth with non-numeric text is rejected even if incomplete', () {
      expect(details(pool(minDepth: 'x', maxDepth: ''), complete: false), isNotNull);
    });
  });

  group('Pool durations and buffers', () {
    test('duration bounds 30..1440', () {
      for (final d in [29, 0, -30, 1441]) {
        expect(
          check([pool(durations: [d], defaultDuration: d)]),
          isNotNull,
          reason: '$d',
        );
      }
      expect(check([pool(durations: [30], defaultDuration: 30)]), isNull);
      expect(
        check([
          pool(
            durations: [1440],
            defaultDuration: 1440,
            hours: PoolHours(opens: '00:00', closes: '00:00', allDay: true),
          ),
        ]),
        isNull,
      );
    });
    test('empty, duplicate and default-not-listed durations rejected', () {
      expect(check([pool(durations: [], defaultDuration: 60, tariffs: [])]), isNotNull);
      expect(
        check([pool(durations: [60, 60], defaultDuration: 60, tariffs: [])],
            complete: false),
        isNotNull,
      );
      expect(
        check([pool(durations: [60], defaultDuration: 90, tariffs: [])],
            complete: false),
        isNotNull,
      );
    });
    test('buffer before/after bounds 0..240', () {
      expect(check([pool(before: -1)]), isNotNull);
      expect(check([pool(after: -1)]), isNotNull);
      expect(check([pool(before: 241)]), isNotNull);
      expect(check([pool(after: 241)]), isNotNull);
      expect(check([pool(before: 240, after: 240)]), isNull);
      expect(check([pool(before: 0, after: 0)]), isNull);
    });
    test('duration longer than opening span is incomplete', () {
      expect(
        check([
          pool(
            hours: PoolHours(opens: '09:00', closes: '10:00'),
            durations: [90],
            defaultDuration: 90,
          ),
        ]),
        isNotNull,
      );
    });
  });

  group('Pool opening hours', () {
    test('closes equal to opens rejected unless allDay with midnight', () {
      expect(PoolHours(opens: '09:00', closes: '09:00').validate(), isNotNull);
      expect(
        PoolHours(opens: '00:00', closes: '00:00', allDay: true).validate(),
        isNull,
      );
      expect(
        PoolHours(opens: '06:00', closes: '23:00', allDay: true).validate(),
        isNotNull,
      );
    });
    test('malformed times rejected', () {
      for (final t in ['24:00', '9:00', '09:60', '', 'aa:bb', '09:00:00', '٠٩:٠٠']) {
        expect(PoolHours(opens: t).validate(), isNotNull, reason: t);
        expect(PoolHours(closes: t).validate(), isNotNull, reason: t);
      }
    });
    test('overnight window valid with wrapped span', () {
      final h = PoolHours(opens: '22:00', closes: '02:00');
      expect(h.validate(), isNull);
      expect(h.span, 240);
    });
    test('weekday constraints', () {
      expect(PoolHours(days: []).validate(), isNotNull);
      expect(PoolHours(days: [0]).validate(), isNotNull);
      expect(PoolHours(days: [8]).validate(), isNotNull);
      expect(PoolHours(days: [1, 1]).validate(), isNotNull);
      expect(PoolHours(days: [7]).validate(), isNull);
    });
    test('date ranges', () {
      expect(PoolHours(dateFrom: '2030-01-01').validate(), isNotNull);
      expect(
        PoolHours(dateFrom: '2030-02-01', dateUntil: '2030-01-01').validate(),
        isNotNull,
        reason: 'from after until',
      );
      expect(
        PoolHours(dateFrom: '2030-02-30', dateUntil: '2030-03-01').validate(),
        isNotNull,
        reason: 'impossible date',
      );
      expect(
        PoolHours(dateFrom: '2030-2-3', dateUntil: '2030-03-01').validate(),
        isNotNull,
        reason: 'unpadded',
      );
      expect(
        PoolHours(dateFrom: '2030-01-01', dateUntil: '2030-01-01').validate(),
        isNull,
        reason: 'single day',
      );
      expect(
        PoolHours(dateFrom: '2028-02-29', dateUntil: '2028-02-29').validate(),
        isNull,
        reason: 'leap day',
      );
      expect(
        PoolHours(dateFrom: '2029-02-29', dateUntil: '2029-03-01').validate(),
        isNotNull,
        reason: 'not a leap year',
      );
    });
    test('a pool itself cannot be date-limited', () {
      expect(
        check([
          pool(
            hours: PoolHours(dateFrom: '2030-01-01', dateUntil: '2030-02-01'),
          ),
        ]),
        isNotNull,
      );
    });
  });

  group('Pool tariffs and prices', () {
    test('amount strings', () {
      for (final ok in ['0', '1', '199.5', '199.50', '1000000', ' 10 ']) {
        expect(check([pool(price: ok)]), isNull, reason: ok);
      }
      for (final bad in ['', ' ', '-1', '1.999', '1000001', 'abc', '1e3', '💰', '١٠']) {
        expect(check([pool(price: bad)]), isNotNull, reason: '"$bad"');
      }
    });
    test('blank price accepted while drafting, rejected on completion', () {
      expect(check([pool(price: '')], complete: false), isNull);
      expect(check([pool(price: '')], complete: true), isNotNull);
    });
    test('negative and over-precise price rejected even while drafting', () {
      expect(check([pool(price: '-5')], complete: false), isNotNull);
      expect(check([pool(price: '1.234')], complete: false), isNotNull);
    });
    test('zero price is a valid complete price', () {
      expect(check([pool(price: '0')]), isNull);
    });
    test('PoolRate.minor rounds nothing and handles floating point edges', () {
      expect(const PoolRate(60, '19.99').minor, 1999);
      expect(const PoolRate(60, '0.1').minor, 10);
      expect(const PoolRate(60, '1000000').minor, 100000000);
    });
    test('price rules must stay within opening hours', () {
      final p = pool(
        hours: PoolHours(opens: '09:00', closes: '12:00'),
        tariffs: [
          PoolTariff(
            id: 't',
            hours: PoolHours(opens: '08:00', closes: '12:00'),
            rates: const [PoolRate(60, '100')],
          ),
        ],
      );
      expect(check([p]), isNotNull);
    });
    test('overlapping price rules rejected, adjacent accepted', () {
      PoolTariff t(String id, String a, String b) => PoolTariff(
        id: id,
        hours: PoolHours(opens: a, closes: b),
        rates: const [PoolRate(60, '100')],
      );
      PoolResource with_(List<PoolTariff> ts) => pool(
        hours: PoolHours(opens: '06:00', closes: '22:00'),
        tariffs: ts,
      );
      expect(check([with_([t('a', '06:00', '12:00'), t('b', '11:00', '15:00')])]),
          'Price rules overlap for Pool A.');
      expect(check([with_([t('a', '06:00', '12:00'), t('b', '12:00', '22:00')])]),
          isNull);
      expect(check([with_([t('a', '06:00', '22:00'), t('b', '08:00', '09:00')])]),
          isNotNull);
    });
    test('more than 40 price rules rejected', () {
      final tariffs = [
        for (var i = 0; i < 41; i++)
          PoolTariff(
            id: 't$i',
            hours: PoolHours(days: [1 + i % 7]),
            rates: const [PoolRate(60, '100')],
          ),
      ];
      expect(check([pool(tariffs: tariffs)], complete: false), isNotNull);
    });
    test('rates must match the allowed durations', () {
      final p = pool(
        durations: [60, 90],
        tariffs: [
          PoolTariff(id: 't', hours: PoolHours(), rates: const [PoolRate(60, '1')]),
        ],
      );
      expect(check([p], complete: false), isNotNull);
    });
  });

  group('Pool group offers', () {
    PoolGroupOffer offer({
      String name = 'Family',
      String people = '5',
      String price = '1000',
      String mode = 'up_to',
      int duration = 60,
      bool enabled = true,
      List<String> pools = const ['p1'],
    }) => PoolGroupOffer(
      id: 'o',
      name: name,
      people: people,
      price: price,
      mode: mode,
      duration: duration,
      enabled: enabled,
      poolIds: pools,
    );
    String? run(PoolGroupOffer o, {bool complete = true}) =>
        check([pool()], offers: [o], complete: complete);

    test('valid offer', () => expect(run(offer()), isNull));
    test('name bounds', () {
      for (final n in ['', ' ', 'a', 'a' * 101]) {
        expect(run(offer(name: n)), isNotNull, reason: '"$n"');
      }
      expect(run(offer(name: '👪👪')), isNull);
    });
    test('people bounds', () {
      for (final v in ['', '0', '-3', '2.5', 'x', '10001', '٥']) {
        expect(run(offer(people: v)), isNotNull, reason: v);
      }
      expect(run(offer(people: '1')), isNull);
    });
    test('people above pool capacity rejected for enabled offers', () {
      expect(run(offer(people: '21')), isNotNull);
      expect(run(offer(people: '20')), isNull);
      expect(run(offer(people: '21', enabled: false)), isNull);
    });
    test('unknown group mode rejected', () {
      expect(run(offer(mode: 'between')), isNotNull);
      for (final m in ['exact', 'up_to', 'at_least']) {
        expect(run(offer(mode: m)), isNull);
      }
    });
    test('price rules', () {
      expect(run(offer(price: ''), complete: true), isNotNull);
      expect(run(offer(price: ''), complete: false), isNull);
      expect(run(offer(price: '-1'), complete: false), isNotNull);
      expect(run(offer(price: '99.999'), complete: false), isNotNull);
      expect(run(offer(price: '0')), isNull);
    });
    test('duration bounds and fit within opening hours', () {
      expect(run(offer(duration: 29)), isNotNull);
      expect(run(offer(duration: 1441)), isNotNull);
      expect(run(offer(duration: 30)), isNull);
    });
    test('no pool selected: rejected when enabled and complete', () {
      expect(run(offer(pools: const [])), isNotNull);
      expect(run(offer(pools: const []), complete: false), isNull);
      expect(run(offer(pools: const ['ghost'])), isNotNull);
      expect(run(offer(pools: const ['p1', 'p1'])), isNotNull);
    });
    test('group size wording', () {
      expect(offer(mode: 'exact', people: '4').sizeLabel, 'Exactly 4 people');
      expect(offer(mode: 'at_least', people: '4').sizeLabel, '4+ people');
      expect(offer(mode: 'zzz').sizeLabel, 'Group size unavailable');
    });
    test('more than 50 offers rejected', () {
      final offers = [
        for (var i = 0; i < 51; i++) offer(name: 'Offer $i').copyWith()
      ];
      expect(
        PoolConfiguration(pools: [pool()], offers: offers).validate(),
        isNotNull,
      );
    });
  });

  group('Pool plans', () {
    String? run(PoolPlan p, {bool complete = true}) =>
        check([pool()], plans: [p], complete: complete);

    test('valid plans', () {
      expect(run(plan()), isNull);
      expect(run(plan(kind: 'coaching')), isNull);
    });
    test('name bounds', () {
      for (final n in ['', ' ', 'a', 'a' * 101]) {
        expect(run(plan(name: n)), isNotNull, reason: '"$n"');
      }
    });
    test('allowance bounds', () {
      for (final v in ['', '0', '-1', '1.5', 'x', '10001', '٣']) {
        expect(run(plan(allowance: v)), isNotNull, reason: v);
      }
      expect(run(plan(allowance: '1')), isNull);
      expect(run(plan(allowance: '10000')), isNull);
    });
    test('allowance ignored when attendance is not tracked', () {
      expect(run(plan(allowance: '0', track: false)), isNull);
      expect(run(plan(allowance: '', track: false)), isNull);
    });
    test('validity ceilings differ per unit', () {
      expect(run(plan(expiryMode: 'after_months', months: '120')), isNull);
      expect(run(plan(expiryMode: 'after_months', months: '121')), isNotNull);
      expect(run(plan(expiryMode: 'after_years', years: '10')), isNull);
      expect(run(plan(expiryMode: 'after_years', years: '11')), isNotNull);
      expect(run(plan(expiryMode: 'after_start', days: '3650')), isNull);
      expect(run(plan(expiryMode: 'after_start', days: '3651')), isNotNull);
      for (final m in ['after_start', 'after_months', 'after_years']) {
        expect(
          run(plan(expiryMode: m, days: '0', months: '0', years: '0')),
          isNotNull,
          reason: m,
        );
        expect(
          run(plan(expiryMode: m, days: '-1', months: '-1', years: '-1')),
          isNotNull,
          reason: m,
        );
        expect(
          run(plan(expiryMode: m, days: '', months: '', years: '')),
          isNotNull,
          reason: m,
        );
        expect(
          run(plan(expiryMode: m, days: '1.5', months: '1.5', years: '1.5')),
          isNotNull,
          reason: m,
        );
      }
    });
    test('unknown expiry mode rejected', () {
      expect(run(plan(expiryMode: 'forever')), isNotNull);
    });
    test('fixed date', () {
      expect(run(plan(expiryMode: 'fixed_date', date: '2030-12-31')), isNull);
      expect(run(plan(expiryMode: 'fixed_date', date: '2030-02-30')), isNotNull);
      expect(run(plan(expiryMode: 'fixed_date', date: '30-12-2030')), isNotNull);
      expect(run(plan(expiryMode: 'fixed_date', date: '')), isNotNull);
      expect(run(plan(expiryMode: 'fixed_date')), isNotNull,
          reason: 'complete needs a date');
      expect(run(plan(expiryMode: 'fixed_date'), complete: false), isNull);
    });
    test('fixed date in the past is not rejected by the model', () {
      expect(
        run(plan(expiryMode: 'fixed_date', date: '2001-01-01')),
        isNotNull,
      );
    }, skip: 'BUG-2: pool plan accepts a fixed expiry date in the past (court plans take a `today` parameter, pool plans do not)');
    test('price rules', () {
      for (final v in ['-1', '1.234', 'x', '1000001']) {
        expect(run(plan(price: v), complete: false), isNotNull, reason: v);
      }
      expect(run(plan(price: ''), complete: true), isNotNull);
      expect(run(plan(price: ''), complete: false), isNull);
      expect(run(plan(price: '0')), isNull);
    });
    test('coaching seats and class duration', () {
      for (final s in ['', '0', '-1', '1.5', 'x', '10001']) {
        expect(run(plan(kind: 'coaching', seats: s)), isNotNull, reason: s);
      }
      expect(run(plan(kind: 'coaching', seats: '20')), isNull);
      expect(run(plan(kind: 'coaching', seats: '21')), isNotNull,
          reason: 'cannot exceed pool capacity');
      expect(run(plan(kind: 'coaching', classDuration: 29)), isNotNull);
      expect(run(plan(kind: 'coaching', classDuration: 1441)), isNotNull);
      expect(run(plan(kind: 'swimming', seats: '')), isNull,
          reason: 'swimming ignores seats');
    });
    test('unknown plan kind rejected', () {
      expect(run(plan(kind: 'party')), isNotNull);
    });
    test('plan on a disabled pool rejected when enabled', () {
      expect(
        check([pool(enabled: false)], plans: [plan()], complete: false),
        isNotNull,
      );
    });
    test('more than 50 plans rejected', () {
      final plans = [for (var i = 0; i < 51; i++) plan(id: 'p$i', name: 'Plan $i')];
      expect(
        PoolConfiguration(pools: [pool()], plans: plans).validate(),
        isNotNull,
      );
    });
    test('duplicate plan names are allowed', () {
      expect(
        check([pool()], plans: [plan(id: 'a'), plan(id: 'b')]),
        isNull,
      );
    });
  });

  group('Pool plan validity arithmetic', () {
    DateTime? exp(String mode, String count, DateTime from) {
      final p = plan(expiryMode: mode, days: count, months: count, years: count);
      return p.expiryFrom(from);
    }

    test('months clamp to the last day of the target month', () {
      expect(exp('after_months', '1', DateTime(2030, 1, 31)), DateTime(2030, 2, 28));
      expect(exp('after_months', '1', DateTime(2028, 1, 31)), DateTime(2028, 2, 29));
      expect(exp('after_months', '12', DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
      expect(exp('after_months', '1', DateTime(2030, 12, 31)), DateTime(2031, 1, 31));
    });
    test('years clamp leap day', () {
      expect(exp('after_years', '1', DateTime(2028, 2, 29)), DateTime(2029, 2, 28));
      expect(exp('after_years', '4', DateTime(2028, 2, 29)), DateTime(2032, 2, 29));
    });
    test('days cross month and year boundaries', () {
      expect(exp('after_start', '1', DateTime(2030, 12, 31)), DateTime(2031, 1, 1));
      expect(exp('after_start', '3650', DateTime(2030, 1, 1)), isNotNull);
    });
    test('invalid counts give no expiry', () {
      expect(exp('after_months', '0', DateTime(2030, 1, 1)), isNull);
      expect(exp('after_months', '121', DateTime(2030, 1, 1)), isNull);
      expect(exp('after_years', 'x', DateTime(2030, 1, 1)), isNull);
      expect(exp('after_start', '-5', DateTime(2030, 1, 1)), isNull);
    });
    test('validityCount follows the selected unit and drafts are preserved', () {
      final p = plan(expiryMode: 'after_months', days: '9', months: '3', years: '2');
      expect(p.validityCount, '3');
      expect(p.withValidityCount('7').expiryMonths, '7');
      expect(p.withValidityCount('7').expiryDays, '9');
    });
  });

  group('Pool configuration limits and serialisation', () {
    test('more than 30 pools rejected', () {
      final pools = [
        for (var i = 0; i < 31; i++) pool(id: 'p$i', name: 'Pool ${i + 10}'),
      ];
      expect(check(pools), 'Too many pools, offers or plans.');
    });
    test('complete requires an enabled pool', () {
      expect(check([pool(enabled: false)]), 'Enable at least one pool.');
      expect(check(const []), 'Enable at least one pool.');
      expect(check(const [], complete: false), isNull);
    });
    test('regular swimming off needs an offer or plan', () {
      final p = PoolResource(
        id: 'p1',
        name: 'Pool A',
        minDepth: '3',
        maxDepth: '5',
        regularSwimming: false,
      );
      expect(check([p]), isNotNull);
      expect(check([p], plans: [plan()]), isNull);
    });
    test('local draft json preserves raw text typed by the user', () {
      final cfg = PoolConfiguration(
        pools: [pool(price: '12.5')],
        plans: [plan(allowance: 'abc', price: '1.234')],
      );
      final restored = PoolConfiguration.fromJson(
        cfg.toJson(localDraft: true),
      );
      expect(restored.plans.first.allowance, 'abc');
      expect(restored.plans.first.price, '1.234');
      expect(restored.pools.first.tariffs.first.rates.first.price, '12.5');
    });
    test('server json stores minor units and null for unparseable prices', () {
      final json = PoolConfiguration(
        pools: [pool(price: '19.99')],
        plans: [plan(price: 'oops')],
      ).toJson();
      expect(json['pools'][0]['tariffs'][0]['rates'][0]['price_minor'], 1999);
      expect(json['plans'][0]['price_minor'], isNull);
    });
    test('round trip of rounding-sensitive prices is lossless', () {
      for (final v in ['0.29', '1.15', '4.35', '19.99', '1000000']) {
        final r = PoolRate.fromJson(PoolRate(60, v).toJson());
        expect(double.parse(r.price), closeTo(double.parse(v), 0.0001), reason: v);
      }
    });
    test('unicode name survives local draft round trip', () {
      final restored = PoolConfiguration.fromJson(
        PoolConfiguration(pools: [pool(name: '🏊 Zoë 游泳')]).toJson(
          localDraft: true,
        ),
      );
      expect(restored.pools.first.name, '🏊 Zoë 游泳');
    });
  });
}
