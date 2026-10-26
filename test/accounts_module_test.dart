import 'package:eden_booking/modules/accounts/widgets/accounts_overview_widgets.dart'
    show FinanceNetCard, FinanceQuickActions;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/accounts/cubit/accounts_cubits.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/accounts/repositories/accounts_repository.dart';
import 'package:eden_booking/modules/accounts/screens/accounts_screen.dart';
import 'package:eden_booking/modules/accounts/screens/finance_entry_screen.dart';
import 'package:eden_booking/modules/accounts/screens/account_settings_screen.dart';
import 'package:eden_booking/modules/accounts/screens/accounts_reports_screen.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/repositories/booking_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/modules/staff_cash/repositories/staff_cash_repository.dart';
import 'staff_cash_test.dart' show FakeStaffCash;
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;
import 'income_module_test.dart' show IncomeRepo;
import 'package:eden_booking/modules/income/repositories/income_repository.dart';

final qaCatalog = FinanceCatalog(
  name: 'Eden',
  today: '2026-10-15',
  timezone: 'Asia/Kolkata',
  canView: true,
  canManage: true,
  canIncome: true,
  canExpense: true,
  accounts: const [
    MoneyAccount(
      id: 'cash',
      name: 'Cash in hand',
      kind: 'cash',
      balance: 15000,
    ),
    MoneyAccount(
      id: 'bank',
      name: 'HDFC Business',
      kind: 'bank',
      primary: true,
      balance: 50000,
    ),
  ],
  businesses: [
    FinanceBusiness('business', 'Badminton', [
      const FinanceSpace('space', 'Court 1'),
    ]),
  ],
  routes: const [PaymentRoute('business', 'space', 'upi', 'bank')],
);

class FakeAccountsRepository extends Fake implements AccountsRepository {
  final events = StreamController<void>.broadcast();
  final writes = <Map<String, Object?>>[];
  final filters = <FinanceFilter>[];
  bool networkFail = false;
  Completer<FinanceOverview>? delayed;
  @override
  Stream<void> get changes => events.stream;
  @override
  Future<FinanceCatalog> catalog() async => catalogValue;
  FinanceCatalog catalogValue = qaCatalog;
  @override
  Future<FinanceOverview> overview(FinanceFilter f) async {
    filters.add(f);
    final p = delayed;
    delayed = null;
    return p == null ? overviewValue : p.future;
  }

  final overviewValue = FinanceOverview(
    selected: const FinanceTotals(
      collections: 65000,
      income: 65000,
      net: 65000,
      methods: {'cash': 15000, 'upi': 50000},
    ),
    today: const FinanceTotals(
      collections: 65000,
      methods: {'cash': 15000, 'upi': 50000},
    ),
    previous: const FinanceTotals(),
    accounts: qaCatalog.accounts,
    trend: const [FinanceTrend('2026-10', 65000, 0)],
  );
  @override
  Future<FinanceTransactionPage> transactions(
    FinanceFilter f, {
    int cursor = 0,
  }) async => FinanceTransactionPage([], null);
  @override
  Future<void> entry(Map<String, Object?> r) async {
    writes.add(r);
    if (networkFail) {
      throw const AppException('Network interrupted', code: 'NETWORK');
    }
  }

  @override
  Future<void> createBank(Map<String, Object?> r) async {
    writes.add(r);
  }

  @override
  Future<List<int>> report(FinanceFilter f, String type, String format) async =>
      [1, 2, 3];
}

class FakeSaver implements ReportSaver {
  bool result = true;
  int calls = 0;
  @override
  Future<bool> save(List<int> b, String filename) async {
    calls++;
    return result;
  }
}

Future<WorkspaceCubit> session() async {
  final w = WorkspaceCubit(BookingSource());
  await w.load();
  return w;
}

