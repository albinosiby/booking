import 'dart:async';

import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/accounts/widgets/finance_period_widgets.dart';
import 'package:eden_booking/modules/expenses/cubit/expenses_cubit.dart';
import 'package:eden_booking/modules/expenses/models/expense_models.dart';
import 'package:eden_booking/modules/expenses/repositories/expense_mapper.dart';
import 'package:eden_booking/modules/expenses/screens/expenses_screen.dart';
import 'package:eden_booking/modules/income/cubit/income_cubit.dart';
import 'package:eden_booking/modules/income/models/income_models.dart';
import 'package:eden_booking/modules/income/screens/income_screen.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'expenses_module_test.dart' show ExpenseRepo, Saver, workspace;
import 'income_module_test.dart' show IncomeRepo;

class DayExpenseRepo extends ExpenseRepo {
  final requests = <({ExpenseFilter filter, int cursor})>[];
  bool failList = false;
  Completer<ExpensePage>? pendingMore;

  @override
  Future<ExpenseSummary> overview(ExpenseFilter f) async =>
      ExpenseSummary(60000, 3, {'2026-10-15': 30000, '2026-10-16': 30000}, []);

  @override
  Future<ExpensePage> list(ExpenseFilter f, {int cursor = 0}) async {
    requests.add((filter: f, cursor: cursor));
    if (failList) throw const AppException('Could not load expenses');
    if (cursor > 0 && pendingMore != null) return pendingMore!.future;
    final items =
        [
              for (final (id, day, amount) in [
                ('First expense', 15, 10000),
                ('Second expense', 15, 20000),
                ('Other day expense', 16, 30000),
              ])
                ExpenseItem(
                  id: id,
                  reason: id,
                  category: 'Food',
                  date: '2026-10-$day',
                  amount: amount,
                ),
            ]
            .where(
              (i) =>
                  i.date.compareTo(f.from) >= 0 &&
                  i.date.compareTo(f.until) <= 0,
            )
            .toList();
    if (f.day == null) return ExpensePage(items, null);
    return ExpensePage(
      items.skip(cursor).take(1).toList(),
      cursor + 1 < items.length ? cursor + 1 : null,
    );
  }
}

class DayIncomeRepo extends IncomeRepo {
  final requests = <({IncomeFilter filter, int cursor})>[];
  bool failList = false;
  Completer<IncomePage>? pendingMore;

  @override
  Future<IncomeSummary> overview(IncomeFilter f) async => IncomeSummary(
    total: 60000,
    refunds: 0,
    count: 3,
    days: {'2026-10-15': 30000, '2026-10-16': 30000},
  );

  @override
  Future<IncomePage> list(IncomeFilter f, {int cursor = 0}) async {
    requests.add((filter: f, cursor: cursor));
    if (failList) throw const AppException('Could not load income');
    if (cursor > 0 && pendingMore != null) return pendingMore!.future;
    final items =
        [
              for (final (id, day, amount) in [
                ('First income', 15, 10000),
                ('Second income', 15, 20000),
                ('Other day income', 16, 30000),
              ])
                IncomeItem(
                  FinanceTransaction(
                    id: id,
                    kind: 'income',
                    reason: id,
                    category: 'Sponsorship',
                    date: '2026-10-$day 10:00:00',
                    staff: 'Owner',
                    lines: [FinanceLine('cash', 'Cash', 'cash', amount)],
                  ),
                  'Sponsorship',
                ),
            ]
            .where(
              (i) =>
                  i.entry.date.substring(0, 10).compareTo(f.from) >= 0 &&
                  i.entry.date.substring(0, 10).compareTo(f.until) <= 0,
            )
            .toList();
    if (f.day == null) return IncomePage(items, null);
    return IncomePage(
      items.skip(cursor).take(1).toList(),
      cursor + 1 < items.length ? cursor + 1 : null,
    );
  }
}

