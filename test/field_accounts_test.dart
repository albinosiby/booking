import 'dart:async';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/accounts/cubit/accounts_cubits.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/accounts/repositories/accounts_repository.dart';
import 'package:eden_booking/modules/accounts/screens/account_settings_screen.dart';
import 'package:eden_booking/modules/accounts/screens/accounts_reports_screen.dart';
import 'package:eden_booking/modules/accounts/screens/accounts_screen.dart';
import 'package:eden_booking/modules/accounts/screens/finance_entry_screen.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/modules/income/repositories/income_repository.dart';
import 'package:eden_booking/modules/staff_cash/repositories/staff_cash_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'accounts_module_test.dart' show FakeAccountsRepository, qaCatalog, session;
import 'booking_module_test.dart' show FakeBookingRepository;
import 'income_module_test.dart' show IncomeRepo;
import 'staff_cash_test.dart' show FakeStaffCash;

class SlowAccounts extends FakeAccountsRepository {
  final gate = Completer<void>();
  @override
  Future<void> entry(Map<String, Object?> r) async {
    writes.add(r);
    await gate.future;
  }

  @override
  Future<void> createBank(Map<String, Object?> r) async {
    writes.add(r);
    await gate.future;
  }
}

class FailingCatalog extends FakeAccountsRepository {
  @override
  Future<FinanceCatalog> catalog() async => throw const AppException('Server down', code: 'NETWORK');
}

class CashAccounts extends FakeAccountsRepository {
  @override
  Future<void> cashOpening(Map<String, Object?> r) async => writes.add(r);
}

class RejectingAccounts extends FakeAccountsRepository {
  RejectingAccounts(this.code);
  final String code;
  @override
  Future<void> entry(Map<String, Object?> r) async {
    writes.add(r);
    throw AppException('Rejected', code: code);
  }

  @override
  Future<void> createBank(Map<String, Object?> r) async {
    writes.add(r);
    throw AppException('Rejected', code: code);
  }
}

Future<FinanceEntryCubit> entry(
  String kind,
  FakeAccountsRepository r, {
  String reason = 'Court lighting',
  String category = 'Maintenance',
  String amount = '100',
}) async {
  final w = await session();
  final c = FinanceEntryCubit(w, r, kind);
  addTearDown(() async {
    await c.close();
    await w.close();
  });
  await c.load();
  c.fields(reason: reason, category: category, toAccountId: 'bank');
  c.line(0, FinanceDraftLine(accountId: 'cash', amount: amount));
  return c;
}