void main() {
  test(
    'report type selects complete year/month and preserves the month anchor',
    () async {
      final w = await session(),
          r = FakeAccountsRepository(),
          c = ReportsCubit(
            w,
            r,
            FakeSaver(),
            const FinanceFilter(from: '2026-02-01', until: '2026-02-15'),
          );
      c.selectType('yearly');
      expect(c.state.filter.from, '2026-01-01');
      expect(c.state.filter.until, '2026-12-31');
      c.selectType('monthly');
      expect(c.state.filter.from, '2026-02-01');
      expect(c.state.filter.until, '2026-02-28');
      c.configure(
        const FinanceFilter(from: '2024-02-01', until: '2024-02-15'),
        'monthly',
      );
      c.selectType('monthly');
      expect(c.state.filter.until, '2024-02-29');
      expect(financeLabel('upi'), 'UPI');
      await c.close();
      await w.close();
    },
  );

  test(
    'finance opening balances support large balances and midnight remains 24:00 in UI',
    () {
      expect(financeOpeningMinor('2500000.50'), 250000050);
      expect(financeOpeningMinor('1.001'), isNull);
      expect(financeStamp('2026-10-15 00:00:00'), '2026-10-15 24:00');
    },
  );
  test('removing a split keeps the remaining amount field identity', () async {
    final w = await session(),
        r = FakeAccountsRepository(),
        c = FinanceEntryCubit(w, r, 'income');
    await c.load();
    c.add();
    final id = c.state.lines[1].id;
    expect(id, isNotEmpty);
    expect(id, isNot(c.state.lines[0].id));
    c.line(1, c.state.lines[1].copyWith(amount: '500'));
    c.remove(0);
    expect(c.state.lines.single.id, id);
    expect(c.state.lines.single.amount, '500');
    await c.close();
    await w.close();
  });

  test('space routing wins and cash always routes to cash', () {
    expect(qaCatalog.destination('upi', 'business', 'space'), 'bank');
    expect(qaCatalog.destination('cash', 'business', 'space'), 'cash');
    expect(qaCatalog.destination('card', null, null), 'bank');
  });
  test(
    'expense form retains split accounts, scope and reason in repository request',
    () async {
      final w = await session(),
          r = FakeAccountsRepository(),
          c = FinanceEntryCubit(w, r, 'expense');
      await c.load();
      c.scope('business', 'space');
      c.fields(category: 'Maintenance', reason: 'Court lighting repair');
      c.line(0, const FinanceDraftLine(accountId: 'cash', amount: '150'));
      c.add();
      c.method(1, 'upi');
      c.line(1, c.state.lines[1].copyWith(amount: '500'));
      await c.save();
      expect(c.state.saved, true);
      expect(r.writes.single['business_id'], 'business');
      expect(r.writes.single['resource_id'], 'space');
      expect((r.writes.single['lines'] as List)[1]['account_id'], 'bank');
      expect(c.total, 65000);
      await c.close();
      await w.close();
    },
  );
  test(
    'transfer needs no category, rejects identical accounts and submits a balanced command',
    () async {
      final w = await session(),
          r = FakeAccountsRepository(),
          c = FinanceEntryCubit(w, r, 'transfer');
      await c.load();
      c.fields(reason: 'Deposit daily collection', toAccountId: 'cash');
      c.line(0, const FinanceDraftLine(accountId: 'cash', amount: '500'));
      await c.save();
      expect(r.writes, isEmpty);
      expect(c.state.category, isEmpty);
      expect(c.state.error, 'Choose two different accounts.');
      c.fields(toAccountId: 'bank');
      await c.save();
      expect(r.writes.single['kind'], 'transfer');
      expect(r.writes.single['category'], 'Transfer');
      expect(r.writes.single['business_id'], null);
      expect(r.writes.single['to_account_id'], 'bank');
      expect(c.state.saved, isTrue);
      await c.close();
      await w.close();
    },
  );
  test('uncertain write retries the exact command and locks editing', () async {
    final w = await session(),
        r = FakeAccountsRepository()..networkFail = true,
        c = FinanceEntryCubit(w, r, 'income');
    await c.load();
    c.fields(category: 'Rental', reason: 'Equipment hire');
    c.line(0, const FinanceDraftLine(accountId: 'cash', amount: '100'));
    await c.save();
    c.fields(reason: 'Changed');
    expect(c.state.reason, 'Equipment hire');
    r.networkFail = false;
    await c.save();
    expect(r.writes[0], r.writes[1]);
    expect(c.state.saved, true);
    await c.close();
    await w.close();
  });
  test('changing the period keeps figures visible while loading', () async {
    final w = await session(),
        r = FakeAccountsRepository(),
        b = FakeBookingRepository(),
        c = AccountsOverviewCubit(w, r, b);
    await c.load();
    final delayed = Completer<FinanceOverview>();
    r.delayed = delayed;
    final f = const FinanceFilter(from: '2026-09-01', until: '2026-09-30');
    final pending = c.load(filter: f);
    await Future<void>.delayed(Duration.zero);
    expect(c.state.loading, isTrue);
    expect(c.state.filter, f);
    expect(c.state.overview, isNotNull);
    delayed.complete(r.overviewValue);
    await pending;
    expect(c.state.loading, isFalse);
    await c.close();
    await w.close();
  });
  test('late overview response cannot overwrite a newer date filter', () async {
    final w = await session(),
        r = FakeAccountsRepository(),
        b = FakeBookingRepository(),
        c = AccountsOverviewCubit(w, r, b);
    final delayed = Completer<FinanceOverview>();
    r.delayed = delayed;
    final old = c.load();
    await Future<void>.delayed(Duration.zero);
    final f = const FinanceFilter(from: '2026-09-01', until: '2026-09-30');
    await c.load(filter: f);
    delayed.complete(r.overviewValue);
    await old;
    expect(c.state.filter, f);
    await c.close();
    await w.close();
  });
  test(
    'bank creation validates amount and reports preserve cancellation state',
    () async {
      final w = await session(),
          r = FakeAccountsRepository(),
          bank = BankAccountCubit(w, r);
      bank.update(
        name: 'HDFC Business',
        accountNumber: '001234561234',
        opening: 'not money',
      );
      await bank.save();
      expect(r.writes, isEmpty);
      bank.update(opening: '5000', accountNumber: '12345');
      await bank.save();
      expect(r.writes, isEmpty);
      bank.update(accountNumber: '001234561234');
      bank.update(opening: '5000');
      await bank.save();
      expect(r.writes.single['opening_minor'], 500000);
      expect(r.writes.single['account_number'], '001234561234');
      final saver = FakeSaver()..result = false,
          c = ReportsCubit(
            w,
            r,
            saver,
            const FinanceFilter(from: '2026-10-01', until: '2026-10-15'),
          );
      await c.download('pdf');
      expect(c.state.message, 'Download cancelled.');
      await bank.close();
      await c.close();
      await w.close();
    },
  );
  for (final width in const [1000.0, 1440.0]) {
    testWidgets('overview shows the wide dashboard at ${width}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await session();
      await getIt.reset();
      registerFeatureDependencies(getIt);
      getIt.unregister<AccountsRepository>();
      getIt.registerSingleton<AccountsRepository>(FakeAccountsRepository());
      getIt.unregister<BookingRepository>();
      getIt.registerSingleton<BookingRepository>(FakeBookingRepository());
      getIt.unregister<IncomeRepository>();
      getIt.registerSingleton<IncomeRepository>(IncomeRepo());
      getIt.unregister<IStaffCashRepository>();
      getIt.registerSingleton<IStaffCashRepository>(FakeStaffCash());
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (c, s) => const AccountsScreen())],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: Size(width, 1400),
            builder: (c, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.dark),
              routerConfig: router,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Net cash flow'), findsOneWidget);
      expect(find.text('Booking dues'), findsOneWidget);
      expect(find.text('Income & expenses'), findsOneWidget);
      expect(find.text("Today's collection"), findsOneWidget);
      await w.close();
    });
  }
  for (final screen in [
    'overview',
    'settings',
    'income',
    'transfer',
    'reports',
  ]) {
    testWidgets('$screen is usable at 320px with enlarged text', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await session(), r = FakeAccountsRepository();
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
      final page = switch (screen) {
        'overview' => const AccountsScreen(),
        'settings' => const AccountSettingsScreen(),
        'income' => const FinanceEntryScreen(kind: 'income'),
        'transfer' => const FinanceEntryScreen(kind: 'transfer'),
        _ => const AccountsReportsScreen(
          filter: FinanceFilter(from: '2026-10-01', until: '2026-10-15'),
        ),
      };
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (c, s) => page)],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.dark),
              routerConfig: router,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: const TextScaler.linear(1.4)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (screen == 'transfer') {
        expect(find.text('Category'), findsNothing);
        expect(find.text('Reason for transfer'), findsOneWidget);
      }
      if (screen == 'settings') {
        final scroll = find.byType(Scrollable).first;
        final menu = find.byTooltip('Manage HDFC Business');
        await tester.scrollUntilVisible(menu, 200, scrollable: scroll);
        await tester.tap(menu);
        await tester.pumpAndSettle();
        expect(find.text('Rename'), findsOneWidget);
        expect(find.text('Set as primary'), findsNothing);
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        expect(find.text('Rename bank account'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(r.writes, isEmpty);
        final business = find.text('Badminton');
        await tester.scrollUntilVisible(business, 200, scrollable: scroll);
        await tester.tap(business);
        await tester.pumpAndSettle();
        final space = find.text('Court 1');
        await tester.scrollUntilVisible(space, 150, scrollable: scroll);
        await tester.tap(space);
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('Individual space settings'),
          120,
          scrollable: scroll,
        );
        expect(find.text('Business default'), findsOneWidget);
        expect(find.byType(AppPicker), findsNWidgets(6));
        expect(tester.takeException(), isNull);
      }
      for (var i = 0; i < 8; i++) {
        final scroll = find.byType(Scrollable).first;
        await tester.drag(scroll, const Offset(0, -420));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        if (screen == 'overview') {
          expect(find.byType(FinanceNetCard), findsOneWidget);
          expect(find.byType(FinanceQuickActions), findsOneWidget);
          expect(find.byType(FloatingActionButton), findsNothing);
        }
      }
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await w.close();
      await getIt.reset();
    });
  }
  test(
    'booking payment account is serialized and cleared when method changes',
    () {
      final p = BookingPaymentDraft(
        method: 'upi',
        accountId: 'bank',
        amount: '500',
      );
      expect(p.toJson()['account_id'], 'bank');
      expect(p.copyWith(method: 'cash').accountId, isNull);
    },
  );
}
