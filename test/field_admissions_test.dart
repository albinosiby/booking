import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/models/booking_payment_entry_model.dart';
import 'package:flutter_test/flutter_test.dart';

BookingCustomer c({String name = 'Anjali', String phone = '9876543210', String email = ''}) =>
    BookingCustomer(name: name, phone: phone, email: email);

AdmissionPlan plan(String mode, {int? days, int? months, int? years, String? date}) => AdmissionPlan(
  'p', 'Plan', 'swimming', const ['x'], 10, 1000, null, 'Unassigned',
  expiryMode: mode, expiryDays: days, expiryMonths: months, expiryYears: years, expiryDate: date,
);

void main() {
  group('Admission customer fields', () {
    test('name bounds, whitespace, unicode', () {
      for (final n in ['', ' ', 'a', ' a ', 'a' * 101]) {
        expect(c(name: n).validate(), isNotNull, reason: '"$n"');
      }
      for (final n in ['ab', 'a' * 100, ' Zoë ', '李雷', '🏊🏊']) {
        expect(c(name: n).validate(), isNull, reason: n);
      }
    });
    test('valid phones', () {
      for (final p in ['9876543210', '+91 98765 43210', '(022) 1234-567', '1234567', '1' * 25]) {
        expect(c(phone: p).validate(), isNull, reason: p);
      }
    });
    test('invalid phones', () {
      for (final p in ['', ' ', '123456', '1' * 26, 'abcdefghij', '98765x3210', '١٢٣٤٥٦٧٨', '📞📞📞📞📞📞📞', '+', '12-34']) {
        expect(c(phone: p).validate(), isNotNull, reason: p);
      }
    });
    test('phone must contain digits', () {
      for (final p in ['-------', '((((((((', '+-------', '()()()()']) {
        expect(c(phone: p).validate(), isNotNull, reason: p);
      }
    }, skip: 'BUG-22: phone regex accepts strings with no digits such as "-------" or "(((((((("');
    test('email optional, validated when present', () {
      expect(c(email: '').validate(), isNull);
      expect(c(email: 'a@b.co').validate(), isNull);
      expect(c(email: ' a@b.co ').validate(), isNull);
      for (final e in ['a', 'a@b', '@b.co', 'a b@c.de', 'a@@b.co']) {
        expect(c(email: e).validate(), isNotNull, reason: e);
      }
    });
    test('whitespace-only email is treated as empty', () {
      expect(c(email: '   ').validate(), isNull);
    }, skip: 'BUG-23: whitespace-only email fails validation although toJson sends it as null');
    test('toJson trims and nulls empty email', () {
      final j = c(name: ' Ann ', phone: ' 9876543210 ', email: '  ').toJson();
      expect(j['name'], 'Ann');
      expect(j['phone'], '9876543210');
      expect(j['email'], isNull);
    });
  });

  group('Payment drafts', () {
    BookingPaymentDraft p(String amount, {String ref = '', DateTime? at}) =>
        BookingPaymentDraft(amount: amount, reference: ref, receivedAt: at);
    test('amounts', () {
      for (final ok in ['1', '0.01', '19.99', ' 5 ', '1000000']) {
        expect(p(ok).validate(), isNull, reason: ok);
      }
      for (final bad in ['0', '0.00', '-1', '1.001', 'abc', '💰', '١', '1000000.01', '1e2']) {
        expect(p(bad).validate(), isNotNull, reason: bad);
      }
    });
    test('reference limit 200 and future time', () {
      expect(p('1', ref: 'a' * 200).validate(), isNull);
      expect(p('1', ref: 'a' * 201).validate(), isNotNull);
      expect(p('1', at: DateTime.now().add(const Duration(hours: 1))).validate(), isNotNull);
    });
    test('blank detection and balance maths', () {
      expect(p('').isBlank, isTrue);
      expect(p('  ').isBlank, isTrue);
      final a = p('60'), b = p('50');
      final m = BookingPaymentEntryModel(total: 10000, payments: [a, b]);
      expect(m.received, 11000);
      expect(m.remaining, 0);
      expect(m.errorFor(b), 'Amount exceeds the remaining balance.');
      expect(m.errorFor(a), 'Amount exceeds the remaining balance.');
      expect(m.balanceFor(a.id), 5000);
    });
    test('invalid amounts count as zero received', () {
      final m = BookingPaymentEntryModel(total: 100, payments: [p('x'), p('-5')]);
      expect(m.received, 0);
    });
    test('no total means no balance limit', () {
      final m = BookingPaymentEntryModel(total: null, payments: [p('999999')]);
      expect(m.errorFor(m.payments.first), isNull);
    });
  });

  group('AdmissionPlan expiry arithmetic', () {
    test('days', () {
      expect(plan('after_start', days: 45).expiryFor('2026-12-31'), '2027-02-14');
      expect(plan('after_start', days: 0).expiryFor('2026-12-31'), '2026-12-31');
    });
    test('months clamp to month end', () {
      expect(plan('after_months', months: 1).expiryFor('2026-01-31'), '2026-02-28');
      expect(plan('after_months', months: 1).expiryFor('2028-01-31'), '2028-02-29');
    });
    test('years clamp leap day', () {
      expect(plan('after_years', years: 1).expiryFor('2028-02-29'), '2029-02-28');
    });
    test('fixed date and missing data', () {
      expect(plan('fixed_date', date: '2030-01-01').expiryFor('2026-01-01'), '2030-01-01');
      expect(plan('after_months').expiryFor('2026-01-01'), isNull);
      expect(plan('after_start', days: 5).expiryFor('garbage'), isNull);
      expect(plan('after_start', days: 5).expiryFor(''), isNull);
    });
    test('impossible calendar start is rejected', () {
      expect(plan('after_start', days: 1).expiryFor('2026-02-30'), isNull);
    }, skip: 'BUG-24: expiryFor accepts impossible dates like 2026-02-30 (DateTime.tryParse rolls over to March)');
    test('validity label pluralisation', () {
      expect(plan('after_months', months: 1).validityLabel, '1 month');
      expect(plan('after_months', months: 3).validityLabel, '3 months');
      expect(plan('after_years', years: 1).validityLabel, '1 year');
      expect(plan('fixed_date').validityLabel, 'Until —');
    });
  });
}
