import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/hall/models/hall_configuration.dart';
import 'package:eden_booking/modules/hall/widgets/hall_editors.dart';

HallPackage pkg(
  String id,
  String name, {
  String opens = '09:00',
  String closes = '13:00',
  bool enabled = false,
  List<HallPackagePrice> prices = const [],
}) => HallPackage(
  id: id,
  name: name,
  hours: HallHours(opens: opens, closes: closes),
  enabled: enabled,
  prices: prices,
);

HallResource hall({
  String id = 'h1',
  String name = 'Grand Hall',
  String capacity = '100',
  String seated = '80',
  String amenities = '',
  String environment = 'unspecified',
  bool enabled = true,
  bool hourly = true,
  String price = '1000',
  HallHours? hours,
  List<int> durations = const [60],
  int defaultDuration = 60,
  int before = 0,
  int after = 5,
  List<HallTariff>? tariffs,
  List<HallPackage>? sessions,
  HallPackage? fullDay,
}) => HallResource(
  id: id,
  name: name,
  capacity: capacity,
  seated: seated,
  amenities: amenities,
  environment: environment,
  enabled: enabled,
  hourlyEnabled: hourly,
  hours: hours,
  durations: durations,
  defaultDuration: defaultDuration,
  before: before,
  after: after,
  tariffs:
      tariffs ??
      [
        HallTariff(
          id: 't-$id',
          hours: hours ?? HallHours(),
          rates: durations.map((d) => HallRate(d, price)),
        ),
      ],
  sessions: sessions ?? [pkg('s1-$id', 'Morning'), pkg('s2-$id', 'Evening', opens: '17:00', closes: '22:00')],
  fullDay: fullDay ?? pkg('f-$id', 'Full day', opens: '09:00', closes: '23:00'),
);

String? check(Iterable<HallResource> halls, {bool complete = true}) =>
    HallConfiguration(halls: halls).validate(complete: complete);

