import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
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
import 'accounts_module_test.dart' show qaCatalog;
import 'expenses_module_test.dart' show Saver, workspace;
import 'income_module_test.dart' show IncomeRepo;

class CategoryIncome extends IncomeRepo {
  final saved = <(String, String?, bool)>[];
  bool duplicate = false;
  @override
  Future<void> saveCategory(String name, {String? id, bool active = true}) async {
    if (duplicate) throw const AppException('A category with this name already exists.');
    saved.add((name, id, active));
  }
}

class EmptyIncome extends IncomeRepo {
  @override
  Future<IncomeSummary> overview(IncomeFilter f) async => IncomeSummary(total: 0, refunds: 0, count: 0);
  @override
  Future<IncomePage> list(IncomeFilter f, {int cursor = 0}) async => IncomePage(const [], null);
}

class NoAccessIncome extends IncomeRepo {
  @override
  Future<FinanceCatalog> financeCatalog() async => FinanceCatalog(name: 'Eden', today: '2026-10-15');
}

class HugeIncome extends IncomeRepo {
  @override
  Future<IncomeSummary> overview(IncomeFilter f) async => IncomeSummary(
    total: 100000000000000,
    refunds: 100000000000001,
    count: 999999999,
    days: const {'2026-10-15': 100000000000000},
    sources: const [IncomeSourceTotal('x', 'A very long income category name that keeps going and going for ever', 100000000000000)],
  );
}

