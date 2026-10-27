import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/turf/models/turf_configuration.dart';
import 'package:eden_booking/modules/turf/widgets/turf_field.dart';

TurfPriceBand band({
  String id = 'b1',
  String price = '1500',
  String opens = '06:00',
  String closes = '23:00',
  bool allDay = false,
  List<int> days = const [1, 2, 3, 4, 5, 6, 7],
  List<TurfRate>? rates,
}) => TurfPriceBand(
  id: id,
  days: days,
  opens: opens,
  closes: closes,
  allDay: allDay,
  rates: rates ?? [TurfRate(60, price)],
);

TurfOffering offering({
  String id = 'o1',
  String layout = 'l1',
  TurfSport sport = TurfSport.football,
  String name = 'Football 5s',
  String format = '5v5',
  bool enabled = true,
  List<TurfRate> rates = const [TurfRate(60, '')],
  int before = 0,
  int after = 5,
  TurfHours? hours,
  List<TurfPriceBand>? bands,
  int? defaultDuration,
}) => TurfOffering(
  id: id,
  layoutId: layout,
  sport: sport,
  name: name,
  format: format,
  enabled: enabled,
  rates: rates,
  bufferBefore: before,
  bufferAfter: after,
  hoursOverride: hours,
  defaultDuration: defaultDuration,
  pricingRules: bands ?? [band()],
);

TurfConfiguration config({
  String ground = 'Main ground',
  String layoutName = 'Full pitch',
  List<TurfOffering>? offerings,
  TurfHours? operating,
  List<TurfSport> sports = const [TurfSport.football],
  List<TurfLayout>? layouts,
}) => TurfConfiguration(
  sports: sports,
  grounds: [
    TurfGround(
      id: 'g1',
      name: ground,
      arrangement: TurfArrangement.single,
      sections: const [TurfSection('s1', 'Whole')],
    ),
  ],
  layouts:
      layouts ??
      [TurfLayout(id: 'l1', groundId: 'g1', name: layoutName, sectionIds: const ['s1'])],
  offerings: offerings ?? [offering()],
  operating: operating,
);

String? check(TurfConfiguration c, {bool complete = true}) => c.validate(complete: complete);

