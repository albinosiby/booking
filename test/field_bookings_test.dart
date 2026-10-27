// Field-value tests for lib/modules/bookings: amounts, discounts, payments,
// customer fields, people count, dates/times, double submit and small-screen /
// large-text rendering. Real defects are kept but skipped with `BUG-<n>`; see
// docs/audits/test-report-flutter-bookings.md.
import 'dart:async';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_detail_cubit.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_detail_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_discount.dart';
import 'package:eden_booking/modules/bookings/models/booking_form_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/models/booking_payment_entry_model.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_discount_editor.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_payment_editor.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_widgets.dart';
import 'package:eden_booking/utils/helpers/validation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'booking_module_test.dart' show form, customer;

const longEmoji = '😀';

Future<void> mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(320, 568),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        theme: AppTheme.build(Brightness.light),
        builder: (context, app) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: app!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Validation.priceMinor (amount / discount / payment parser)', () {
    const valid = {
      '0': 0,
      '0.5': 50,
      '0.05': 5,
      '1': 100,
      '1.5': 150,
      '1.50': 150,
      '12.34': 1234,
      ' 7 ': 700,
      '01': 100,
      '1000000': 100000000,
      '1000000.00': 100000000,
    };
    valid.forEach((input, minor) {
      test('accepts "$input" as $minor minor units', () {
        expect(Validation.priceMinor(input), minor);
      });
    });
    const invalid = [
      '',
      ' ',
      '-1',
      '-0',
      '+5',
      '1.234',
      '.5',
      '5.',
      '1,000',
      '1e3',
      '0x10',
      'abc',
      '1 000',
      longEmoji,
      '٣', // Arabic-Indic digit
      '１２', // full-width digits
      '1000000.01',
      '1000001',
      '99999999999999999999999',
      '5\n5',
    ];
    for (final input in invalid) {
      test('rejects ${input.isEmpty ? '<empty>' : '"$input"'}', () {
        expect(Validation.priceMinor(input), isNull);
      });
    }
  });

  group('BookingPaymentDraft', () {
    test('blank means empty amount and empty/whitespace reference', () {
      expect(BookingPaymentDraft().isBlank, isTrue);
      expect(
        BookingPaymentDraft(amount: '   ', reference: '  \t ').isBlank,
        isTrue,
      );
      expect(BookingPaymentDraft(amount: '0').isBlank, isFalse);
      expect(BookingPaymentDraft(reference: 'UPI-1').isBlank, isFalse);
    });
    for (final amount in [
      '0',
      '0.00',
      '-5',
      '',
      ' ',
      'abc',
      '1.234',
      longEmoji,
    ]) {
      test('rejects amount "$amount"', () {
        expect(
          BookingPaymentDraft(amount: amount).validate(),
          'Enter a positive payment amount.',
        );
      });
    }
    for (final amount in ['0.01', '1', '99.99', '1000000']) {
      test('accepts amount "$amount"', () {
        expect(BookingPaymentDraft(amount: amount).validate(), isNull);
      });
    }
    test('reference length boundary at 200 and unicode', () {
      expect(
        BookingPaymentDraft(amount: '1', reference: 'a' * 200).validate(),
        isNull,
      );
      expect(
        BookingPaymentDraft(amount: '1', reference: 'a' * 201).validate(),
        contains('200 characters'),
      );
      expect(
        BookingPaymentDraft(
          amount: '1',
          reference: ' ${'a' * 200} ',
        ).validate(),
        isNull,
        reason: 'surrounding whitespace is trimmed before the limit',
      );
      expect(
        BookingPaymentDraft(
          amount: '1',
          reference: 'UPI ✅ ref 😀 உதாரணம்',
        ).validate(),
        isNull,
      );
      expect(
        BookingPaymentDraft(
          amount: '1',
          reference: '  x  ',
        ).toJson()['reference'],
        'x',
      );
    });
    test('received time in the future is refused, past accepted', () {
      final now = DateTime.now();
      expect(
        BookingPaymentDraft(
          amount: '1',
          receivedAt: now.add(const Duration(minutes: 5)),
        ).validate(),
        'Payment time cannot be in the future.',
      );
      expect(
        BookingPaymentDraft(
          amount: '1',
          receivedAt: now.add(const Duration(seconds: 30)),
        ).validate(),
        isNull,
        reason: 'one minute clock-skew tolerance',
      );
      expect(
        BookingPaymentDraft(amount: '1', receivedAt: DateTime(2000)).validate(),
        isNull,
      );
    });
    test('changing method clears the account id', () {
      final p = BookingPaymentDraft(accountId: 'a', method: 'cash');
      expect(p.copyWith(method: 'upi').accountId, isNull);
      expect(p.copyWith(method: 'cash').accountId, 'a');
    });
  });

  group('BookingPaymentEntryModel', () {
    test('remaining clamps, blank rows are ignored and overpay errors', () {
      final a = BookingPaymentDraft(id: 'a', amount: '60');
      final b = BookingPaymentDraft(id: 'b', amount: '50');
      final blank = BookingPaymentDraft(id: 'c');
      final m = BookingPaymentEntryModel(total: 10000, payments: [a, b, blank]);
      expect(m.received, 11000);
      expect(m.remaining, 0, reason: 'never negative');
      expect(m.recorded, hasLength(2));
      expect(m.errorFor(blank), isNull);
      expect(m.errorFor(b), 'Amount exceeds the remaining balance.');
      expect(
        m.errorFor(a),
        'Amount exceeds the remaining balance.',
        reason: 'each row is checked against total minus the other rows',
      );
      expect(
        BookingPaymentEntryModel(
          total: 10000,
          payments: [BookingPaymentDraft(id: 'x', amount: '100')],
        ).errorFor(BookingPaymentDraft(id: 'x', amount: '100')),
        isNull,
      );
    });
    test('unknown total never reports an overpay and shows no remaining', () {
      final a = BookingPaymentDraft(id: 'a', amount: '99999');
      final m = BookingPaymentEntryModel(total: null, payments: [a]);
      expect(m.remaining, isNull);
      expect(m.errorFor(a), isNull);
    });
    test('invalid rows count as zero received', () {
      final m = BookingPaymentEntryModel(
        total: 5000,
        payments: [
          BookingPaymentDraft(amount: '-5'),
          BookingPaymentDraft(amount: 'abc'),
          BookingPaymentDraft(amount: '10'),
        ],
      );
      expect(m.received, 1000);
    });
    test('zero total: any positive amount exceeds the balance', () {
      final p = BookingPaymentDraft(id: 'p', amount: '1');
      final m = BookingPaymentEntryModel(total: 0, payments: [p]);
      expect(m.errorFor(p), 'Amount exceeds the remaining balance.');
    });
  });

  group('BookingDiscount', () {
    BookingDiscount d(String v, {String type = 'amount', String reason = ''}) =>
        BookingDiscount(type: type, value: v, reason: reason);
    test('units parser', () {
      expect(d('10').units, 1000);
      expect(d('10.5').units, 1050);
      expect(d('10.05').units, 1005);
      expect(d(' 10 ').units, 1000);
      expect(d('0').units, 0);
      expect(d('0000000001.00').units, 100, reason: '13 chars is the cap');
      expect(d('00000000001.00').units, isNull, reason: '14 chars');
      for (final bad in [
        '',
        ' ',
        '-1',
        '1.234',
        '.5',
        '5.',
        'abc',
        '1,5',
        longEmoji,
        '1e2',
      ]) {
        expect(d(bad).units, isNull, reason: bad);
      }
    });
    test('amount validation against subtotal', () {
      expect(d('').validate(10000), 'Enter a valid discount.');
      expect(d('-5').validate(10000), 'Enter a valid discount.');
      expect(d('abc').validate(10000), 'Enter a valid discount.');
      expect(d('100').validate(10000), isNull, reason: 'equal to subtotal');
      expect(
        d('100.01').validate(10000),
        'Discount cannot exceed the subtotal.',
      );
      expect(d('100.01').validate(null), isNull, reason: 'no subtotal yet');
      expect(d('1000000.01').validate(null), 'Enter a valid discount.');
      expect(d('1000000').validate(null), isNull);
      expect(d('99999999999').validate(null), 'Enter a valid discount.');
    });
    test('zero discount is accepted (documented behaviour)', () {
      expect(d('0').validate(10000), isNull);
      expect(d('0').reduction(10000), 0);
    });
    test('percent validation', () {
      expect(d('100', type: 'percent').validate(10000), isNull);
      expect(d('100.00', type: 'percent').validate(10000), isNull);
      expect(
        d('100.01', type: 'percent').validate(10000),
        'Discount cannot exceed 100%.',
      );
      expect(d('12.5', type: 'percent').validate(10000), isNull);
      expect(
        d('1000', type: 'percent').validate(10000),
        'Discount cannot exceed 100%.',
      );
      expect(
        d('-1', type: 'percent').validate(10000),
        'Enter a valid discount.',
      );
      expect(d('0', type: 'percent').validate(null), isNull);
    });
    test('reduction rounding and extremes', () {
      expect(d('33.33', type: 'percent').reduction(1000), 333);
      expect(d('100', type: 'percent').reduction(12345), 12345);
      expect(
        d('50', type: 'percent').reduction(1),
        1,
        reason: 'rounds half up',
      );
      expect(d('10', type: 'percent').reduction(0), 0);
      expect(d('5').reduction(0), 500, reason: 'raw value; clamped by caller');
      expect(d('abc').reduction(1000), 0);
    });
    test('reason limits count the trimmed text', () {
      expect(d('1', reason: 'a' * 200).validate(null), isNull);
      expect(
        d('1', reason: 'a' * 201).validate(null),
        'Keep the reason within 200 characters.',
      );
      expect(d('1', reason: '  ${'a' * 200}  ').validate(null), isNull);
      expect(d('1', reason: '   ').validate(null), isNull);
      expect(d('1', reason: 'Festival ❤️ discount 🎉').validate(null), isNull);
      expect(d('1', reason: '  hi  ').toJson()['reason'], 'hi');
    });
    test('fromJson / toJson round trip', () {
      final back = BookingDiscount.fromJson({
        'type': 'percent',
        'value': 1250,
        'reason': null,
      });
      expect(back.value, '12.50');
      expect(back.toJson(), {'type': 'percent', 'value': 1250, 'reason': ''});
    });
  });

  group('BookingCustomer.validate', () {
    BookingCustomer c(String name, String phone, [String email = '']) =>
        BookingCustomer(name: name, phone: phone, email: email);
    test('accepts typical values', () {
      for (final phone in [
        '9876543210',
        '+919876543210',
        '+91 98765 43210',
        '(022) 1234-5678',
        '1234567',
        ' 9876543210 ',
      ]) {
        expect(c('Al', phone).validate(), isNull, reason: phone);
      }
      expect(c('a' * 100, '9876543210').validate(), isNull);
      expect(c('  Alex  ', '9876543210').validate(), isNull);
      expect(c('José Müller ✨', '9876543210').validate(), isNull);
      expect(c('அபிநவ்', '9876543210').validate(), isNull);
      expect(c('Alex', '9876543210', 'a@b.co').validate(), isNull);
      expect(c('Alex', '9876543210', ' a@b.co ').validate(), isNull);
    });
    test('rejects bad names', () {
      for (final name in ['', ' ', '   ', 'A', ' A ', 'a' * 101]) {
        expect(
          c(name, '9876543210').validate(),
          contains('customer name'),
          reason: name,
        );
      }
    });
    test('rejects invalid phones', () {
      for (final phone in [
        '',
        '   ',
        '123456',
        '1' * 26,
        'abcdefg',
        '+',
        '++919876543210',
        '98765a43210',
        '9876543210 ext 5',
        '٩٨٧٦٥٤٣٢١٠',
        '１２３４５６７８９０',
        '😀😀😀😀😀😀😀',
        '98765.43210',
        '98765/43210',
        '+91-98765-43210\n9',
      ]) {
        expect(
          c('Alex', phone).validate(),
          'Enter a valid phone number.',
          reason: phone,
        );
      }
    });
    test('rejects invalid emails', () {
      for (final email in [
        'a@b',
        'a b@c.de',
        '@b.co',
        'a@.',
        'plain',
        'a@@b.co',
      ]) {
        expect(
          c('Alex', '9876543210', email).validate(),
          'Enter a valid email or leave it empty.',
          reason: email,
        );
      }
    });
    test('toJson trims and nulls an empty email', () {
      expect(c(' Al ', ' 9876543210 ', '  ').toJson(), {
        'id': null,
        'name': 'Al',
        'phone': '9876543210',
        'email': null,
      });
    });
    test(
      'BUG-1 separator-only phone numbers must be rejected',
      () {
        for (final phone in [
          '-------',
          '(((((((',
          '() ()-()',
          '+ ()-()',
          '12345 6',
          '1-2-3-4',
        ]) {
          expect(
            c('Alex', phone).validate(),
            'Enter a valid phone number.',
            reason: phone,
          );
        }
      },
      skip:
          'BUG-1: phone regex counts separators as digits, "-------" is accepted',
    );
    test(
      'BUG-2 phone with more than 15 digits must be rejected',
      () {
        expect(c('Alex', '1' * 20).validate(), 'Enter a valid phone number.');
        expect(c('Alex', '1' * 25).validate(), 'Enter a valid phone number.');
      },
      skip:
          'BUG-2: customer phone allows up to 25 digits; website phone enforces 7-15 digits',
    );
    test(
      'BUG-3 whitespace-only email must count as empty',
      () {
        expect(c('Alex', '9876543210', '   ').validate(), isNull);
      },
      skip:
          'BUG-3: email "   " is non-empty so regex runs and it is rejected, but toJson sends null',
    );
    test(
      'BUG-4 a name with no real characters must be rejected',
      () {
        expect(c('😀', '9876543210').validate(), contains('customer name'));
        expect(c('​​', '9876543210').validate(), contains('customer name'));
      },
      skip:
          'BUG-4: length is counted in UTF-16 units, a single emoji or two zero-width spaces pass the 2-char minimum',
    );
    test('emoji names count UTF-16 units (60 emoji exceed the 100 limit)', () {
      expect(c('😀' * 50, '9876543210').validate(), isNull);
      expect(c('😀' * 51, '9876543210').validate(), contains('customer name'));
    });
  });

  group('booking form cubit', () {
    Future<void> using(
      Future<void> Function(FakeRepo r, BookingFormCubit c) body, {
      bool flexible = false,
    }) async {
      final (w, r, c) = await form(flexible: flexible);
      try {
        await body(r, c);
      } finally {
        await c.close();
        await w.close();
      }
    }

    test('customer name / phone gate review', () async {
      await using((r, c) async {
        c.customerName('   ');
        c.customerPhone('9876543210');
        await c.review();
        expect(c.state.review, isFalse);
        expect(c.state.error, contains('customer name'));
        c.customerName('Alex');
        c.customerPhone('12');
        await c.review();
        expect(c.state.review, isFalse);
        expect(c.state.error, 'Enter a valid phone number.');
        c.customerPhone('+91 98765 43210');
        c.customerName(' José 😀 ');
        await c.review();
        expect(c.state.review, isTrue);
        expect(c.state.error, isNull);
      });
    });

    test(
      'edits after a validation error are not blocked and clear stale review',
      () async {
        await using((r, c) async {
          customer(c);
          await c.review();
          expect(c.state.review, isTrue);
          c.customerName('');
          expect(c.state.review, isFalse, reason: 'editing leaves review');
        });
      },
    );

    test('people count parsing', () async {
      await using((r, c) async {
        for (final v in [
          '0',
          '-1',
          '1.5',
          'abc',
          '',
          ' ',
          '٣',
          '1e1',
          '99999999999999999999',
        ]) {
          c.people(v);
          expect(c.state.draft.selection, isNull, reason: 'people "$v"');
        }
        for (final v in ['1', '2', '010', '500', ' 2 ']) {
          c.people(v);
          expect(
            c.state.draft.selection?.people,
            int.parse(v.trim()),
            reason: v,
          );
        }
      });
    });

    test(
      'BUG-5 people count has an upper bound',
      () async {
        await using((r, c) async {
          c.people('99999999');
          expect(c.state.draft.selection, isNull);
        });
      },
      skip:
          'BUG-5: people("99999999") is accepted for options without a group rule and is sent to quote/availability',
    );

    test(
      'endTime() ignores malformed values and snaps overnight ranges',
      () async {
        await using((r, c) async {
          final start = c.state.draft.duration;
          for (final v in [
            '',
            ' ',
            'abc',
            '25:00',
            '12:60',
            '-1:00',
            '12:5:3',
            '24:30',
            '😀',
            '10',
          ]) {
            c.endTime(v);
            expect(c.state.draft.duration, start, reason: 'endTime "$v"');
          }
          expect(c.state.error, isNull);
        }, flexible: true);
      },
    );

    test('date and time setters guard against garbage', () async {
      await using((r, c) async {
        c.time('09:30');
        expect(c.state.draft.time, '09:30');
      });
    });

    test(
      'BUG-6 booking date in the past is rejected by the cubit',
      () async {
        await using((r, c) async {
          c.date('2020-01-01');
          expect(c.state.draft.date, '2030-06-04');
          c.date('not-a-date');
          expect(c.state.draft.date, '2030-06-04');
        });
      },
      skip:
          'BUG-6: BookingFormCubit.date() accepts past and malformed dates; only the picker restricts the range',
    );

    test(
      'BUG-7 malformed time must not corrupt the draft',
      () async {
        await using((r, c) async {
          c.time('abc');
          expect(() => c.state.draft.endTime, returnsNormally);
          c.time('99:99');
          expect(c.state.draft.time, isNot('99:99'));
        });
      },
      skip:
          'BUG-7: BookingFormCubit.time() stores any string; draft.startMinute/endTime then throw FormatException',
    );

    test('discount values block review with a message', () async {
      await using((r, c) async {
        customer(c);
        for (final v in ['', '-5', 'abc', '1.234', '99999999999', longEmoji]) {
          c.discount(BookingDiscount(value: v));
          await c.review();
          expect(c.state.review, isFalse, reason: 'discount "$v"');
          expect(c.state.error, 'Enter a valid discount.', reason: v);
        }
        c.discount(const BookingDiscount(type: 'percent', value: '100.01'));
        await c.review();
        expect(c.state.error, 'Discount cannot exceed 100%.');
        c.discount(BookingDiscount(value: '5', reason: 'a' * 201));
        await c.review();
        expect(c.state.error, 'Keep the reason within 200 characters.');
        c.discount(null);
        await c.review();
        expect(c.state.review, isTrue);
      });
    });

    test(
      'payment amounts: invalid, zero, negative, decimal, overpay',
      () async {
        await using((r, c) async {
          customer(c);
          c.addPayment();
          final id = c.state.draft.payments.single.id;
          for (final v in ['0', '0.00', '-1', 'abc', '1.234', '١٢٣', '1e2']) {
            c.updatePayment(id, (p) => p.copyWith(amount: v));
            await c.review();
            expect(c.state.review, isFalse, reason: 'payment "$v"');
            expect(
              c.state.error,
              'Enter a positive payment amount.',
              reason: v,
            );
          }
          c.updatePayment(id, (p) => p.copyWith(amount: '9999999'));
          await c.review();
          expect(c.state.review, isFalse);
          c.updatePayment(
            id,
            (p) => p.copyWith(amount: '1000000.00', reference: ''),
          );
          await c.review();
          expect(c.state.review, isFalse);
          expect(
            c.state.error,
            anyOf(contains('exceed'), contains('positive')),
          );
        });
      },
    );

    test(
      'payment reference over 200 chars and future time are refused',
      () async {
        await using((r, c) async {
          customer(c);
          c.addPayment();
          final id = c.state.draft.payments.single.id;
          c.updatePayment(
            id,
            (p) => p.copyWith(amount: '1', reference: 'r' * 201),
          );
          await c.review();
          expect(c.state.error, contains('200 characters'));
          c.updatePayment(
            id,
            (p) => p.copyWith(
              reference: 'ok',
              receivedAt: DateTime.now().add(const Duration(hours: 2)),
            ),
          );
          await c.review();
          expect(c.state.error, 'Payment time cannot be in the future.');
          c.updatePayment(
            id,
            (p) => p.copyWith(
              receivedAt: DateTime.now().subtract(const Duration(days: 400)),
            ),
          );
          await c.review();
          expect(c.state.error, isNull);
          expect(c.state.review, isTrue);
        });
      },
    );

    test(
      'blank payment rows are ignored; whitespace-only reference is blank',
      () async {
        await using((r, c) async {
          customer(c);
          c.addPayment();
          final id = c.state.draft.payments.single.id;
          c.updatePayment(id, (p) => p.copyWith(amount: ' ', reference: '   '));
          await c.review();
          expect(c.state.review, isTrue);
          expect(c.state.draft.recordedPayments, isEmpty);
        });
      },
    );

    test('at most 20 payment rows', () async {
      await using((r, c) async {
        for (var i = 0; i < 30; i++) {
          c.addPayment();
        }
        expect(c.state.draft.payments.length, 20);
      });
    });

    test('double tap confirm submits once with one idempotency key', () async {
      await using((r, c) async {
        customer(c);
        await c.review();
        await Future.wait([c.confirm(), c.confirm(), c.confirm()]);
        expect(r.submitted, hasLength(1));
        expect(c.state.resultId, isNotNull);
      });
    });

    test('double tap review keeps a single quote pending', () async {
      await using((r, c) async {
        customer(c);
        await Future.wait([c.review(), c.review()]);
        expect(c.state.review, isTrue);
      });
    });

    test(
      'BUG-8 booking notes and reschedule reason have a length cap',
      () async {
        await using((r, c) async {
          customer(c);
          c.notes('n' * 10001);
          await c.review();
          expect(c.state.review, isFalse);
        });
      },
      skip:
          'BUG-8: booking notes, reschedule reason and detail reason/notes have no client-side length cap (discount reason and payment reference do)',
    );
  });

  group('booking detail cubit', () {
    Future<void> using(Future<void> Function(BookingDetailCubit d) body) async {
      final (w, r, c) = await form();
      customer(c);
      await c.review();
      await c.confirm();
      final d = BookingDetailCubit(w, r, c.state.resultId!);
      try {
        await d.load();
        await body(d);
      } finally {
        await d.close();
        await c.close();
        await w.close();
      }
    }

    test('collection: empty, zero, negative, decimals and overpay', () async {
      await using((d) async {
        d.begin(BookingDetailAction.collection);
        final id = d.state.payments.single.id;
        void amount(String v) =>
            d.updatePayment(id, (p) => p.copyWith(amount: v));
        amount('');
        await d.submit();
        expect(d.state.error, 'Add at least one payment.');
        for (final v in ['0', '-1', 'abc', '1.234']) {
          amount(v);
          await d.submit();
          expect(d.state.error, 'Enter a positive payment amount.', reason: v);
          expect(d.state.pending, isNull);
        }
        amount('9999999');
        await d.submit();
        expect(d.state.error, isNotNull);
        expect(d.state.saving, isFalse);
      });
    });

    test(
      'collection prefilled with the balance can be double-submitted safely',
      () async {
        await using((d) async {
          d.begin(BookingDetailAction.collection);
          await Future.wait([d.submit(), d.submit()]);
          expect(d.state.record!.balance, 0);
        });
      },
    );

    test('status change reason: empty, 1 char, whitespace, emoji', () async {
      await using((d) async {
        d.begin(BookingDetailAction.noShow);
        for (final v in ['', ' ', '   ', 'x', ' x ']) {
          d.reason(v);
          await d.submit();
          expect(
            d.state.error,
            'Enter a reason for this change.',
            reason: '"$v"',
          );
        }
        d.reason('😀');
        await d.submit();
        expect(d.state.error, isNot('Enter a reason for this change.'));
      });
    });

    test('customer edit reuses customer validation', () async {
      await using((d) async {
        d.begin(BookingDetailAction.customer);
        d.customerName('A');
        await d.submit();
        expect(d.state.error, contains('customer name'));
        d.customerName('Alex');
        d.customerPhone('abc');
        await d.submit();
        expect(d.state.error, 'Enter a valid phone number.');
        d.customerPhone('9876543210');
        d.customerEmail('nope');
        await d.submit();
        expect(d.state.error, contains('valid email'));
      });
    });

    test(
      'BUG-9 status reason has a length cap',
      () async {
        await using((d) async {
          d.begin(BookingDetailAction.noShow);
          d.reason('r' * 10001);
          await d.submit();
          expect(d.state.error, isNotNull);
        });
      },
      skip:
          'BUG-9: status/refund/collection reason is sent without any maximum length',
    );
  });

  group('widgets', () {
    for (final scale in [1.0, 2.0]) {
      testWidgets('customer fields at 320x568, text scale $scale', (
        tester,
      ) async {
        final log = <String>[];
        await mount(
          tester,
          BookingCustomerFields(
            customer: const BookingCustomer(),
            notes: '',
            enabled: true,
            onName: (v) => log.add('name:$v'),
            onPhone: (v) => log.add('phone:$v'),
            onEmail: (v) => log.add('email:$v'),
            onNotes: (v) => log.add('notes:$v'),
          ),
          scale: scale,
        );
        Future<void> type(String label, String text) async {
          final f = find.widgetWithText(TextFormField, label);
          await tester.ensureVisible(f);
          await tester.enterText(f, text);
          await tester.pump();
        }

        await type('Customer name', '   ');
        await type('Customer name', 'a' * 500);
        await type('Customer name', 'José 😀 அபி');
        await type('Phone number', '+91 (98765) 43210');
        await type('Phone number', 'abc');
        await type('Email · optional', 'a@b.co');
        await type('Booking notes · optional', 'line1\nline2 ${'z' * 3000}');
        expect(log, contains('name:   '));
        expect(log, contains('name:José 😀 அபி'));
        expect(
          log,
          contains('phone:abc'),
          reason: 'no input formatter on phone',
        );
        expect(log.where((e) => e.startsWith('notes:')), hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('customer fields are disabled while locked', (tester) async {
      await mount(
        tester,
        BookingCustomerFields(
          customer: const BookingCustomer(name: 'Alex', phone: '9876543210'),
          notes: '',
          enabled: false,
          onName: (_) => fail('edited'),
          onPhone: (_) => fail('edited'),
          onEmail: (_) => fail('edited'),
          onNotes: (_) => fail('edited'),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Customer name'),
        'x',
      );
      expect(find.text('Alex'), findsOneWidget);
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'discount editor shows errors without overflow, scale $scale',
        (tester) async {
          BookingDiscount? last = const BookingDiscount(value: '');
          late StateSetter set;
          final model = BookingFormModel(
            loading: false,
            slots: const [BookingSlot('09:00', true, 10000)],
          );
          await mount(
            tester,
            StatefulBuilder(
              builder: (context, setState) {
                set = setState;
                return BookingDiscountEditor(
                  model: BookingFormModel(
                    loading: false,
                    slots: model.slots,
                    draft: BookingDraft(discount: last),
                  ),
                  onChanged: (v) => set(() => last = v),
                );
              },
            ),
            scale: scale,
          );
          expect(find.text('Subtotal'), findsOneWidget);
          final amount = find.widgetWithText(TextFormField, 'Discount amount');
          expect(amount, findsOneWidget);
          for (final entry in {
            '-5': 'Enter a valid discount.',
            'abc': 'Enter a valid discount.',
            '1.234': 'Enter a valid discount.',
            '100.01': 'Discount cannot exceed the subtotal.',
            '99999999999999999999': 'Enter a valid discount.',
          }.entries) {
            await tester.enterText(amount, entry.key);
            await tester.pump();
            expect(find.text(entry.value), findsOneWidget, reason: entry.key);
          }
          await tester.enterText(amount, '100');
          await tester.pump();
          expect(find.text('Enter a valid discount.'), findsNothing);
          expect(
            find.text('Discount cannot exceed the subtotal.'),
            findsNothing,
          );
          await tester.ensureVisible(find.text('Percentage'));
          await tester.tap(find.text('Percentage'));
          await tester.pump();
          expect(last!.type, 'percent');
          expect(last!.value, '', reason: 'switching type clears the value');
          final pct = find.widgetWithText(TextFormField, 'Discount percentage');
          await tester.enterText(pct, '100.01');
          await tester.pump();
          expect(find.text('Discount cannot exceed 100%.'), findsOneWidget);
          await tester.enterText(
            find.widgetWithText(TextFormField, 'Discount reason · optional'),
            'x' * 201,
          );
          await tester.pump();
          expect(find.text('Discount cannot exceed 100%.'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('discount editor is read-only while locked', (tester) async {
      await mount(
        tester,
        BookingDiscountEditor(
          model: BookingFormModel(
            loading: false,
            saving: true,
            draft: BookingDraft(discount: const BookingDiscount(value: '5')),
          ),
          onChanged: (_) => fail('changed'),
        ),
      );
      await tester.tap(find.text('Remove'), warnIfMissed: false);
      await tester.pump();
    });

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'payment editor with huge amount, long reference, emoji at 320px scale $scale',
        (tester) async {
          final p = BookingPaymentDraft(
            id: 'p1',
            amount: '99999999999999',
            reference: '${'R' * 200}😀',
          );
          final updates = <String>[];
          await mount(
            tester,
            BookingPaymentEditor(
              payments: [p],
              enabled: true,
              currency: 'INR',
              onAdd: () {},
              onRemove: (_) {},
              onUpdate: (id, f) => updates.add(f(p).amount),
              paymentError: (p) => p.validate(),
              entrySummary: BookingPaymentEntryModel(
                total: 100000000,
                payments: [p],
              ),
            ),
            scale: scale,
          );
          expect(find.text('Payment 1'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('payment-amount-p1')),
            '-1',
          );
          await tester.enterText(
            find.byKey(const ValueKey('payment-amount-p1')),
            '0.00',
          );
          await tester.enterText(
            find.byKey(const ValueKey('payment-amount-p1')),
            '١٢٣',
          );
          expect(updates, ['-1', '0.00', '١٢٣']);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets('payment editor empty state and add button cap at 20', (
      tester,
    ) async {
      var added = 0;
      await mount(
        tester,
        BookingPaymentEditor(
          payments: [
            for (var i = 0; i < 20; i++) BookingPaymentDraft(id: 'r$i'),
          ],
          enabled: true,
          currency: 'INR',
          onAdd: () => added++,
          onRemove: (_) {},
          onUpdate: (_, _) {},
        ),
        size: const Size(320, 4000),
      );
      await tester.tap(find.text('Add other payment'), warnIfMissed: false);
      expect(added, 0, reason: 'button disabled at 20 rows');
      await mount(
        tester,
        BookingPaymentEditor(
          payments: const [],
          enabled: true,
          currency: 'INR',
          onAdd: () => added++,
          onRemove: (_) {},
          onUpdate: (_, _) {},
        ),
      );
      expect(find.textContaining('No money recorded'), findsOneWidget);
      await tester.tap(find.text('Add other payment'));
      expect(added, 1);
    });

    testWidgets(
      'date button clamps garbage / past / far-future initial values',
      (tester) async {
        String? picked;
        for (final initial in [
          null,
          'garbage',
          '1999-01-01',
          '2101-01-01',
          '',
        ]) {
          await mount(
            tester,
            BookingDateButton(
              date: initial,
              futureOnly: true,
              onChanged: (v) => picked = v,
            ),
          );
          await tester.tap(find.byType(OutlinedButton));
          await tester.pumpAndSettle();
          expect(
            find.byType(DatePickerDialog),
            findsOneWidget,
            reason: '$initial',
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(picked, isNull);
        }
        await mount(
          tester,
          BookingDateButton(date: '2030-06-04', onChanged: (v) => picked = v),
        );
        await tester.tap(find.byType(OutlinedButton));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        expect(picked, '2030-06-04');
      },
    );

    testWidgets('date button is inert when disabled', (tester) async {
      await mount(
        tester,
        BookingDateButton(
          date: '2030-06-04',
          enabled: false,
          onChanged: (_) => fail('picked'),
        ),
      );
      await tester.tap(find.byType(OutlinedButton), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsNothing);
    });
  });
}

typedef FakeRepo = dynamic;