void main() {
  group('IncomeFilter', () {
    test('month and year boundaries', () {
      expect(IncomeFilter(anchor: DateTime(2024, 2, 29)).until, '2024-02-29');
      expect(IncomeFilter(anchor: DateTime(2025, 2, 1)).until, '2025-02-28');
      expect(IncomeFilter(anchor: DateTime(2026, 12, 15)).until, '2026-12-31');
      expect(IncomeFilter(anchor: DateTime(2026, 6, 15), yearly: true).from, '2026-01-01');
      expect(IncomeFilter(anchor: DateTime(2026, 6, 15), yearly: true).until, '2026-12-31');
    });
    test('day filter pins both ends', () {
      final f = IncomeFilter(anchor: DateTime(2026, 10, 15), day: 31);
      expect(f.from, f.until);
      expect(f.from, '2026-10-31');
    });
    test('search text is trimmed and empty/whitespace is dropped', () {
      final base = IncomeFilter(anchor: DateTime(2026, 10, 1));
      expect(base.toQuery().containsKey('q'), isFalse);
      expect(base.copy(query: '   ').toQuery().containsKey('q'), isFalse);
      expect(base.copy(query: '  rent 🏠 ').toQuery()['q'], 'rent 🏠');
    });
    test('search longer than the server allows is not clamped', () {
      final q = IncomeFilter(anchor: DateTime(2026, 10, 1)).copy(query: 'a' * 300).toQuery()['q'] as String;
      expect(q.length <= 100, isTrue);
    }, skip: 'BUG-11: search text is not limited to the 100 characters the finance API accepts');
    test('clearing scope and account', () {
      final f = IncomeFilter(anchor: DateTime(2026, 10, 1), businessId: 'b', spaceId: 's', accountId: 'a');
      final cleared = f.copy(businessId: null, spaceId: null, clearScope: true, clearAccount: true);
      expect(cleared.businessId, isNull);
      expect(cleared.spaceId, isNull);
      expect(cleared.accountId, isNull);
    });
  });

  group('IncomeSummary parsing and bars', () {
    test('numbers arriving as strings, doubles or null are tolerated', () {
      expect(incomeInt('123'), 123);
      expect(incomeInt(12.9), 12);
      expect(incomeInt(null), 0);
      expect(incomeInt('abc'), 0);
      expect(incomeInt(''), 0);
      expect(incomeInt('-5'), -5);
      expect(incomeInt('9223372036854775807'), 9223372036854775807);
    });
    test('fromJson with empty collections', () {
      final s = IncomeSummary.fromJson({'total_minor': '1999', 'refunds_minor': 99, 'count': null, 'days': [], 'sources': []});
      expect(s.total, 1999);
      expect(s.net, 1900);
      expect(s.count, 0);
    });
    test('net can be negative when refunds exceed income', () {
      expect(IncomeSummary(total: 100, refunds: 250, count: 1).net, -150);
    });
    test('yearly bars aggregate by month and monthly bars by day', () {
      final s = IncomeSummary(total: 0, refunds: 0, count: 0, days: {'2026-01-05': 10, '2026-01-30': 5, '2026-12-31': 7});
      final year = s.bars(IncomeFilter(anchor: DateTime(2026, 6), yearly: true));
      expect(year.length, 12);
      expect(year[0], 15);
      expect(year[11], 7);
      final feb = s.bars(IncomeFilter(anchor: DateTime(2025, 2)));
      expect(feb.length, 28);
    });
    test('a malformed day key throws instead of being ignored', () {
      final s = IncomeSummary(total: 0, refunds: 0, count: 0, days: {'not-a-date': 1});
      expect(() => s.bars(IncomeFilter(anchor: DateTime(2026, 2))), returnsNormally);
    }, skip: 'BUG-19: IncomeSummary.bars (and ExpenseSummary.bars) call DateTime.parse on server keys without a guard; one malformed day makes the whole income/expenses page throw');
  });

  group('IncomeCubit', () {
    Future<IncomeCubit> make(IncomeRepo r) async {
      final w = await workspace();
      final c = IncomeCubit(w, r, Saver());
      addTearDown(() async {
        await c.close();
        await w.close();
      });
      await c.load();
      return c;
    }

    test('selectDay rejects days outside the month', () async {
      final r = IncomeRepo();
      final c = await make(r);
      final calls = r.filters.length;
      await c.selectDay(0);
      await c.selectDay(32);
      await c.selectDay(-1);
      expect(r.filters.length, calls);
      await c.selectDay(31);
      expect(c.state.selectedDay, 31);
    });
    test('February day 30 is rejected in a non-leap year', () async {
      final r = IncomeRepo();
      final c = await make(r);
      c.setFilter(c.state.filter.copy(anchor: DateTime(2027, 2)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await c.selectDay(29);
      expect(c.state.selectedDay, isNull);
      await c.selectDay(28);
      expect(c.state.selectedDay, 28);
    });
    test('day selection resets when the month changes', () async {
      final c = await make(IncomeRepo());
      await c.selectDay(5);
      c.setFilter(c.state.filter.copy(anchor: DateTime(2026, 11)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(c.state.selectedDay, isNull);
    });
    test('selectDay is ignored in yearly mode and for the same day twice', () async {
      final r = IncomeRepo();
      final c = await make(r);
      await c.selectDay(5);
      final n = r.filters.length;
      await c.selectDay(5);
      expect(r.filters.length, n);
      c.setFilter(c.state.filter.copy(yearly: true));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await c.selectDay(6);
      expect(c.state.selectedDay, isNull);
    });
    test('export file name embeds the period and the format', () async {
      final w = await workspace();
      final saver = Saver();
      final c = IncomeCubit(w, IncomeRepo(), saver);
      addTearDown(() async {
        await c.close();
        await w.close();
      });
      await c.load();
      await c.export('pdf');
      expect(saver.name, 'bookos-income-2026-10-all.pdf');
    });
    test('double tap on export runs a single download', () async {
      final w = await workspace();
      final saver = Saver();
      final r = IncomeRepo();
      final c = IncomeCubit(w, r, saver);
      addTearDown(() async {
        await c.close();
        await w.close();
      });
      await c.load();
      final before = r.filters.length;
      await Future.wait([c.export('pdf'), c.export('pdf')]);
      expect(r.filters.length - before, 1);
    });
    test('category save forwards the raw name and surfaces server rejection', () async {
      final r = CategoryIncome();
      final c = await make(r);
      await c.category('Zoë 🏸');
      expect(r.saved.single.$1, 'Zoë 🏸');
      r.duplicate = true;
      await c.category('Sponsorship');
      expect(c.state.error, 'A category with this name already exists.');
    });
    test('category archive keeps the id and flag', () async {
      final r = CategoryIncome();
      final c = await make(r);
      await c.category('Events', id: 'events', active: false);
      expect(r.saved.single, ('Events', 'events', false));
    });
    test('category cubit does not guard blank names itself', () async {
      final r = CategoryIncome();
      final c = await make(r);
      await c.category('   ');
      await c.category('a');
      expect(r.saved, isEmpty);
    }, skip: 'BUG-20: IncomeCubit/ExpensesCubit.category() forward blank or one-character names; only the dialog button guards them');
    test('no view permission yields no figures', () async {
      final c = await make(NoAccessIncome());
      expect(c.state.summary, isNull);
      expect(c.state.items, isEmpty);
    });
    test('overview failure clears stale figures', () async {
      final r = IncomeRepo()..failOverview = true;
      final c = await make(r);
      expect(c.state.error, isNotNull);
      expect(c.state.summary, isNull);
    });
  });

  group('IncomeScreen at 320x568', () {
    Future<void> pump(WidgetTester tester, IncomeRepo r, {double scale = 2.0}) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await workspace();
      addTearDown(w.close);
      await getIt.reset();
      getIt.registerFactoryParam<IncomeCubit, WorkspaceSession, void>((s, _) => IncomeCubit(s, r, Saver()));
      addTearDown(getIt.reset);
      final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => const IncomeScreen())]);
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
    }

    testWidgets('populated state', (tester) async {
      await pump(tester, IncomeRepo());
      expect(tester.takeException(), isNull);
    });
    testWidgets('empty state', (tester) async {
      await pump(tester, EmptyIncome());
      expect(tester.takeException(), isNull);
    });
    testWidgets('error state offers a retry', (tester) async {
      await pump(tester, IncomeRepo()..failOverview = true);
      expect(find.byType(AppErrorWidget), findsWidgets);
      expect(tester.takeException(), isNull);
    });
    testWidgets('no permission state', (tester) async {
      await pump(tester, NoAccessIncome());
      expect(tester.takeException(), isNull);
    });
    testWidgets('huge totals and a very long category name do not overflow', (tester) async {
      await pump(tester, HugeIncome());
      expect(tester.takeException(), isNull);
    });
  });
}
