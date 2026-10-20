import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/expenses/cubit/expense_detail_cubit.dart';
import 'package:eden_booking/modules/expenses/models/expense_models.dart';
import 'package:eden_booking/modules/expenses/screens/expense_detail_screen.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'expenses_module_test.dart' show ExpenseRepo, Picker, workspace;

class DetailRepo extends ExpenseRepo {
  DetailRepo(this.reversed);
  final bool reversed;
  @override
  Future<ExpenseDetail> detail(String id) async => ExpenseDetail(
    ExpenseItem(
      id: id,
      reason: 'Repair lights above the swimming pool',
      category: 'Maintenance',
      date: '2026-10-16T06:00:00Z',
      amount: 125000,
      business: 'Swimming pool',
      space: 'Pool A',
      staff: 'Alex',
      reference: 'INV-2026-100',
      lines: const [
        FinanceLine('cash', 'Cash in hand', 'cash', -25000),
        FinanceLine('bank', 'Primary business bank account', 'upi', -100000),
      ],
    ),
    const [
      ExpenseInvoice(
        id: 'ready',
        name: 'Maintenance invoice October.pdf',
        type: 'application/pdf',
        size: 16384,
        ready: true,
      ),
      ExpenseInvoice(
        id: 'pending',
        name: 'Pool lighting receipt.jpg',
        type: 'image/jpeg',
        size: 100000,
      ),
    ],
    reversed: reversed,
    canAttach: !reversed,
  );
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'Expense receipt fits narrow large-text $brightness with invoice actions',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final session = await workspace();
        final repository = DetailRepo(brightness == Brightness.dark);
        await getIt.reset();
        getIt
            .registerFactoryParam<ExpenseDetailCubit, WorkspaceSession, String>(
              (session, id) =>
                  ExpenseDetailCubit(session, repository, Picker(), id),
            );
        await tester.pumpWidget(
          BlocProvider.value(
            value: session,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp(
                theme: AppTheme.build(brightness),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: const TextScaler.linear(1.6)),
                  child: child!,
                ),
                home: const ExpenseDetailScreen(id: 'expense'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('TOTAL EXPENSE'), findsOneWidget);
        expect(find.text('Maintenance'), findsOneWidget);
        expect(
          find.text('Repair lights above the swimming pool'),
          findsOneWidget,
        );
        final scroll = find.byType(Scrollable).first;
        await tester.scrollUntilVisible(
          find.text('Paid from'),
          250,
          scrollable: scroll,
        );
        expect(find.text('Primary business bank account'), findsOneWidget);
        expect(find.text('UPI'), findsOneWidget);
        await tester.scrollUntilVisible(
          find.text('Maintenance invoice October.pdf'),
          250,
          scrollable: scroll,
        );
        expect(find.text('PDF · 16 KB'), findsOneWidget);
        if (brightness == Brightness.light) {
          await tester.scrollUntilVisible(
            find.text('Add invoices'),
            200,
            scrollable: scroll,
          );
          expect(find.byTooltip('Remove incomplete upload'), findsOneWidget);
        } else {
          expect(find.text('Add invoices'), findsNothing);
          expect(find.byTooltip('Remove incomplete upload'), findsNothing);
          expect(find.textContaining('Reversed expense'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await session.close();
        await repository.events.close();
        await getIt.reset();
      },
    );
  }
}
