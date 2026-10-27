import 'dart:async';
import 'dart:typed_data';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/expenses/cubit/expense_form_cubit.dart';
import 'package:eden_booking/modules/expenses/cubit/expenses_cubit.dart';
import 'package:eden_booking/modules/expenses/models/expense_models.dart';
import 'package:eden_booking/modules/expenses/repositories/expenses_repository.dart';
import 'package:eden_booking/modules/expenses/screens/expense_form_screen.dart';
import 'package:eden_booking/modules/expenses/screens/expenses_screen.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'accounts_module_test.dart' show qaCatalog;
import 'expenses_module_test.dart' show ExpenseRepo, Picker, Saver, workspace;

class SlowExpenses extends ExpenseRepo {
  final gate = Completer<void>();
  @override
  Future<String> create(ExpenseDraft r) async {
    writes.add(r);
    await gate.future;
    return 'saved';
  }
}

class FailingExpenses extends ExpenseRepo {
  FailingExpenses(this.code);
  final String code;
  @override
  Future<String> create(ExpenseDraft r) async {
    writes.add(r);
    throw AppException('Nope', code: code);
  }
}

class CategoryExpenses extends ExpenseRepo {
  final saved = <String>[];
  bool duplicate = false;
  @override
  Future<void> saveCategory(String name, {String? id, bool active = true}) async {
    if (duplicate) throw const AppException('A category with this name already exists.');
    saved.add(name);
  }
}

class UsdExpenses extends ExpenseRepo {
  @override
  Future<FinanceCatalog> financeCatalog() async => FinanceCatalog(
    name: 'Eden',
    currency: 'USD',
    today: '2026-10-15',
    canView: true,
    canManage: true,
    canExpense: true,
    accounts: qaCatalog.accounts,
    businesses: qaCatalog.businesses,
    routes: qaCatalog.routes,
  );
}

class ManyPicker extends Picker {
  ManyPicker(this.count);
  final int count;
  @override
  Future<List<ExpensePickedInvoice>> pick({bool camera = false, bool photos = false}) async => [
    for (var i = 0; i < count; i++)
      ExpensePickedInvoice(
        ExpenseInvoice(id: 'f$i', name: 'bill$i.pdf', type: 'application/pdf', size: 8),
        Uint8List.fromList([37, 80, 68, 70]),
      ),
  ];
}

Future<ExpenseFormCubit> form(
  ExpenseRepo r, {
  String reason = 'Replace floodlight',
  String? category = 'maintenance',
  String amount = '100',
  InvoicePicker? picker,
}) async {
  final w = await workspace();
  final c = ExpenseFormCubit(w, r, picker ?? Picker());
  addTearDown(() async {
    await c.close();
    await w.close();
  });
  await c.load();
  c.fields(reason: reason, categoryId: category);
  c.line(0, c.state.lines.first.copyWith(amount: amount));
  return c;
}

String textOf(WidgetTester tester, Finder field) => tester
    .widget<EditableText>(find.descendant(of: field, matching: find.byType(EditableText)))
    .controller
    .text;

/// Collects framework errors so one defect does not fail unrelated assertions.
List<FlutterErrorDetails> captureErrors() {
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = errors.add;
  return errors;
}

