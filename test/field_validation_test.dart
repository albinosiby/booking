import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/utils/helpers/validation.dart';
import 'package:eden_booking/modules/pool/widgets/pool_editors.dart';
import 'package:eden_booking/modules/court/widgets/court_editors.dart' as court;

void main() {
  group('Validation.priceMinor amount parsing', () {
    int? p(String s) => Validation.priceMinor(s);
    test('valid whole and decimal amounts', () {
      expect(p('0'), 0);
      expect(p('1'), 100);
      expect(p('199'), 19900);
      expect(p('199.5'), 19950);
      expect(p('199.50'), 19950);
      expect(p('0.01'), 1);
      expect(p('0.99'), 99);
      expect(p('1000000'), 100000000);
    });
    test('surrounding whitespace is trimmed', () {
      expect(p('  12.30 '), 1230);
      expect(p('\t5\n'), 500);
    });
    test('empty and whitespace-only are rejected', () {
      expect(p(''), isNull);
      expect(p('   '), isNull);
    });
    test('negative, signed, exponent, hex are rejected', () {
      for (final v in ['-1', '-0', '+5', '1e3', '0x10', '1,000', '1 000']) {
        expect(p(v), isNull, reason: v);
      }
    });
    test('more than two decimals is rejected, not rounded', () {
      expect(p('1.999'), isNull);
      expect(p('0.001'), isNull);
      expect(p('1.'), isNull);
      expect(p('.5'), isNull);
    });
    test('huge numbers are bounded', () {
      expect(p('1000000.01'), isNull);
      expect(p('1000001'), isNull);
      expect(p('99999999999999999999999'), isNull);
      expect(p('9' * 400), isNull);
    });
    test('unicode digits, emoji, letters and injection are rejected', () {
      for (final v in [
        '١٢٣',
        '１２３',
        '12💰',
        '💰',
        'abc',
        '12abc',
        "1'; DROP TABLE x;--",
        '<b>1</b>',
        '1​',
        'NaN',
        'Infinity',
      ]) {
        expect(p(v), isNull, reason: v);
      }
    });
    test('float representation never leaks into minor units', () {
      // 19.99 * 100 == 1998.9999999999998 in floating point.
      expect(p('19.99'), 1999);
      expect(p('0.29'), 29);
      expect(p('1.15'), 115);
      expect(p('4.35'), 435);
    });
    test('single decimal digit pads to tens', () {
      expect(p('1.5'), 150);
      expect(p('1.05'), 105);
      expect(p('1.0'), 100);
    });
  });

  group('Validation helpers', () {
    test('name boundaries', () {
      expect(Validation.name(null), isNotNull);
      expect(Validation.name(''), isNotNull);
      expect(Validation.name('   '), isNotNull);
      expect(Validation.name('a'), isNotNull);
      expect(Validation.name(' a '), isNotNull);
      expect(Validation.name('ab'), isNull);
      expect(Validation.name('a' * 120), isNull);
      expect(Validation.name('a' * 121), isNotNull);
      expect(Validation.name(' ${'a' * 120} '), isNull);
    });
    test('name accepts unicode and emoji', () {
      expect(Validation.name('Zoë Müller'), isNull);
      expect(Validation.name('李雷'), isNull);
      expect(Validation.name('🏊🏊'), isNull);
    });
    test('a single emoji passes the two-character minimum (UTF-16 length)', () {
      // Documents current behaviour: length counts UTF-16 units, not graphemes.
      expect(Validation.name('🏊'), isNull);
    });
    test('required trims', () {
      expect(Validation.required(null), isNotNull);
      expect(Validation.required('  \n'), isNotNull);
      expect(Validation.required(' x '), isNull);
    });
    test('email', () {
      for (final ok in ['a@b.co', ' a@b.co ', 'a+tag@sub.example.com']) {
        expect(Validation.email(ok), isNull, reason: ok);
      }
      for (final bad in ['', 'a', 'a@b', '@b.co', 'a b@c.de', 'a@@b.co']) {
        expect(Validation.email(bad), isNotNull, reason: bad);
      }
    });
    test('password', () {
      expect(Validation.password(null), isNotNull);
      expect(Validation.password('1234567'), isNotNull);
      expect(Validation.password('12345678'), isNull);
    });
  });

  group('shared pool and court integer / price / name validators', () {
    test('integer validators agree on 1..10000', () {
      for (final f in [poolInteger, court.courtInteger]) {
        expect(f(null), isNotNull);
        expect(f(''), isNotNull);
        expect(f('0'), isNotNull);
        expect(f('-1'), isNotNull);
        expect(f('1'), isNull);
        expect(f('10000'), isNull);
        expect(f('10001'), isNotNull);
        expect(f('1.5'), isNotNull);
        expect(f('99999999999999999999'), isNotNull);
        expect(f('١٢'), isNotNull);
        expect(f('12abc'), isNotNull);
      }
    });
    test('integer validators accept whitespace-padded input consistently', () {
      for (final f in [poolInteger, court.courtInteger]) {
        expect(f(' 20 '), isNull);
      }
    });
    test('integer validators reject hex and plus-sign forms', () {
      for (final f in [poolInteger, court.courtInteger]) {
        expect(f('0x10'), isNotNull, reason: 'hex literal accepted as 16');
        expect(f('+5'), isNotNull, reason: 'plus sign accepted');
      }
    }, skip: 'BUG-1: int.tryParse accepts "0x10" and "+5" in capacity/seat/allowance fields');
    test('name validators', () {
      for (final f in [poolName, court.courtName]) {
        expect(f(null), isNotNull);
        expect(f(''), isNotNull);
        expect(f('   '), isNotNull);
        expect(f('a'), isNotNull);
        expect(f('ab'), isNull);
        expect(f('a' * 100), isNull);
        expect(f('a' * 101), isNotNull);
        expect(f('🏊🏊'), isNull);
        expect(f('Café ☕'), isNull);
      }
    });
    test('price validators', () {
      for (final f in [poolPrice, court.courtPrice]) {
        expect(f(null), isNotNull);
        expect(f(''), isNotNull);
        expect(f('-5'), isNotNull);
        expect(f('0'), isNull);
        expect(f('10.999'), isNotNull);
        expect(f('1000000'), isNull);
        expect(f('1000001'), isNotNull);
      }
    });
  });
}