void main() {
  group('financeOpeningMinor', () {
    test('valid', () {
      expect(financeOpeningMinor('0'), 0);
      expect(financeOpeningMinor('0.5'), 50);
      expect(financeOpeningMinor('12.34'), 1234);
      expect(financeOpeningMinor('1000000000'), 100000000000);
    });
    test('invalid', () {
      for (final v in ['', ' ', '-1', '+1', '1e3', '1.001', '.5', '5.', '1,000', '٣', '💰', '12345678901', '1000000000.01', ' 5', '5 ']) {
        expect(financeOpeningMinor(v), isNull, reason: '"$v"');
      }
    });
    test('very long digit strings do not throw', () {
      expect(financeOpeningMinor('9' * 500), isNull);
    });
  });

  group('FinanceFilter search query', () {
    FinanceFilter f(String q) => const FinanceFilter(from: '2026-10-01', until: '2026-10-15').search(q, null);
    test('plain query is sent as given', () {
      expect(f('court 1').toJson()['q'], 'court 1');
      expect(f('🏸 Zoë').toJson()['q'], '🏸 Zoë');
    });
    test('empty query is omitted', () {
      expect(f('').toJson().containsKey('q'), isFalse);
    });
    test('whitespace-only and padded queries are normalised like income/expense filters', () {
      expect(f('   ').toJson().containsKey('q'), isFalse);
      expect(f('  court 1 ').toJson()['q'], 'court 1');
    }, skip: 'BUG-11: FinanceFilter.toJson sends untrimmed/whitespace-only q (Income/Expense filters trim); whitespace query also hides the Staff cash section');
    test('query longer than the server limit of 100 is truncated or rejected client-side', () {
      final q = f('a' * 150).toJson()['q'] as String?;
      expect(q == null || q.length <= 100, isTrue);
    }, skip: 'BUG-11: transactions search field has no maxLength; server rejects q over 100 characters');
  });

  group('financeMoney formatting', () {
    test('rounding and sign', () {
      expect(financeMoney(0, 'INR'), '₹ 0.00');
      expect(financeMoney(1, 'INR'), '₹ 0.01');
      expect(financeMoney(1999, 'INR'), '₹ 19.99');
      expect(financeMoney(-5, 'INR'), '₹ -0.05');
      expect(financeMoney(100000000, 'INR'), '₹ 1000000.00');
      expect(financeMoney(100000000000, 'INR'), '₹ 1000000000.00');
      expect(financeMoney(1234, 'USD'), 'USD 12.34');
    });
  });

  group('FinanceEntryCubit amount matrix (expense)', () {
    for (final ok in {'1': 100, '0.01': 1, '19.99': 1999, '0.29': 29, '1.15': 115, '4.35': 435, '100.5': 10050, ' 25 ': 2500, '1000000': 100000000}.entries) {
      test('"${ok.key}" -> ${ok.value} minor', () async {
        final r = FakeAccountsRepository();
        final c = await entry('expense', r, amount: ok.key);
        await c.save();
        expect(c.state.error, isNull);
        expect((r.writes.single['lines'] as List)[0]['amount_minor'], ok.value);
      });
    }
    for (final bad in ['', ' ', '0', '0.00', '-1', '-0.01', '1.001', '1e3', 'abc', '💰', '١٠', '1000000.01', '99999999999999999999', '1,5', '.', '+5', '0x10']) {
      test('"$bad" is rejected without calling the server', () async {
        final r = FakeAccountsRepository();
        final c = await entry('expense', r, amount: bad);
        await c.save();
        expect(r.writes, isEmpty);
        expect(c.state.error, isNotNull);
        expect(c.state.saved, isFalse);
      });
    }
    test('a zero split line rejects the whole entry', () async {
      final r = FakeAccountsRepository();
      final c = await entry('expense', r, amount: '10');
      c.add();
      c.line(1, c.state.lines[1].copyWith(amount: '0'));
      await c.save();
      expect(r.writes, isEmpty);
    });
    test('split lines sum exactly, no float drift', () async {
      final r = FakeAccountsRepository();
      final c = await entry('expense', r, amount: '0.10');
      c.add();
      c.line(1, c.state.lines[1].copyWith(amount: '0.20'));
      expect(c.total, 30);
      c.add();
      c.line(2, c.state.lines[2].copyWith(amount: '0.07'));
      expect(c.total, 37);
    });
    test('split lines are capped at 20', () async {
      final r = FakeAccountsRepository();
      final c = await entry('expense', r);
      for (var i = 0; i < 40; i++) {
        c.add();
      }
      expect(c.state.lines.length, 20);
    });
    test('the last split line cannot be removed', () async {
      final c = await entry('expense', FakeAccountsRepository());
      c.remove(0);
      expect(c.state.lines.length, 1);
    });
    test('split totals above the server ceiling are accepted client-side', () async {
      final r = FakeAccountsRepository();
      final c = await entry('expense', r, amount: '1000000');
      c.add();
      c.line(1, c.state.lines[1].copyWith(amount: '1000000', accountId: 'cash'));
      await c.save();
      expect(c.total, 200000000);
    });
  });

  group('FinanceEntryCubit text fields', () {
    test('reason and category: empty, whitespace, one character', () async {
      for (final bad in ['', ' ', '   ', 'a', ' a ', '\n\t ']) {
        final r = FakeAccountsRepository();
        var c = await entry('expense', r, reason: bad);
        await c.save();
        expect(r.writes, isEmpty, reason: 'reason "$bad"');
        c = await entry('expense', r, category: bad);
        await c.save();
        expect(r.writes, isEmpty, reason: 'category "$bad"');
      }
    });
    test('two characters accepted and trimmed in the command', () async {
      final r = FakeAccountsRepository();
      final c = await entry('expense', r, reason: '  ab  ', category: ' cd ');
      c.fields(reference: '  ref 1  ');
      await c.save();
      expect(r.writes.single['reason'], 'ab');
      expect(r.writes.single['category'], 'cd');
      expect(r.writes.single['reference'], 'ref 1');
    });
    test('unicode, emoji and markup pass through untouched', () async {
      final r = FakeAccountsRepository();
      final c = await entry('expense', r, reason: '修理 💡 <b>x</b> "q" \'s', category: 'Zoë ☕');
      await c.save();
      expect(r.writes.single['reason'], '修理 💡 <b>x</b> "q" \'s');
      expect(r.writes.single['category'], 'Zoë ☕');
    });
    test('reason over 500, category over 80, reference over 200 are blocked client-side', () async {
      final r = FakeAccountsRepository();
      var c = await entry('expense', r, reason: 'a' * 501);
      await c.save();
      expect(r.writes, isEmpty, reason: 'reason 501');
      c = await entry('expense', r, category: 'a' * 81);
      await c.save();
      expect(r.writes, isEmpty, reason: 'category 81');
      c = await entry('expense', r);
      c.fields(reference: 'a' * 201);
      await c.save();
      expect(r.writes, isEmpty, reason: 'reference 201');
    }, skip: 'BUG-8: finance entry reason/category/reference have no client length limit or maxLength; server rejects reason>500, category>80, reference>200');
    test('boundary lengths are accepted', () async {
      final r = FakeAccountsRepository();
      final c = await entry('expense', r, reason: 'a' * 500, category: 'b' * 80);
      c.fields(reference: 'c' * 200);
      await c.save();
      expect(r.writes.length, 1);
    });
    test('income without category rejected', () async {
      final r = FakeAccountsRepository();
      final c = await entry('income', r, category: '');
      await c.save();
      expect(r.writes, isEmpty);
    });
    test('transfer ignores category but needs reason and different accounts', () async {
      final r = FakeAccountsRepository();
      var c = await entry('transfer', r, category: '', reason: 'x');
      await c.save();
      expect(r.writes, isEmpty);
      c = await entry('transfer', r, category: '');
      c.fields(toAccountId: 'cash');
      await c.save();
      expect(r.writes, isEmpty);
      expect(c.state.error, 'Choose two different accounts.');
      c = await entry('transfer', r, category: '');
      await c.save();
      expect(r.writes.single['category'], 'Transfer');
    });
  });

  group('FinanceEntryCubit submission safety', () {
    test('double tap while the request is in flight sends one command', () async {
      final r = SlowAccounts();
      final c = await entry('expense', r);
      final a = c.save();
      final b = c.save();
      await Future<void>.delayed(Duration.zero);
      expect(r.writes.length, 1);
      r.gate.complete();
      await Future.wait([a, b]);
      expect(r.writes.length, 1);
      expect(c.state.saved, isTrue);
    });
    test('fields are locked while pending', () async {
      final r = SlowAccounts();
      final c = await entry('expense', r);
      final f = c.save();
      c.fields(reason: 'changed');
      c.line(0, const FinanceDraftLine(accountId: 'cash', amount: '999'));
      expect(c.state.reason, 'Court lighting');
      r.gate.complete();
      await f;
    });
    test('network failure keeps the same command key for the retry', () async {
      final r = FakeAccountsRepository()..networkFail = true;
      final c = await entry('expense', r);
      await c.save();
      r.networkFail = false;
      await c.save();
      expect(r.writes.length, 2);
      expect(r.writes[0]['command_key'], r.writes[1]['command_key']);
    });
    test('validation rejection unlocks editing so the user can fix it', () async {
      final r = RejectingAccounts('VALIDATION_ERROR');
      final c = await entry('expense', r);
      await c.save();
      expect(c.pending, isNull);
      c.fields(reason: 'Fixed reason');
      expect(c.state.reason, 'Fixed reason');
    });
    test('scope change re-routes accounts per method', () async {
      final r = FakeAccountsRepository();
      final c = await entry('expense', r);
      c.method(0, 'upi');
      expect(c.state.lines.first.accountId, 'bank');
      c.method(0, 'cash');
      expect(c.state.lines.first.accountId, 'cash');
    });
  });

  group('BankAccountCubit', () {
    Future<BankAccountCubit> bank(FakeAccountsRepository r, {bool cash = false}) async {
      final w = await session();
      final c = BankAccountCubit(w, r, cash: cash);
      addTearDown(() async {
        await c.close();
        await w.close();
      });
      return c;
    }

    void fill(BankAccountCubit c, {String name = 'HDFC', String bank = 'HDFC Bank', String number = '123456', String opening = '0'}) =>
        c.update(name: name, bank: bank, accountNumber: number, opening: opening);

    test('account number must be 6 to 34 ASCII digits', () async {
      for (final bad in ['', '12345', '1' * 35, '12345a', '12 3456', '١٢٣٤٥٦', '12-3456', '1234.56', '💰💰💰💰💰💰']) {
        final r = FakeAccountsRepository();
        final c = await bank(r);
        fill(c, number: bad);
        await c.save();
        expect(r.writes, isEmpty, reason: '"$bad"');
      }
      for (final ok in ['123456', '1' * 34, ' 123456 ']) {
        final r = FakeAccountsRepository();
        final c = await bank(r);
        fill(c, number: ok);
        await c.save();
        expect(r.writes.length, 1, reason: '"$ok"');
        expect(r.writes.single['account_number'], ok.trim());
      }
    });
    test('name 2 characters minimum, trimmed', () async {
      for (final bad in ['', ' ', 'a', ' a ']) {
        final r = FakeAccountsRepository();
        final c = await bank(r);
        fill(c, name: bad);
        await c.save();
        expect(r.writes, isEmpty, reason: '"$bad"');
      }
      final r = FakeAccountsRepository();
      final c = await bank(r);
      fill(c, name: '  Zoë 🏦  ');
      await c.save();
      expect(r.writes.single['name'], 'Zoë 🏦');
    });
    test('opening balance matrix', () async {
      final cases = {'0': 0, '0.00': 0, '100': 10000, '100.5': 10050, '-250.75': -25075, ' 12 ': 1200, '-0': 0, '1000000000': 100000000000, '-1000000000': -100000000000};
      for (final e in cases.entries) {
        final r = FakeAccountsRepository();
        final c = await bank(r);
        fill(c, opening: e.key);
        await c.save();
        expect(r.writes.single['opening_minor'], e.value, reason: e.key);
      }
      for (final bad in ['', ' ', 'abc', '1.001', '--5', '+5', '1e3', '٣', '1000000000.01', '12345678901', '-']) {
        final r = FakeAccountsRepository();
        final c = await bank(r);
        fill(c, opening: bad);
        await c.save();
        expect(r.writes, isEmpty, reason: '"$bad"');
      }
    });
    test('negative zero does not leak as -0 minor', () async {
      final r = FakeAccountsRepository();
      final c = await bank(r);
      fill(c, opening: '-0');
      await c.save();
      expect(r.writes.single['opening_minor'], isNot(isA<double>()));
      expect(r.writes.single['opening_minor'].toString(), '0');
    });
    test('name and bank over 100 characters are blocked client-side', () async {
      var r = FakeAccountsRepository();
      var c = await bank(r);
      fill(c, name: 'a' * 101);
      await c.save();
      expect(r.writes, isEmpty, reason: 'name 101');
      r = FakeAccountsRepository();
      c = await bank(r);
      fill(c, bank: 'b' * 101);
      await c.save();
      expect(r.writes, isEmpty, reason: 'bank 101');
    }, skip: 'BUG-9: BankAccountScreen/BankAccountCubit accept name/bank name over 100 chars (server limit is 100); no maxLength on fields');
    test('bank name optional', () async {
      final r = FakeAccountsRepository();
      final c = await bank(r);
      fill(c, bank: '');
      await c.save();
      expect(r.writes.length, 1);
    });
    test('cash opening ignores name and account number', () async {
      final r = CashAccounts();
      final c = await bank(r, cash: true);
      c.update(opening: '500');
      await c.save();
      expect(r.writes.length, 1);
      expect(r.writes.single.keys.toSet(), {'command_key', 'opening_minor', 'opening_at'});
    });
    test('double tap sends the bank account once', () async {
      final r = SlowAccounts();
      final c = await bank(r);
      fill(c);
      final a = c.save();
      final b = c.save();
      await Future<void>.delayed(Duration.zero);
      expect(r.writes.length, 1);
      r.gate.complete();
      await Future.wait([a, b]);
      expect(c.state.saved, isTrue);
    });
    test('validation rejection unlocks the form; other errors keep the same command', () async {
      final r = RejectingAccounts('VALIDATION_ERROR');
      final c = await bank(r);
      fill(c);
      await c.save();
      expect(c.pending, isNull);
      final r2 = RejectingAccounts('NETWORK');
      final c2 = await bank(r2);
      fill(c2);
      await c2.save();
      final first = c2.pending!['command_key'];
      await c2.save();
      expect(r2.writes[0]['command_key'], first);
      expect(r2.writes[1]['command_key'], first);
    });
  });

  group('Account screens at 320x568 with 2.0 text', () {
    Future<void> pump(WidgetTester tester, Widget page, FakeAccountsRepository r, {double scale = 2.0, Size size = const Size(320, 568)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await session();
      addTearDown(w.close);
      await getIt.reset();
      registerFeatureDependencies(getIt);
      getIt.unregister<AccountsRepository>();
      getIt.registerSingleton<AccountsRepository>(r);
      getIt.unregister<BookingRepository>();
      getIt.registerSingleton<BookingRepository>(FakeBookingRepository());
      getIt.unregister<IncomeRepository>();
      getIt.registerSingleton<IncomeRepository>(IncomeRepo());
      getIt.unregister<IStaffCashRepository>();
      getIt.registerSingleton<IStaffCashRepository>(FakeStaffCash());
      addTearDown(getIt.reset);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (c, s) => const Scaffold()),
          GoRoute(path: '/page', builder: (c, s) => page),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.dark),
              routerConfig: router,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      unawaited(router.push('/page'));
      await tester.pumpAndSettle();
    }

    for (final kind in ['income', 'expense', 'transfer']) {
      testWidgets('$kind entry form: no overflow, rejects empty save', (tester) async {
        final r = FakeAccountsRepository();
        await pump(tester, FinanceEntryScreen(kind: kind), r);
        expect(tester.takeException(), isNull);
        final save = find.byType(AppButton).last;
        await tester.ensureVisible(save);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(r.writes, isEmpty);
        expect(find.textContaining('Enter a'), findsWidgets);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('expense entry: typed values reach the repository once on double tap', (tester) async {
      final r = FakeAccountsRepository();
      await pump(tester, const FinanceEntryScreen(kind: 'expense'), r, scale: 1.0);
      await tester.enterText(find.widgetWithText(TextFormField, 'Category'), 'Repairs');
      await tester.enterText(find.widgetWithText(TextFormField, 'Reason for expense'), 'Net replacement');
      await tester.enterText(find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('finance-amount') == true), '12.50');
      final save = find.text('Record expense');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(r.writes.length, 1);
      expect((r.writes.single['lines'] as List)[0]['amount_minor'], 1250);
    });

    testWidgets('entry form shows an error with retry when the catalog fails to load', (tester) async {
      await pump(tester, const FinanceEntryScreen(kind: 'income'), FailingCatalog(), scale: 1.0);
      expect(find.byType(AppErrorWidget), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('bank account form: invalid input shows an error and sends nothing', (tester) async {
      final r = FakeAccountsRepository();
      await pump(tester, const BankAccountScreen(), r);
      expect(tester.takeException(), isNull);
      final save = find.text('Save bank account');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(r.writes, isEmpty);
      expect(find.textContaining('account number (6–34 digits)'), findsOneWidget);
    });

    testWidgets('cash opening balance form fits', (tester) async {
      await pump(tester, const BankAccountScreen(cash: true), FakeAccountsRepository());
      expect(tester.takeException(), isNull);
    });

    testWidgets('BUG-12: overview net card does not overflow at 320px / 2.0 text', (tester) async {
      await pump(tester, const AccountsScreen(), FakeAccountsRepository());
      expect(tester.takeException(), isNull);
    }, skip: true); // BUG-12: FinanceNetCard Row overflows by up to 88px (accounts_overview_widgets.dart:284)
    for (final name in ['settings', 'reports']) {
      testWidgets('$name fits', (tester) async {
        final page = switch (name) {
          'settings' => const AccountSettingsScreen(),
          _ => const AccountsReportsScreen(filter: FinanceFilter(from: '2026-10-01', until: '2026-10-15')),
        };
        await pump(tester, page, FakeAccountsRepository());
        expect(tester.takeException(), isNull);
      });
    }
  });
}