void main() {
  group('ExpenseFilter period arithmetic', () {
    test('month ends: leap February, 30/31 day months, December', () {
      expect(ExpenseFilter(anchor: DateTime(2024, 2, 10)).until, '2024-02-29');
      expect(ExpenseFilter(anchor: DateTime(2025, 2, 10)).until, '2025-02-28');
      expect(ExpenseFilter(anchor: DateTime(2026, 4, 10)).until, '2026-04-30');
      expect(ExpenseFilter(anchor: DateTime(2026, 12, 31)).until, '2026-12-31');
      expect(ExpenseFilter(anchor: DateTime(2026, 12, 31), yearly: true).until, '2026-12-31');
    });
    test('single day filter', () {
      final f = ExpenseFilter(anchor: DateTime(2026, 10, 15), day: 31);
      expect(f.from, '2026-10-31');
      expect(f.until, '2026-10-31');
    });
    test('day beyond month end rolls over rather than failing', () {
      final f = ExpenseFilter(anchor: DateTime(2026, 2, 1), day: 31);
      expect(f.from, '2026-03-03');
    });
    test('year 9999 does not throw', () {
      expect(ExpenseFilter(anchor: DateTime(9999, 12)).until, '9999-12-31');
    });
    test('bars skip dates in other months', () {
      final f = ExpenseFilter(anchor: DateTime(2026, 2, 1));
      final s = ExpenseSummary(300, 2, {'2026-02-28': 100, '2026-02-01': 200}, []);
      final bars = s.bars(f);
      expect(bars.length, 28);
      expect(bars.first, 200);
      expect(bars.last, 100);
    });
  });

  group('ExpenseFormCubit amount matrix', () {
    for (final ok in {'1': 100, '0.01': 1, '19.99': 1999, '4.35': 435, '1.15': 115, ' 7 ': 700, '1000000': 100000000}.entries) {
      test('"${ok.key}" saves ${ok.value} minor units', () async {
        final r = ExpenseRepo();
        final c = await form(r, amount: ok.key);
        await c.save();
        expect(r.writes.single.payments.single.amount, ok.value);
      });
    }
    for (final bad in ['', ' ', '0', '0.0', '0.00', '-1', '-0.01', '1.001', '1e3', 'abc', '💰', '١٢', '1000000.01', '99999999999999999999', '1,5', '+3', '0x1']) {
      test('"$bad" is rejected before any request', () async {
        final r = ExpenseRepo();
        final c = await form(r, amount: bad);
        await c.save();
        expect(r.writes, isEmpty);
        expect(c.state.error, isNotNull);
      });
    }
    test('one empty split line rejects the entire expense', () async {
      final r = ExpenseRepo();
      final c = await form(r);
      c.addLine();
      await c.save();
      expect(r.writes, isEmpty);
    });
    test('split totals are exact and removing a line updates the total', () async {
      final c = await form(ExpenseRepo(), amount: '0.10');
      c.addLine();
      c.line(1, c.state.lines[1].copyWith(amount: '0.20', accountId: 'cash'));
      expect(c.total, 30);
      c.removeLine(0);
      expect(c.total, 20);
    });
    test('split lines cap at 20, last line cannot be removed', () async {
      final c = await form(ExpenseRepo());
      for (var i = 0; i < 30; i++) {
        c.addLine();
      }
      expect(c.state.lines.length, 20);
      final one = await form(ExpenseRepo());
      one.removeLine(0);
      expect(one.state.lines.length, 1);
    });
    test('payment line without an account is rejected', () async {
      final r = ExpenseRepo();
      final c = await form(r);
      c.method(0, 'upi');
      c.line(0, c.state.lines.first.copyWith(clearAccount: true));
      await c.save();
      expect(r.writes, isEmpty);
    });
  });

  group('ExpenseFormCubit text fields and category', () {
    test('reason: empty, whitespace, one character rejected', () async {
      for (final bad in ['', ' ', '   ', 'a', ' a ', '\n']) {
        final r = ExpenseRepo();
        final c = await form(r, reason: bad);
        await c.save();
        expect(r.writes, isEmpty, reason: '"$bad"');
      }
    });
    test('reason accepted at 2 and 500 chars, trimmed, unicode intact', () async {
      for (final v in ['ab', 'a' * 500, '  修理 💡 <b>x</b> ']) {
        final r = ExpenseRepo();
        final c = await form(r, reason: v);
        await c.save();
        expect(r.writes.single.reason, v.trim());
      }
    });
    test('reference is trimmed and optional', () async {
      final r = ExpenseRepo();
      final c = await form(r);
      c.fields(reference: '  INV-9  ');
      await c.save();
      expect(r.writes.single.reference, 'INV-9');
      final r2 = ExpenseRepo();
      final c2 = await form(r2);
      await c2.save();
      expect(r2.writes.single.reference, '');
    });
    test('category is required and must exist', () async {
      for (final id in [null, '', 'ghost']) {
        final r = ExpenseRepo();
        final c = await form(r, category: id);
        await c.save();
        expect(r.writes, isEmpty, reason: '$id');
      }
    });
    test('reason over 500 characters is blocked in the cubit, not just the widget', () async {
      final r = ExpenseRepo();
      final c = await form(r, reason: 'a' * 501);
      await c.save();
      expect(r.writes, isEmpty);
    }, skip: 'BUG-13: ExpenseFormCubit.save() has no upper length check for reason (500) or reference (200); only the widget maxLength protects it');
    test('reference over 200 characters is blocked in the cubit', () async {
      final r = ExpenseRepo();
      final c = await form(r);
      c.fields(reference: 'a' * 201);
      await c.save();
      expect(r.writes, isEmpty);
    }, skip: 'BUG-13: see reason length');
  });

  group('ExpenseFormCubit invoices', () {
    test('11 files in one pick are rejected', () async {
      final c = await form(ExpenseRepo(), picker: ManyPicker(11));
      await c.pick();
      expect(c.state.files, isEmpty);
      expect(c.state.error, isNotNull);
    });
    test('10 files accepted, an 11th across picks is rejected', () async {
      final c = await form(ExpenseRepo(), picker: ManyPicker(10));
      await c.pick();
      expect(c.state.files.length, 10);
      await c.pick();
      expect(c.state.files.length, 10);
      expect(c.state.error, contains('10'));
    });
    test('removing a file frees a slot', () async {
      final c = await form(ExpenseRepo(), picker: ManyPicker(10));
      await c.pick();
      c.removeFile(0);
      expect(c.state.files.length, 9);
    });
    test('a failed upload keeps the expense id and marks only that file', () async {
      final r = ExpenseRepo()..failUpload = true;
      final c = await form(r);
      await c.pick();
      await c.save();
      expect(r.writes.length, 1);
      expect(c.state.savedId, 'saved-expense');
      expect(c.state.files.single.error, 'Upload failed');
      expect(c.state.complete, isFalse);
      r.failUpload = false;
      await c.save();
      expect(r.writes.length, 1, reason: 'retry must not create the expense again');
      expect(c.state.complete, isTrue);
    });
  });

  group('ExpenseFormCubit submission safety', () {
    test('double tap sends one expense', () async {
      final r = SlowExpenses();
      final c = await form(r);
      final a = c.save();
      final b = c.save();
      await Future<void>.delayed(Duration.zero);
      expect(r.writes.length, 1);
      r.gate.complete();
      await Future.wait([a, b]);
      expect(r.writes.length, 1);
    });
    test('editing is locked while saving and after saving', () async {
      final r = SlowExpenses();
      final c = await form(r);
      final f = c.save();
      c.fields(reason: 'changed mid-flight');
      expect(c.state.reason, 'Replace floodlight');
      r.gate.complete();
      await f;
      c.fields(reason: 'after save');
      expect(c.state.reason, 'Replace floodlight');
    });
    test('network failure retries the same command id', () async {
      final r = FailingExpenses('NETWORK');
      final c = await form(r);
      await c.save();
      await c.save();
      expect(r.writes.length, 2);
      expect(r.writes[0].commandId, r.writes[1].commandId);
      expect(r.writes[0], same(r.writes[1]));
    });
    test('validation failure unlocks the form for correction', () async {
      final r = FailingExpenses('VALIDATION_ERROR');
      final c = await form(r);
      await c.save();
      expect(c.pending, isNull);
      c.fields(reason: 'Corrected');
      expect(c.state.reason, 'Corrected');
    });
  });

  group('Category dialog (ExpensesScreen)', () {
    Future<CategoryExpenses> open(WidgetTester tester, {CategoryExpenses? repo}) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final r = repo ?? CategoryExpenses();
      final w = await workspace();
      addTearDown(w.close);
      await getIt.reset();
      getIt.registerFactoryParam<ExpensesCubit, WorkspaceSession, void>((s, _) => ExpensesCubit(s, r, Saver()));
      getIt.registerFactoryParam<ExpenseFormCubit, WorkspaceSession, void>((s, _) => ExpenseFormCubit(s, r, Picker()));
      addTearDown(getIt.reset);
      final router = GoRouter(routes: [GoRoute(path: '/', builder: (c, s) => const ExpensesScreen())]);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.light),
              routerConfig: router,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c).copyWith(textScaler: const TextScaler.linear(2.0)),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Manage categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add category'));
      await tester.pumpAndSettle();
      return r;
    }

    testWidgets('empty, whitespace and one-character names are ignored silently', (tester) async {
      final r = await open(tester);
      for (final bad in ['', '   ', 'a', ' a ']) {
        await tester.enterText(find.byType(TextField), bad);
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();
        expect(find.text('Category name'), findsOneWidget, reason: 'dialog stays open for "$bad"');
      }
      expect(r.saved, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('validation feedback is shown for an invalid name', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'a');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('at least 2'), findsOneWidget);
    }, skip: true); // BUG-14: category dialog Save does nothing and shows no message for an invalid name

    testWidgets('valid, emoji and 80 character names are saved trimmed', (tester) async {
      final saved = FlutterError.onError;
      addTearDown(() => FlutterError.onError = saved);
      captureErrors();
      final r = await open(tester);
      await tester.enterText(find.byType(TextField), '  Zoë 🏸  ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(r.saved.single, 'Zoë 🏸');
    });

    testWidgets('names over 80 characters are truncated by the field', (tester) async {
      final saved = FlutterError.onError;
      addTearDown(() => FlutterError.onError = saved);
      captureErrors();
      final r = await open(tester);
      await tester.enterText(find.byType(TextField), 'a' * 120);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(r.saved.single.length, 80);
    });

    testWidgets('BUG-18: closing the category dialog does not use a disposed controller', (tester) async {
      final saved = FlutterError.onError;
      addTearDown(() => FlutterError.onError = saved);
      final errors = captureErrors();
      await open(tester);
      await tester.enterText(find.byType(TextField), 'Valid name');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(errors, isEmpty);
    }, skip: true); // BUG-18: categoryDialog disposes its TextEditingController right after showDialog returns, while the closing animation still builds the TextField (expenses_screen.dart:96, income_screen.dart:109, accounts_transactions_screen.dart:229)

    testWidgets('duplicate name surfaces the server message', (tester) async {
      final saved = FlutterError.onError;
      addTearDown(() => FlutterError.onError = saved);
      captureErrors();
      final r = await open(tester, repo: CategoryExpenses()..duplicate = true);
      await tester.enterText(find.byType(TextField), 'Maintenance');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(r.saved, isEmpty);
      expect(find.textContaining('already exists', skipOffstage: false), findsWidgets,
          reason: 'the cubit does surface the server message');
    });

    testWidgets('BUG-21: duplicate-name error is visible to the user', (tester) async {
      final saved = FlutterError.onError;
      addTearDown(() => FlutterError.onError = saved);
      captureErrors();
      await open(tester, repo: CategoryExpenses()..duplicate = true);
      await tester.enterText(find.byType(TextField), 'Maintenance');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.textContaining('already exists'), findsWidgets);
    }, skip: true); // BUG-21: the error is rendered on the page under the manage-categories sheet, so the user sees nothing
  });

  group('ExpenseFormScreen at 320x568', () {
    Future<void> pump(WidgetTester tester, ExpenseRepo r, {double scale = 1.0}) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await workspace();
      addTearDown(w.close);
      await getIt.reset();
      getIt.registerFactoryParam<ExpensesCubit, WorkspaceSession, void>((s, _) => ExpensesCubit(s, r, Saver()));
      getIt.registerFactoryParam<ExpenseFormCubit, WorkspaceSession, void>((s, _) => ExpenseFormCubit(s, r, Picker()));
      addTearDown(getIt.reset);
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (c, s) => const Scaffold()),
          GoRoute(path: '/form', builder: (c, s) => const ExpenseFormScreen()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.light),
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
      unawaited(router.push('/form'));
      await tester.pumpAndSettle();
    }

    testWidgets('large text: no overflow, split lines and invoices render', (tester) async {
      await pump(tester, ExpenseRepo(), scale: 2.0);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Split across another payment source'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Files / PDF'), 300, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty save shows the validation message and sends nothing', (tester) async {
      final r = ExpenseRepo();
      await pump(tester, r);
      await tester.tap(find.text('Save expense'));
      await tester.pumpAndSettle();
      expect(r.writes, isEmpty);
      expect(find.textContaining('Choose a category'), findsOneWidget);
    });

    testWidgets('reason and reference text is capped by maxLength', (tester) async {
      await pump(tester, ExpenseRepo());
      final reason = find.widgetWithText(TextFormField, 'What was this expense for?');
      await tester.enterText(reason, 'a' * 800);
      expect(textOf(tester, reason).length, 500);
      final ref = find.widgetWithText(TextFormField, 'Reference / invoice number (optional)');
      await tester.ensureVisible(ref);
      await tester.enterText(ref, 'b' * 400);
      expect(textOf(tester, ref).length, 200);
    });

    testWidgets('total amount field has no length cap', (tester) async {
      await pump(tester, ExpenseRepo());
      final total = find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('expense-total') == true);
      await tester.enterText(total, '9' * 80);
      expect(textOf(tester, total).length, 80);
    }, skip: true); // BUG-15: single-line total amount has no maxLength/inputFormatter (split amount fields cap at 12); the server ceiling is 1,000,000.00

    testWidgets('full valid form saves once even with a double tap', (tester) async {
      final r = ExpenseRepo();
      await pump(tester, r);
      final total = find.byWidgetPredicate((w) => w is TextFormField && (w.key as ValueKey?)?.value.toString().startsWith('expense-total') == true);
      await tester.enterText(total, '19.99');
      await tester.enterText(find.widgetWithText(TextFormField, 'What was this expense for?'), 'Net 🏸');
      await tester.tap(find.text('Choose category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Maintenance').last);
      await tester.pumpAndSettle();
      final save = find.text('Save expense');
      await tester.tap(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(r.writes.length, 1);
      expect(r.writes.single.payments.single.amount, 1999);
      expect(r.writes.single.reason, 'Net 🏸');
    });

    testWidgets('split amount prefix follows the catalog currency', (tester) async {
      await pump(tester, UsdExpenses());
      await tester.tap(find.text('Split across another payment source'));
      await tester.pumpAndSettle();
      expect(find.text('₹ '), findsNothing);
    }, skip: true); // BUG-17: split payment Amount field hardcodes the '₹ ' prefix regardless of the organization currency (expense_form_screen.dart:97)
  });
}
