import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/accounts/cubit/accounts_cubits.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/income/cubit/income_cubit.dart';
import 'package:eden_booking/modules/income/cubit/income_state.dart';
import 'package:eden_booking/modules/income/models/income_models.dart';
import 'package:eden_booking/modules/income/repositories/income_repository.dart';
import 'package:eden_booking/modules/income/screens/income_screen.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'accounts_module_test.dart' show qaCatalog, FakeAccountsRepository;
import 'expenses_module_test.dart' show Saver, workspace;

class IncomeRepo extends Fake implements IncomeRepository {
  final events = StreamController<void>.broadcast();
  final filters = <IncomeFilter>[];
  bool failCategories = false, failOverview = false;
  @override
  Stream<void> get changes => events.stream;
  @override
  void refresh() {}
  @override
  Future<FinanceCatalog> financeCatalog() async => qaCatalog;
  @override
  Future<List<IncomeCategory>> categories() async {
    if (failCategories) throw const AppException('Not found');
    return const [
      IncomeCategory('sponsorship', 'Sponsorship'),
      IncomeCategory('events', 'Events'),
      IncomeCategory('old', 'Old stall', active: false),
    ];
  }

  @override
  Future<IncomeSummary> overview(IncomeFilter f) async {
    filters.add(f);
    if (failOverview) throw const AppException('Offline');
    return IncomeSummary(
      total: 85000,
      refunds: 10000,
      count: 3,
      days: {'2026-10-15': 85000},
      sources: const [
        IncomeSourceTotal(incomeBookings, 'Bookings', 65000),
        IncomeSourceTotal('sponsorship', 'Sponsorship', 20000),
      ],
    );
  }

  @override
  Future<IncomePage> list(IncomeFilter f, {int cursor = 0}) async =>
      IncomePage([
        IncomeItem(
          FinanceTransaction(
            id: 'collection',
            kind: 'booking_collection',
            reason: 'Booking payment',
            category: '',
            date: '2026-10-15 10:00:00',
            staff: 'Owner',
            bookingReference: 'BK-1001',
            lines: [FinanceLine('cash', 'Cash drawer', 'cash', 65000)],
          ),
          'Bookings',
        ),
        IncomeItem(
          FinanceTransaction(
            id: 'sponsor',
            kind: 'income',
            reason: 'Tournament sponsor',
            category: 'Sponsorship',
            date: '2026-10-15 09:00:00',
            staff: 'Owner',
            lines: [FinanceLine('bank', 'HDFC', 'upi', 20000)],
          ),
          'Sponsorship',
        ),
      ], null);
  @override
  Future<List<int>> report(IncomeFilter f, String format) async {
    filters.add(f);
    return [1, 2, 3];
  }
}

void main() {
  test('period bounds and query include the selected source', () {
    final f = IncomeFilter(anchor: DateTime(2024, 2, 15));
    expect(f.from, '2024-02-01');
    expect(f.until, '2024-02-29');
    final year = f.copy(yearly: true, source: incomeBookings);
    expect(year.toQuery(), {
      'from': '2024-01-01',
      'until': '2024-12-31',
      'source': 'bookings',
    });
    expect(year.copy(clearSource: true).toQuery().containsKey('source'), false);
  });
  test(
    'income cubit loads totals and exports with the source filter',
    () async {
      final w = await workspace(), r = IncomeRepo(), saver = Saver();
      final c = IncomeCubit(w, r, saver);
      await c.load();
      expect(c.state.summary!.net, 75000);
      expect(c.state.items.length, 2);
      c.setFilter(c.state.filter.copy(source: incomeBookings));
      await Future<void>.delayed(Duration.zero);
      expect(r.filters.last.source, incomeBookings);
      expect(c.state.sourceName, 'Bookings');
      await c.export('xlsx');
      expect(saver.name, 'income-2026-10-01-2026-10-31-source.xlsx');
      await c.close();
      await w.close();
    },
  );
  test(
    'changing period keeps figures while loading and preloads the previous one',
    () async {
      final w = await workspace(), r = IncomeRepo();
      final c = IncomeCubit(w, r, Saver());
      await c.load();
      final states = <IncomeState>[];
      final sub = c.stream.listen(states.add);
      final next = c.state.filter.copy(anchor: DateTime(2026, 11));
      c.setFilter(next);
      await Future<void>.delayed(Duration.zero);
      expect(states.first.loading, isTrue);
      expect(states.first.summary, isNotNull);
      expect(states.first.items, isNotEmpty);
      expect(states.first.filter.from, '2026-11-01');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.state.loading, isFalse);
      expect(r.filters.map((f) => f.from), contains('2026-10-01'));
      r.failOverview = true;
      c.setFilter(next.copy(anchor: DateTime(2026, 12)));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(c.state.error, isNotNull);
      expect(c.state.summary, isNull);
      await sub.cancel();
      await c.close();
      await w.close();
    },
  );
  test('income form picks a managed category and sends its ID', () async {
    final w = await workspace(),
        accounts = FakeAccountsRepository(),
        c = FinanceEntryCubit(w, accounts, 'income', income: IncomeRepo());
    await c.load();
    expect(c.state.incomeCategories.map((c) => c.name), [
      'Sponsorship',
      'Events',
    ]);
    c.incomeCategory('events');
    c.fields(reason: 'Weekend tournament');
    c.line(0, c.state.lines.first.copyWith(amount: '250'));
    await c.save();
    expect(accounts.writes.single['income_category_id'], 'events');
    expect(accounts.writes.single['category'], 'Events');
    await c.close();
    await w.close();
  });
  test('income form keeps typed categories when the server has none', () async {
    final w = await workspace(),
        accounts = FakeAccountsRepository(),
        c = FinanceEntryCubit(
          w,
          accounts,
          'income',
          income: IncomeRepo()..failCategories = true,
        );
    await c.load();
    expect(c.state.error, isNull);
    expect(c.state.incomeCategories, isEmpty);
    c.fields(reason: 'Stall rent', category: 'Rentals');
    c.line(0, c.state.lines.first.copyWith(amount: '100'));
    await c.save();
    expect(accounts.writes.single.containsKey('income_category_id'), false);
    expect(accounts.writes.single['category'], 'Rentals');
    await c.close();
    await w.close();
  });
  for (final dark in [false, true]) {
    testWidgets('income page fits 320px with large text ($dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await workspace(), r = IncomeRepo();
      await getIt.reset();
      getIt.registerFactoryParam<IncomeCubit, WorkspaceSession, void>(
        (s, _) => IncomeCubit(s, r, Saver()),
      );
      final router = GoRouter(
        routes: [GoRoute(path: '/', builder: (c, s) => const IncomeScreen())],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp.router(
              theme: AppTheme.build(dark ? Brightness.dark : Brightness.light),
              routerConfig: router,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Total income'), findsOneWidget);
      expect(find.text('Net after refunds'), findsOneWidget);
      expect(find.text('Add income'), findsOneWidget);
      final scroll = find.byType(Scrollable).first;
      final sponsor = find.textContaining('Sponsorship · Shared');
      await tester.scrollUntilVisible(sponsor, 300, scrollable: scroll);
      expect(tester.takeException(), isNull);
      final bookings = find.text('Bookings');
      await tester.scrollUntilVisible(bookings, -200, scrollable: scroll);
      await tester.tap(bookings);
      await tester.pumpAndSettle();
      expect(r.filters.last.source, incomeBookings);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await w.close();
      await getIt.reset();
    });
  }
}