void main() {
  test(
    'single-day query bounds retain the existing expense and income scope',
    () {
      final expense = ExpenseFilter(
        anchor: DateTime(2024, 2),
        categoryId: 'food',
        businessId: 'business',
        spaceId: 'space',
        accountId: 'bank',
        query: 'bill',
      ).copy(day: 29);
      expect(ExpenseMapper.filter(expense), {
        'from': '2024-02-29',
        'until': '2024-02-29',
        'category_id': 'food',
        'business_id': 'business',
        'resource_id': 'space',
        'account_id': 'bank',
        'q': 'bill',
      });
      final income = IncomeFilter(
        anchor: DateTime(2024, 2),
        source: incomeBookings,
        businessId: 'business',
        spaceId: 'space',
        accountId: 'bank',
        query: 'payment',
      ).copy(day: 29);
      expect(income.toQuery(), {
        'from': '2024-02-29',
        'until': '2024-02-29',
        'source': 'bookings',
        'business_id': 'business',
        'resource_id': 'space',
        'account_id': 'bank',
        'q': 'payment',
      });
    },
  );

  test(
    'expense day selection paginates, refreshes, clears and resets by period',
    () async {
      final w = await workspace(), r = DayExpenseRepo();
      final c = ExpensesCubit(w, r, Saver());
      addTearDown(() async {
        await c.close();
        await w.close();
        await r.events.close();
      });
      await c.load(
        filter: ExpenseFilter(anchor: DateTime(2026, 10), categoryId: 'food'),
      );
      await c.selectDay(15);
      expect(c.state.summary!.total, 60000);
      expect(c.state.filter.from, '2026-10-01');
      expect(r.requests.last.filter.from, '2026-10-15');
      expect(r.requests.last.filter.until, '2026-10-15');
      expect(r.requests.last.filter.categoryId, 'food');
      expect(c.state.items.single.reason, 'First expense');
      await c.more();
      expect(r.requests.last.cursor, 1);
      expect(r.requests.last.filter.from, '2026-10-15');
      expect(c.state.items.map((i) => i.reason), [
        'First expense',
        'Second expense',
      ]);
      await c.load(refresh: true);
      expect(c.state.selectedDay, 15);
      await c.load(filter: c.state.filter.copy(accountId: 'bank'));
      expect(c.state.selectedDay, 15);
      expect(r.requests.last.filter.accountId, 'bank');
      await c.selectDay(17);
      expect(c.state.items, isEmpty);
      await c.selectDay(null);
      expect(c.state.selectedDay, isNull);
      expect(c.state.items.length, 3);
      await c.selectDay(31);
      await c.load(filter: c.state.filter.copy(anchor: DateTime(2026, 11)));
      expect(c.state.selectedDay, isNull);
      await c.selectDay(31);
      expect(c.state.selectedDay, isNull);
      await c.selectDay(15);
      await c.load(filter: c.state.filter.copy(yearly: true));
      expect(c.state.selectedDay, isNull);
    },
  );

  test(
    'income day selection paginates, refreshes, clears and resets by period',
    () async {
      final w = await workspace(), r = DayIncomeRepo();
      final c = IncomeCubit(w, r, Saver());
      addTearDown(() async {
        await c.close();
        await w.close();
        await r.events.close();
      });
      await c.load(
        filter: IncomeFilter(
          anchor: DateTime(2026, 10),
          source: incomeBookings,
        ),
      );
      await c.selectDay(15);
      expect(c.state.summary!.total, 60000);
      expect(c.state.filter.from, '2026-10-01');
      expect(r.requests.last.filter.from, '2026-10-15');
      expect(r.requests.last.filter.until, '2026-10-15');
      expect(r.requests.last.filter.source, incomeBookings);
      expect(c.state.items.single.entry.reason, 'First income');
      await c.more();
      expect(r.requests.last.cursor, 1);
      expect(r.requests.last.filter.from, '2026-10-15');
      expect(c.state.items.map((i) => i.entry.reason), [
        'First income',
        'Second income',
      ]);
      await c.load(refresh: true);
      expect(c.state.selectedDay, 15);
      await c.load(filter: c.state.filter.copy(accountId: 'bank'));
      expect(c.state.selectedDay, 15);
      expect(r.requests.last.filter.accountId, 'bank');
      await c.selectDay(17);
      expect(c.state.items, isEmpty);
      await c.selectDay(null);
      expect(c.state.selectedDay, isNull);
      expect(c.state.items.length, 3);
      await c.selectDay(31);
      await c.load(filter: c.state.filter.copy(anchor: DateTime(2026, 11)));
      expect(c.state.selectedDay, isNull);
      await c.selectDay(31);
      expect(c.state.selectedDay, isNull);
      await c.selectDay(15);
      await c.load(filter: c.state.filter.copy(yearly: true));
      expect(c.state.selectedDay, isNull);
    },
  );

  test(
    'failed expense selection hides old rows and stale pagination is ignored',
    () async {
      final w = await workspace(), r = DayExpenseRepo();
      final c = ExpensesCubit(w, r, Saver());
      addTearDown(() async {
        await c.close();
        await w.close();
        await r.events.close();
      });
      await c.load();
      await c.selectDay(15);
      r.pendingMore = Completer<ExpensePage>();
      final more = c.more();
      r.failList = true;
      await c.selectDay(16);
      expect(c.state.items, isEmpty);
      expect(c.state.error, isNotNull);
      expect(c.state.more, isFalse);
      r.pendingMore!.complete(ExpensePage([], 2));
      await more;
      expect(c.state.next, isNull);
      r.failList = false;
      await c.load();
      expect(c.state.items.single.reason, 'Other day expense');
    },
  );

  test(
    'failed income selection hides old rows and stale pagination is ignored',
    () async {
      final w = await workspace(), r = DayIncomeRepo();
      final c = IncomeCubit(w, r, Saver());
      addTearDown(() async {
        await c.close();
        await w.close();
        await r.events.close();
      });
      await c.load();
      await c.selectDay(15);
      r.pendingMore = Completer<IncomePage>();
      final more = c.more();
      r.failList = true;
      await c.selectDay(16);
      expect(c.state.items, isEmpty);
      expect(c.state.error, isNotNull);
      expect(c.state.more, isFalse);
      r.pendingMore!.complete(IncomePage([], 2));
      await more;
      expect(c.state.next, isNull);
      r.failList = false;
      await c.load();
      expect(c.state.items.single.entry.reason, 'Other day income');
    },
  );

  for (final width in [390.0, 1440.0]) {
    for (final isIncome in [false, true]) {
      final label = isIncome ? 'income' : 'expenses';
      testWidgets('$label daily bar filters and clears at width $width', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final w = await workspace();
        final expenses = DayExpenseRepo(), income = DayIncomeRepo();
        await getIt.reset();
        getIt.registerFactoryParam<ExpensesCubit, WorkspaceSession, void>(
          (s, _) => ExpensesCubit(s, expenses, Saver()),
        );
        getIt.registerFactoryParam<IncomeCubit, WorkspaceSession, void>(
          (s, _) => IncomeCubit(s, income, Saver()),
        );
        final router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (_, _) =>
                  isIncome ? const IncomeScreen() : const ExpensesScreen(),
            ),
          ],
        );
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          router.dispose();
          await w.close();
          await getIt.reset();
          await expenses.events.close();
          await income.events.close();
        });
        await tester.pumpWidget(
          BlocProvider.value(
            value: w,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp.router(
                theme: AppTheme.build(Brightness.light),
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
        final bar = find.byKey(const ValueKey('finance-bar-14'));
        await tester.ensureVisible(bar);
        await tester.tap(bar);
        await tester.pumpAndSettle();
        expect(find.text('15 Oct 2026 · ₹ 300.00'), findsOneWidget);
        final chart = tester.widget<FinancePeriodChart>(
          find.byType(FinancePeriodChart),
        );
        expect(chart.selectedDay, 15);
        expect(chart.values.length, 31);
        expect(chart.values[15], 30000);
        expect(
          isIncome
              ? income.requests.last.filter.from
              : expenses.requests.last.filter.from,
          '2026-10-15',
        );
        expect(find.text('Other day expense'), findsNothing);
        expect(find.text('Other day income'), findsNothing);
        final emptyBar = find.byKey(const ValueKey('finance-bar-16'));
        await tester.ensureVisible(emptyBar);
        await tester.tap(emptyBar);
        await tester.pumpAndSettle();
        final empty = find.text('No $label on this day');
        await tester.ensureVisible(empty);
        expect(empty, findsOneWidget);
        final clear = find.text('Show all days');
        await tester.ensureVisible(clear);
        await tester.tap(clear);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<FinancePeriodChart>(find.byType(FinancePeriodChart))
              .selectedDay,
          isNull,
        );
        expect(
          isIncome
              ? income.requests.last.filter.until
              : expenses.requests.last.filter.until,
          '2026-10-31',
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