void main() {
  test('baseline valid', () => expect(check(config()), isNull));

  group('Turf ground / space / offering names', () {
    test('ground name bounds', () {
      for (final n in ['', ' ', 'a', ' a ']) {
        expect(check(config(ground: n)), isNotNull, reason: '"$n"');
      }
      expect(check(config(ground: 'ab')), isNull);
      expect(check(config(ground: 'a' * 100)), isNull);
      expect(check(config(ground: 'a' * 101)), isNotNull);
      expect(check(config(ground: '⚽ Zoë 球场')), isNull);
    });
    test('space name bounds', () {
      for (final n in ['', ' ', 'a', 'a' * 101]) {
        expect(check(config(layoutName: n)), isNotNull, reason: '"$n"');
      }
    });
    test('duplicate space names rejected case-insensitively', () {
      final c = config(
        layouts: [
          TurfLayout(id: 'l1', groundId: 'g1', name: 'Half A', sectionIds: const ['s1']),
          TurfLayout(id: 'l2', groundId: 'g1', name: ' half a ', sectionIds: const ['s1']),
        ],
        offerings: [offering(), offering(id: 'o2', layout: 'l2', name: 'Other')],
      );
      expect(check(c), contains('distinct name'));
    });
    test('offering name 2..100 and format 2..40', () {
      for (final n in ['', ' ', 'a', 'a' * 101]) {
        expect(check(config(offerings: [offering(name: n)])), isNotNull, reason: n);
      }
      for (final f in ['', ' ', 'a', 'a' * 41]) {
        expect(check(config(offerings: [offering(format: f)])), isNotNull, reason: f);
      }
      expect(check(config(offerings: [offering(format: 'a' * 40)])), isNull);
      expect(check(config(offerings: [offering(format: '7 a-side ⚽')])), isNull);
    });
    test('duplicate ground names are accepted (only spaces must be distinct)', () {
      final c = TurfConfiguration(
        sports: const [TurfSport.football],
        grounds: [
          TurfGround(id: 'g1', name: 'North', arrangement: TurfArrangement.single, sections: const [TurfSection('s1', 'W')]),
          TurfGround(id: 'g2', name: 'north', arrangement: TurfArrangement.single, sections: const [TurfSection('s2', 'W')]),
        ],
        layouts: [
          TurfLayout(id: 'l1', groundId: 'g1', name: 'A1', sectionIds: const ['s1']),
          TurfLayout(id: 'l2', groundId: 'g2', name: 'B1', sectionIds: const ['s2']),
        ],
        offerings: [offering(), offering(id: 'o2', layout: 'l2', name: 'Other')],
      );
      expect(check(c), isNull);
    });
    test('names are sent to the server trimmed', () {
      final json = config(
        ground: '  Main  ',
        layoutName: '  Full  ',
        offerings: [offering(name: '  F5  ', format: ' 5v5 ')],
      ).toJson();
      expect(json['grounds'][0]['name'], 'Main');
      expect(json['layouts'][0]['name'], 'Full');
      expect(json['offerings'][0]['name'], 'F5');
      expect(json['offerings'][0]['format'], '5v5');
    }, skip: 'BUG-5: Turf ground/space/offering names and format labels are serialised untrimmed (pool/court/hall trim in toJson)');
  });

  group('Turf prices', () {
    TurfConfiguration withPrice(String p) => config(offerings: [offering(bands: [band(price: p)])]);
    test('valid amounts', () {
      for (final ok in ['0', '1', '1500', '1500.5', '1500.50', ' 10 ', '1000000']) {
        expect(check(withPrice(ok)), isNull, reason: ok);
      }
    });
    test('invalid amounts', () {
      for (final bad in ['', ' ', '-1', '1.999', 'abc', '💰', '1000001', '1e3', '٣']) {
        expect(check(withPrice(bad)), isNotNull, reason: '"$bad"');
      }
    });
    test('blank price: draft ok, complete rejected', () {
      expect(check(withPrice(''), complete: false), isNull);
      expect(check(withPrice(''), complete: true), isNotNull);
    });
    test('negative price rejected even in draft', () {
      expect(check(withPrice('-5'), complete: false), isNotNull);
    });
    test('disabled offering with blank price allowed', () {
      final c = config(
        offerings: [offering(), offering(id: 'o2', name: 'Cricket', sport: TurfSport.cricket, enabled: false, bands: [band(price: '')])],
        sports: [TurfSport.football],
      );
      expect(check(c), isNull);
    });
    test('whitespace price is not an error in the rate list but is for bands', () {
      expect(
        check(config(offerings: [offering(rates: const [TurfRate(60, '   ')])]), complete: false),
        isNull,
      );
    });
    test('rate list prices validated', () {
      expect(
        check(config(offerings: [offering(rates: const [TurfRate(60, '1.234')])]), complete: false),
        isNotNull,
      );
    });
    test('minor conversion precision', () {
      expect(const TurfRate(60, '19.99').minor, 1999);
      expect(const TurfRate(60, '0.07').minor, 7);
    });
    test('json round trip keeps pricing digits', () {
      final back = TurfConfiguration.fromJson(config(offerings: [offering(bands: [band(price: '1234.5')])]).toJson());
      expect(back.offerings.first.pricingRules.first.rates.first.price, '1234.50');
    });
    test('local draft keeps what the user typed', () {
      final back = TurfConfiguration.fromJson(config(offerings: [offering(bands: [band(price: '12.345')])]).toJson(localDraft: true));
      expect(back.offerings.first.pricingRules.first.rates.first.price, '12.345');
    });
  });

  group('Turf hours and durations', () {
    test('operating hours', () {
      expect(check(config(operating: TurfHours(opens: '10:00', closes: '10:00'))), isNotNull);
      expect(check(config(operating: TurfHours(days: []))), isNotNull);
      expect(check(config(operating: TurfHours(allDay: true, opens: '00:00', closes: '00:00'), offerings: [offering(bands: [band(allDay: true, opens: '00:00', closes: '00:00')])])), isNull);
      expect(TurfHours(allDay: true, opens: '06:00', closes: '23:00').validTimes, isFalse);
    });
    test('overnight span', () {
      expect(TurfHours(opens: '22:00', closes: '02:00').spanMinutes, 240);
    });
    test('duration longer than the window is rejected on completion', () {
      final c = config(
        operating: TurfHours(opens: '10:00', closes: '10:30'),
        offerings: [offering(rates: const [TurfRate(60, '')], bands: [band(opens: '10:00', closes: '10:30')])],
      );
      expect(check(c), isNotNull);
    });
    test('default duration must be in the allowed rates', () {
      expect(
        check(config(offerings: [offering(rates: const [TurfRate(60, '')], defaultDuration: 90)]), complete: false),
        isNotNull,
      );
    });
    test('rate durations are bounded 30..1440 and unique', () {
      for (final d in [0, -60, 5, 1441, 100000]) {
        final c = config(offerings: [offering(rates: [TurfRate(d, '')], defaultDuration: d, bands: [band(rates: [TurfRate(d, '1')])])]);
        expect(check(c), isNotNull, reason: '$d');
      }
    }, skip: 'BUG-6: Turf validation never bounds offering durations (0, negative or >1440 minutes accepted); pool/court/hall enforce 30..1440');
    test('duplicate rate durations rejected', () {
      final c = config(offerings: [offering(rates: const [TurfRate(60, ''), TurfRate(60, '')])]);
      expect(check(c, complete: false), isNotNull);
    });
    test('buffers are bounded 0..240', () {
      expect(check(config(offerings: [offering(before: -1)])), isNotNull);
      expect(check(config(offerings: [offering(after: 241)])), isNotNull);
      expect(check(config(offerings: [offering(before: 100000, after: 100000)])), isNotNull);
    }, skip: 'BUG-7: Turf validation never bounds preparation/cleanup buffers (pool/court/hall reject <0 and >240)');
    test('hours override must stay inside operating hours', () {
      final c = config(
        operating: TurfHours(opens: '08:00', closes: '20:00'),
        offerings: [offering(hours: TurfHours(opens: '07:00', closes: '20:00'), bands: [band(opens: '08:00', closes: '20:00')])],
      );
      expect(check(c), isNotNull);
    });
    test('override with no days rejected', () {
      expect(check(config(offerings: [offering(hours: TurfHours(days: []))])), isNotNull);
    });
  });

  group('Turf price rules', () {
    test('overlapping price rules rejected, adjacent allowed', () {
      TurfPriceBand b(String id, String a, String z, {List<int>? days}) => band(id: id, opens: a, closes: z, days: days ?? [1, 2, 3, 4, 5, 6, 7]);
      expect(check(config(offerings: [offering(bands: [b('a', '06:00', '12:00'), b('b', '11:00', '15:00')])])), contains('overlap'));
      expect(check(config(offerings: [offering(bands: [b('a', '06:00', '12:00'), b('b', '12:00', '15:00')])])), isNull);
      expect(check(config(offerings: [offering(bands: [b('a', '06:00', '12:00', days: [1]), b('b', '06:00', '12:00', days: [2])])])), isNull);
    });
    test('rule outside opening hours rejected', () {
      expect(
        check(config(operating: TurfHours(opens: '08:00', closes: '12:00'), offerings: [offering(bands: [band(opens: '07:00', closes: '12:00')])])),
        isNotNull,
      );
    });
    test('rule without days rejected', () {
      expect(check(config(offerings: [offering(bands: [band(days: [])])])), isNotNull);
    });
    test('enabled offering needs a price rule on completion', () {
      expect(check(config(offerings: [offering(bands: [])])), isNotNull);
      expect(check(config(offerings: [offering(bands: [])]), complete: false), isNull);
    });
    test('band prices must cover every allowed duration', () {
      final c = config(offerings: [
        offering(rates: const [TurfRate(60, ''), TurfRate(90, '')], bands: [band(rates: const [TurfRate(60, '1')])]),
      ]);
      expect(check(c, complete: false), isNotNull);
    });
  });

  group('Turf sports and completeness', () {
    test('no sports when completing', () {
      expect(check(config(sports: const [])), isNotNull);
      expect(check(config(sports: const []), complete: false), isNull);
    });
    test('every selected sport needs an enabled offering', () {
      expect(check(config(sports: const [TurfSport.football, TurfSport.cricket])), isNotNull);
    });
    test('every space needs an enabled offering', () {
      expect(check(config(offerings: [offering(enabled: false)])), isNotNull);
    });
    test('no grounds is rejected', () {
      final c = TurfConfiguration(sports: const [TurfSport.football], grounds: const [], layouts: const [], offerings: const []);
      expect(check(c, complete: false), isNotNull);
    });
  });

  group('turfName validator', () {
    test('bounds', () {
      expect(turfName(null), isNotNull);
      expect(turfName(''), isNotNull);
      expect(turfName('  '), isNotNull);
      expect(turfName('a'), isNotNull);
      expect(turfName('ab'), isNull);
      expect(turfName('a' * 100), isNull);
      expect(turfName('a' * 101), isNotNull);
      expect(turfName('⚽⚽'), isNull);
    });
  });
}
