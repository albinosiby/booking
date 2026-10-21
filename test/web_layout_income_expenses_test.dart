import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/expenses/cubit/expense_detail_cubit.dart';
import 'package:eden_booking/modules/expenses/cubit/expense_form_cubit.dart';
import 'package:eden_booking/modules/expenses/cubit/expenses_cubit.dart';
import 'package:eden_booking/modules/expenses/screens/expense_detail_screen.dart';
import 'package:eden_booking/modules/expenses/screens/expense_form_screen.dart';
import 'package:eden_booking/modules/expenses/screens/expenses_screen.dart';
import 'package:eden_booking/modules/income/cubit/income_cubit.dart';
import 'package:eden_booking/modules/income/models/income_models.dart';
import 'package:eden_booking/modules/income/screens/income_screen.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'expense_detail_screen_test.dart' show DetailRepo;
import 'expenses_module_test.dart' show Picker, Saver, workspace;
import 'income_module_test.dart' show IncomeRepo;

late IncomeRepo income;
late DetailRepo expenses;

/// Pumps [page] in a 1440x1000 desktop window, pushed over a home route so
/// the in-page Back link is available.
Future<void> pumpDesktop(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final w = await workspace();
  addTearDown(w.close);
  final router = GoRouter(
    initialLocation: '/page',
    routes: [
      GoRoute(
        path: '/',
        builder: (c, s) => const Scaffold(body: Text('home')),
        routes: [GoRoute(path: 'page', builder: (c, s) => page)],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    BlocProvider.value(
      value: w,
      child: ScreenUtilInit(
        designSize: const Size(1440, 1000),
        builder: (c, _) => MaterialApp.router(
          theme: AppTheme.build(Brightness.dark),
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  // Unmount before the workspace closes so page cubits close first.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

void main() {
  setUp(() async {
    await getIt.reset();
    income = IncomeRepo();
    expenses = DetailRepo(false);
    getIt.registerFactoryParam<IncomeCubit, WorkspaceSession, void>(
      (s, _) => IncomeCubit(s, income, Saver()),
    );
    getIt.registerFactoryParam<ExpensesCubit, WorkspaceSession, void>(
      (s, _) => ExpensesCubit(s, expenses, Saver()),
    );
    getIt.registerFactoryParam<ExpenseFormCubit, WorkspaceSession, void>(
      (s, _) => ExpenseFormCubit(s, expenses, Picker()),
    );
    getIt.registerFactoryParam<ExpenseDetailCubit, WorkspaceSession, String>(
      (s, id) => ExpenseDetailCubit(s, expenses, Picker(), id),
    );
    addTearDown(getIt.reset);
  });

  testWidgets('income shows a desktop dashboard with stats and breakdown', (
    tester,
  ) async {
    await pumpDesktop(tester, const IncomeScreen());
    expect(find.byKey(const ValueKey('web-back')), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add income'), findsOneWidget);
    for (final tip in [
      'Download report',
      'Refresh',
      'Manage categories',
      'Previous period',
      'Next period',
      'Choose source',
      'Filter income',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    expect(find.byType(AppStatTile), findsNWidgets(4));
    expect(find.text('Net after refunds'), findsOneWidget);
    expect(find.text('₹ 750.00'), findsOneWidget);
    expect(find.text('By source'), findsOneWidget);
    expect(find.text('All income'), findsOneWidget);
    expect(find.text('Tournament sponsor'), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-export-pdf')), findsOneWidget);

    await tester.tap(find.text('Sponsorship').first);
    await tester.pumpAndSettle();
    expect(income.filters.last.source, 'sponsorship');

    await tester.tap(find.text('Yearly'));
    await tester.pumpAndSettle();
    // The cubit also preloads the previous period after the selected one.
    expect(
      income.filters.where((f) => f.yearly).map((f) => f.from),
      contains('2026-01-01'),
    );

    await tester.tap(find.byKey(const ValueKey('desktop-export-xlsx')));
    await tester.pumpAndSettle();
    expect(income.filters.last.source, 'sponsorship');
    expect(tester.takeException(), isNull);
  });

  testWidgets('income source filter can be cleared on desktop', (tester) async {
    await pumpDesktop(tester, const IncomeScreen());
    await tester.tap(find.text('Bookings').first);
    await tester.pumpAndSettle();
    expect(income.filters.last.source, incomeBookings);
    await tester.tap(find.bySemanticsLabel('Clear Bookings'));
    await tester.pumpAndSettle();
    expect(income.filters.last.source, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expenses shows a desktop dashboard with category panel', (
    tester,
  ) async {
    await pumpDesktop(tester, const ExpensesScreen());
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add expense'), findsOneWidget);
    expect(find.byType(AppStatTile), findsNWidgets(4));
    expect(find.text('Top category'), findsOneWidget);
    expect(find.text('Maintenance · 100% of spending'), findsOneWidget);
    expect(find.text('By category'), findsOneWidget);
    expect(find.text('No expenses in this period'), findsOneWidget);
    for (final tip in [
      'Download report',
      'Refresh',
      'Manage categories',
      'Choose category',
      'Filter expenses',
    ]) {
      expect(find.byTooltip(tip), findsOneWidget, reason: tip);
    }
    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();
    expect(expenses.filters.last.categoryId, 'maintenance');
    await tester.tap(find.byTooltip('Next period'));
    await tester.pumpAndSettle();
    final november = expenses.filters.where((f) => f.from == '2026-11-01');
    expect(november, isNotEmpty);
    expect(november.last.categoryId, 'maintenance');
    expect(tester.takeException(), isNull);
  });

  testWidgets('expense detail puts receipt and invoices beside details', (
    tester,
  ) async {
    await pumpDesktop(tester, const ExpenseDetailScreen(id: 'expense'));
    expect(find.byKey(const ValueKey('web-back')), findsOneWidget);
    expect(find.text('Receipt'), findsOneWidget);
    expect(find.text('TOTAL EXPENSE'), findsOneWidget);
    expect(find.text('Expense information'), findsOneWidget);
    expect(find.text('Paid from'), findsOneWidget);
    expect(find.text('2 payment sources'), findsOneWidget);
    expect(find.text('Primary business bank account'), findsOneWidget);
    expect(find.text('Maintenance invoice October.pdf'), findsOneWidget);
    expect(find.byTooltip('Remove incomplete upload'), findsOneWidget);
    expect(find.text('Add invoices'), findsOneWidget);
    final receipt = tester.getTopLeft(find.text('TOTAL EXPENSE'));
    final info = tester.getTopLeft(find.text('Expense information'));
    expect(receipt.dx, lessThan(info.dx));
    expect(tester.takeException(), isNull);
  });

  testWidgets('expense form uses two columns and keeps validation', (
    tester,
  ) async {
    await pumpDesktop(tester, const ExpenseFormScreen());
    final summary = find.byKey(const ValueKey('expense-summary-card'));
    expect(summary, findsOneWidget);
    expect(find.text('Save expense'), findsOneWidget);
    expect(find.text('Files / PDF'), findsOneWidget);
    expect(
      tester.getTopLeft(summary).dx,
      greaterThan(tester.getTopLeft(find.text('Expense details')).dx),
    );
    await tester.enterText(
      find.byWidgetPredicate(
        (w) =>
            w is TextFormField && w.key.toString().contains('expense-total-'),
      ),
      '500',
    );
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: summary, matching: find.text('₹ 500.00')),
      findsOneWidget,
    );
    await tester.tap(find.text('Files / PDF'));
    await tester.pumpAndSettle();
    expect(find.text('bill.pdf'), findsOneWidget);
    expect(
      find.descendant(of: summary, matching: find.text('1 attached')),
      findsOneWidget,
    );
    await tester.tap(find.text('Save expense'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Choose a category'), findsOneWidget);
    expect(expenses.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
