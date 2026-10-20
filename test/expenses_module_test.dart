import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/modules/expenses/screens/expenses_screen.dart';
import 'package:eden_booking/modules/expenses/screens/expense_form_screen.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/expenses/models/expense_models.dart';
import 'package:eden_booking/modules/expenses/repositories/expenses_repository.dart';
import 'package:eden_booking/modules/expenses/cubit/expenses_cubit.dart';
import 'package:eden_booking/modules/expenses/cubit/expense_form_cubit.dart';
import 'package:eden_booking/modules/expenses/widgets/expenses_widgets.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/accounts/cubit/accounts_cubits.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'accounts_module_test.dart' show qaCatalog;
import 'booking_module_test.dart' show BookingSource;

class ExpenseRepo extends Fake implements ExpensesRepository {
  final events = StreamController<void>.broadcast();
  final writes = <ExpenseDraft>[];
  final filters = <ExpenseFilter>[];
  bool failUpload = false;
  int uploads = 0;
  @override
  Stream<void> get changes => events.stream;
  @override
  void refresh() {}
  @override
  Future<FinanceCatalog> financeCatalog() async => qaCatalog;
  @override
  Future<List<ExpenseCategory>> categories() async => const [
    ExpenseCategory('maintenance', 'Maintenance'),
    ExpenseCategory('food', 'Food'),
  ];
  @override
  Future<ExpenseSummary> overview(ExpenseFilter f) async {
    filters.add(f);
    return ExpenseSummary(
      20000,
      1,
      {'2026-10-01': 20000},
      [const ExpenseCategoryTotal('maintenance', 'Maintenance', 20000)],
    );
  }

  @override
  Future<ExpensePage> list(ExpenseFilter f, {int cursor = 0}) async =>
      ExpensePage([], null);
  @override
  Future<String> create(ExpenseDraft r) async {
    writes.add(r);
    return 'saved-expense';
  }

  @override
  Future<void> upload(String id, ExpensePickedInvoice f) async {
    uploads++;
    if (failUpload) throw const AppException('Upload failed');
  }

  @override
  Future<List<int>> report(ExpenseFilter f, String format) async {
    filters.add(f);
    return [1, 2, 3];
  }
}

class Picker extends Fake implements InvoicePicker {
  @override
  Future<List<ExpensePickedInvoice>> pick({
    bool camera = false,
    bool photos = false,
  }) async => [
    ExpensePickedInvoice(
      const ExpenseInvoice(
        id: 'file',
        name: 'bill.pdf',
        type: 'application/pdf',
        size: 8,
      ),
      Uint8List.fromList([37, 80, 68, 70, 45, 49, 10, 10]),
    ),
  ];
}

class Saver implements ReportSaver {
  String? name;
  @override
  Future<bool> save(List<int> bytes, String filename) async {
    name = filename;
    return true;
  }
}

Future<WorkspaceCubit> workspace() async {
  final w = WorkspaceCubit(BookingSource());
  await w.load();
  return w;
}

void main() {
  test(
    'month/year bounds include full period and aggregate correct months',
    () {
      final f = ExpenseFilter(anchor: DateTime(2024, 2, 15));
      expect(f.from, '2024-02-01');
      expect(f.until, '2024-02-29');
      final year = f.copy(yearly: true, categoryId: 'food');
      expect(year.from, '2024-01-01');
      expect(year.until, '2024-12-31');
      expect(
        year.copy(anchor: DateTime(2024, 3), yearly: false).categoryId,
        'food',
      );
      final s = ExpenseSummary(300, 2, {
        '2024-02-01': 100,
        '2024-03-01': 200,
      }, []);
      expect(s.bars(year)[1], 100);
      expect(s.bars(year)[2], 200);
    },
  );
  test(
    'upload retry retains saved ID and records expense exactly once',
    () async {
      final w = await workspace(),
          r = ExpenseRepo(),
          c = ExpenseFormCubit(w, r, Picker());
      await c.load();
      c.fields(reason: 'Replace floodlight', categoryId: 'maintenance');
      c.line(0, c.state.lines[0].copyWith(amount: '500'));
      await c.pick();
      r.failUpload = true;
      await c.save();
      expect(c.state.savedId, 'saved-expense');
      expect(c.state.complete, false);
      expect(c.editable, false);
      expect(r.writes.length, 1);
      r.failUpload = false;
      await c.save();
      expect(c.state.complete, true);
      expect(r.writes.length, 1);
      expect(r.uploads, 2);
      await c.close();
      await w.close();
      await r.events.close();
    },
  );
  test(
    'report uses selected category and complete month/year filters',
    () async {
      final w = await workspace(),
          r = ExpenseRepo(),
          saver = Saver(),
          c = ExpensesCubit(w, r, saver);
      await c.load();
      await c.load(
        filter: ExpenseFilter(
          anchor: DateTime(2026, 5),
          yearly: true,
          categoryId: 'food',
        ),
      );
      await c.export('xlsx');
      expect(r.filters.last.categoryId, 'food');
      expect(r.filters.last.until, '2026-12-31');
      expect(saver.name, 'expenses-2026-01-01-2026-12-31-category.xlsx');
      expect(c.state.exporting, false);
      await c.close();
      await w.close();
      await r.events.close();
    },
  );
  testWidgets(
    'year graph selects month and fits narrow phones with large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      int? chosen;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.4)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: ExpenseChart(
                  values: List.generate(12, (i) => (i + 1) * 100),
                  filter: ExpenseFilter(anchor: DateTime(2026), yearly: true),
                  currency: 'INR',
                  onMonth: (m) => chosen = m,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Feb'));
      expect(chosen, 2);
      expect(tester.takeException(), isNull);
    },
  );
  for (final page in ['expenses', 'add']) {
    testWidgets('$page screen fits mobile with larger text', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = await workspace(), repository = ExpenseRepo();
      await getIt.reset();
      getIt.registerFactoryParam<ExpensesCubit, WorkspaceSession, void>(
        (s, _) => ExpensesCubit(s, repository, Saver()),
      );
      getIt.registerFactoryParam<ExpenseFormCubit, WorkspaceSession, void>(
        (s, _) => ExpenseFormCubit(s, repository, Picker()),
      );
      final loader = FontLoader('Roboto')
        ..addFont(
          Future.value(
            ByteData.sublistView(
              File(
                'backend/assets/fonts/NotoSans-Regular.ttf',
              ).readAsBytesSync(),
            ),
          ),
        );
      await loader.load();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (c, s) => page == 'expenses'
                ? const ExpensesScreen()
                : const ExpenseFormScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: session,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (c, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.light),
              routerConfig: router,
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(
                  c,
                ).copyWith(textScaler: const TextScaler.linear(1.2)),
                child: RepaintBoundary(
                  key: const ValueKey('capture-expenses'),
                  child: child!,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (page == 'expenses') {
        expect(find.text('Monthly'), findsOneWidget);
        expect(find.text('Add expense'), findsOneWidget);
      } else {
        expect(find.text('Save expense'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Files / PDF'),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(tester.takeException(), isNull);
        await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
        await tester.pumpAndSettle();
      }
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('capture-expenses')),
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.5),
            png = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '/tmp/booking-$page-preview.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      });
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      await session.close();
      await repository.events.close();
      await getIt.reset();
    });
  }
}