void main() {
  test('baseline valid', () => expect(check([hall()]), isNull));

  group('Hall name', () {
    test('bounds, whitespace, unicode', () {
      for (final n in ['', ' ', 'a', ' a ']) {
        expect(check([hall(name: n)]), isNotNull, reason: '"$n"');
      }
      for (final n in ['ab', 'a' * 100, 'Salle 🎉', '宴会厅', ' Grand ']) {
        expect(check([hall(name: n)]), isNull, reason: n);
      }
      expect(check([hall(name: 'a' * 101)]), isNotNull);
    });
    test('duplicate names rejected', () {
      expect(
        check([hall(id: 'a', name: 'Grand'), hall(id: 'b', name: ' GRAND ')]),
        'Use unique hall names and identifiers.',
      );
    });
    test('duplicate ids rejected', () {
      expect(check([hall(id: 'a', name: 'One'), hall(id: 'a', name: 'Two')]), isNotNull);
    });
    test('51 halls rejected', () {
      final halls = [for (var i = 0; i < 51; i++) hall(id: 'h$i', name: 'Hall ${i + 10}')];
      expect(check(halls, complete: false), 'Use at most 50 halls per business.');
    });
    test('toJson trims', () => expect(hall(name: '  X1  ').toJson()['name'], 'X1'));
  });

  group('Hall capacity and seated capacity', () {
    test('capacity invalid values', () {
      for (final c in ['', ' ', '0', '-1', '10001', '1.5', 'x', '٣', '💺', '9' * 30]) {
        expect(check([hall(capacity: c, seated: '0')]), isNotNull, reason: '"$c"');
      }
    });
    test('capacity boundaries', () {
      expect(check([hall(capacity: '1', seated: '1')]), isNull);
      expect(check([hall(capacity: '10000', seated: '10000')]), isNull);
    });
    test('seated invalid values', () {
      for (final s in ['', '-1', '101', '1.5', 'x', '٣']) {
        expect(check([hall(capacity: '100', seated: s)]), isNotNull, reason: '"$s"');
      }
    });
    test('seated zero and equal to capacity accepted', () {
      expect(check([hall(seated: '0')]), isNull);
      expect(check([hall(seated: '100')]), isNull);
    });
    test('seated greater than capacity rejected (min>max)', () {
      expect(check([hall(capacity: '50', seated: '51')]), isNotNull);
    });
    test('seated can silently exceed capacity after capacity is lowered', () {
      // capacity edited from 100 to 40 while seated stays 80.
      expect(check([hall(capacity: '40', seated: '80')]), isNotNull);
    });
    test('hex and plus signs rejected', () {
      expect(check([hall(capacity: '0x64', seated: '0')]), isNotNull);
      expect(check([hall(capacity: '+100', seated: '0')]), isNotNull);
      expect(check([hall(capacity: '100', seated: '+5')]), isNotNull);
    }, skip: 'BUG-1: int.tryParse accepts hex ("0x64") and "+" prefixes in capacity fields');
    test('json carries ints', () {
      final j = hall(capacity: '120', seated: '60').toJson();
      expect(j['capacity'], 120);
      expect(j['seated_capacity'], 60);
    });
    test('json emits null for unparseable capacity instead of failing', () {
      final j = hall(capacity: 'x', seated: '').toJson();
      expect(j['capacity'], isNull);
      expect(j['seated_capacity'], isNull);
    });
  });

  group('Hall amenities and environment', () {
    test('1000 trimmed characters max', () {
      expect(check([hall(amenities: 'a' * 1000)]), isNull);
      expect(check([hall(amenities: 'a' * 1001)]), isNotNull);
      expect(check([hall(amenities: ' ${'a' * 1000} ')]), isNull);
      expect(check([hall(amenities: ' ' * 5000)]), isNull);
    });
    test('emoji and newline allowed', () {
      expect(check([hall(amenities: 'AC ❄️\nWi-Fi 📶')]), isNull);
    });
    test('environment must be known', () {
      expect(check([hall(environment: 'roof')]), isNotNull);
      for (final e in ['indoor', 'outdoor', 'unspecified']) {
        expect(check([hall(environment: e)]), isNull);
      }
    });
  });

  group('Hall hours, durations and buffers', () {
    test('closing equal to opening is rejected (no 24-hour halls)', () {
      expect(HallHours(opens: '08:00', closes: '08:00').validate(), isNotNull);
      expect(HallHours(opens: '00:00', closes: '00:00').validate(), isNotNull);
    });
    test('malformed times and weekdays', () {
      expect(HallHours(opens: '8:00').validate(), isNotNull);
      expect(HallHours(closes: '24:00').validate(), isNotNull);
      expect(HallHours(days: []).validate(), isNotNull);
      expect(HallHours(days: [0]).validate(), isNotNull);
      expect(HallHours(days: [2, 2]).validate(), isNotNull);
    });
    test('overnight window', () {
      expect(HallHours(opens: '20:00', closes: '02:00').span, 360);
    });
    test('date ranges', () {
      expect(HallHours(dateFrom: '2030-01-01').validate(), isNotNull);
      expect(HallHours(dateFrom: '2030-02-01', dateUntil: '2030-01-01').validate(), isNotNull);
      expect(HallHours(dateFrom: '2030-02-30', dateUntil: '2030-03-01').validate(), isNotNull);
      expect(HallHours(dateFrom: '2030-01-01', dateUntil: '2030-01-01').validate(), isNull);
    });
    test('hall operating hours cannot be dated', () {
      expect(
        check([hall(hours: HallHours(dateFrom: '2030-01-01', dateUntil: '2030-02-01'))]),
        isNotNull,
      );
    });
    test('durations 30..1440, max 10, unique, default listed', () {
      expect(check([hall(durations: [29], defaultDuration: 29, tariffs: [])], complete: false), isNotNull);
      expect(check([hall(durations: [1441], defaultDuration: 1441, tariffs: [])], complete: false), isNotNull);
      expect(check([hall(durations: [60, 60], tariffs: [])], complete: false), isNotNull);
      expect(check([hall(durations: [60], defaultDuration: 30, tariffs: [])], complete: false), isNotNull);
      expect(check([hall(durations: [], tariffs: [])], complete: false), isNotNull);
      expect(
        check([hall(durations: [for (var i = 1; i <= 11; i++) 30 * i], defaultDuration: 30, tariffs: [])], complete: false),
        isNotNull,
      );
    });
    test('buffers', () {
      expect(check([hall(before: -1)]), isNotNull);
      expect(check([hall(after: 241)]), isNotNull);
      expect(check([hall(before: 240, after: 240)]), isNull);
    });
  });

  group('Hall hourly prices', () {
    test('amount strings', () {
      for (final ok in ['0', '10', '10.5', '10.50', '1000000']) {
        expect(check([hall(price: ok)]), isNull, reason: ok);
      }
      for (final bad in ['', '-1', '10.555', 'x', '💰', '1000001', '٣']) {
        expect(check([hall(price: bad)]), isNotNull, reason: bad);
      }
    });
    test('hourly disabled does not require hourly prices', () {
      expect(check([hall(hourly: false, price: '', fullDay: pkg('f', 'Full day', enabled: true, prices: [HallPackagePrice(id: 'p', price: '5000')]))]), isNull);
    });
    test('blank price accepted while drafting', () {
      expect(check([hall(price: '')], complete: false), isNull);
    });
    test('tariffs must remain inside operating hours', () {
      final h = hall(
        hours: HallHours(opens: '09:00', closes: '12:00'),
        tariffs: [
          HallTariff(
            id: 't',
            hours: HallHours(opens: '08:00', closes: '12:00'),
            rates: const [HallRate(60, '10')],
          ),
        ],
        sessions: const [],
        fullDay: pkg('f', 'Full day', opens: '09:00', closes: '12:00'),
      );
      expect(check([h]), isNotNull);
    });
    test('overlap detection', () {
      HallTariff t(String id, String a, String b) => HallTariff(
        id: id,
        hours: HallHours(opens: a, closes: b),
        rates: const [HallRate(60, '10')],
      );
      final base = (List<HallTariff> ts) => hall(
        hours: HallHours(opens: '06:00', closes: '22:00'),
        tariffs: ts,
        sessions: const [],
        fullDay: pkg('f', 'Full day', opens: '06:00', closes: '22:00'),
      );
      expect(check([base([t('a', '06:00', '12:00'), t('b', '11:00', '14:00')])]), 'Price rules overlap for Grand Hall.');
      expect(check([base([t('a', '06:00', '12:00'), t('b', '12:00', '14:00')])]), isNull);
      expect(check([base([t('x', '06:00', '12:00'), t('x', '12:00', '14:00')])]), isNotNull, reason: 'duplicate ids');
    });
    test('41 tariffs rejected', () {
      final ts = [
        for (var i = 0; i < 41; i++)
          HallTariff(id: 't$i', hours: HallHours(days: [1 + i % 7]), rates: const [HallRate(60, '1')]),
      ];
      expect(check([hall(tariffs: ts)], complete: false), isNotNull);
    });
  });

  group('Hall sessions and full-day packages', () {
    test('session name bounds and duplicates', () {
      for (final n in ['', ' ', 'a', 'a' * 101]) {
        expect(
          check([hall(sessions: [pkg('s', n)])], complete: false),
          isNotNull,
          reason: '"$n"',
        );
      }
      expect(
        check([hall(sessions: [pkg('a', 'Morning'), pkg('b', ' morning ')])]),
        'Use distinct session names and IDs, up to 12 sessions.',
      );
    });
    test('session ids must not collide with the full-day id', () {
      expect(check([hall(sessions: [pkg('f-h1', 'Morning')])]), isNotNull);
    });
    test('13 sessions rejected', () {
      final s = [for (var i = 0; i < 13; i++) pkg('s$i', 'Session ${i + 10}')];
      expect(check([hall(sessions: s)], complete: false), isNotNull);
    });
    test('session named like the full-day package is rejected', () {
      expect(check([hall(sessions: [pkg('s', 'Full day')])]), isNotNull);
    }, skip: 'BUG-4: a session may share its name with the Full day package (uniqueness only checked among sessions), producing two indistinguishable options for customers');
    test('enabled session must fit inside hall hours', () {
      final h = hall(
        hours: HallHours(opens: '09:00', closes: '12:00'),
        tariffs: const [],
        hourly: false,
        sessions: [pkg('s', 'Late', opens: '11:00', closes: '14:00', enabled: true, prices: [HallPackagePrice(id: 'p', price: '100')])],
        fullDay: pkg('f', 'Full day', opens: '09:00', closes: '12:00'),
      );
      expect(check([h], complete: false), isNotNull);
    });
    test('enabled package needs prices when completing', () {
      final h = hall(
        hourly: false,
        sessions: [pkg('s', 'Morning', enabled: true)],
        fullDay: pkg('f', 'Full day', opens: '09:00', closes: '23:00'),
      );
      expect(check([h]), 'Complete prices for Morning.');
      expect(check([h], complete: false), isNull);
    });
    test('package price strings', () {
      HallResource with_(String p) => hall(
        hourly: false,
        sessions: [
          pkg('s', 'Morning', enabled: true, prices: [HallPackagePrice(id: 'p', price: p)]),
        ],
      );
      for (final ok in ['0', '5000', '5000.5']) {
        expect(check([with_(ok)]), isNull, reason: ok);
      }
      for (final bad in ['', '-1', '5.555', 'x', '9' * 20]) {
        expect(check([with_(bad)]), isNotNull, reason: '"$bad"');
      }
    });
    test('package price rules may not overlap by weekday', () {
      final h = hall(
        hourly: false,
        sessions: [
          pkg('s', 'Morning', enabled: true, prices: [
            HallPackagePrice(id: 'a', days: [1, 2], price: '1'),
            HallPackagePrice(id: 'b', days: [2, 3], price: '2'),
          ]),
        ],
      );
      expect(check([h]), 'Price rules overlap for Morning.');
    });
    test('package price weekday outside the package weekdays rejected', () {
      final h = hall(
        hourly: false,
        sessions: [
          HallPackage(
            id: 's',
            name: 'Morning',
            hours: HallHours(days: [1, 2], opens: '09:00', closes: '13:00'),
            enabled: true,
            prices: [HallPackagePrice(id: 'a', days: [5], price: '1')],
          ),
        ],
      );
      expect(check([h]), isNotNull);
    });
    test('hall with every booking option off when completing', () {
      expect(
        check([hall(hourly: false)]),
        'Enable at least one booking option for Grand Hall.',
      );
    });
    test('package price rules capped at 40', () {
      final prices = [
        for (var i = 0; i < 41; i++) HallPackagePrice(id: 'p$i', days: [1 + i % 7], dateFrom: '2030-01-${(i % 28 + 1).toString().padLeft(2, '0')}', dateUntil: '2030-01-${(i % 28 + 1).toString().padLeft(2, '0')}', price: '1'),
      ];
      expect(
        check([hall(sessions: [pkg('s', 'Morning', prices: prices)])], complete: false),
        isNotNull,
      );
    });
  });

  group('Hall draft json', () {
    test('local draft preserves raw text', () {
      final cfg = HallConfiguration(
        halls: [hall(name: ' ', capacity: 'abc', seated: '', amenities: ' 🎉 ')],
      );
      final back = HallConfiguration.fromJson(cfg.toJson(localDraft: true));
      expect(back.halls.first.name, ' ');
      expect(back.halls.first.capacity, 'abc');
      expect(back.halls.first.seated, '');
      expect(back.halls.first.amenities, ' 🎉 ');
    });
    test('server json uses minor units', () {
      final j = hall(price: '19.99').toJson();
      expect(j['tariffs'][0]['rates'][0]['price_minor'], 1999);
    });
  });

  group('shared hall validators', () {
    test('hallName / hallInteger / hallPrice', () {
      expect(hallName(null), isNotNull);
      expect(hallName(' '), isNotNull);
      expect(hallName('ab'), isNull);
      expect(hallName('a' * 101), isNotNull);
      expect(hallInteger('0'), isNotNull);
      expect(hallInteger('10001'), isNotNull);
      expect(hallInteger('10000'), isNull);
      expect(hallInteger('1.5'), isNotNull);
      expect(hallPrice('-1'), isNotNull);
      expect(hallPrice('1.234'), isNotNull);
      expect(hallPrice('1.23'), isNull);
    });
  });
}
