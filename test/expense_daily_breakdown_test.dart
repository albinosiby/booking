import 'package:eden_booking/modules/expenses/models/expense_models.dart';
import 'package:eden_booking/modules/expenses/widgets/expense_daily_breakdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('daily expense card shows reason, space and payment methods', (
    tester,
  ) async {
    int? selected;
    final summary = ExpenseSummary(
      15000,
      2,
      {'2026-10-15': 15000},
      const [],
      gross: 20000,
      reversals: 5000,
      dailyTotals: {
        '2026-10-15': const ExpenseDailyTotal(
          gross: 20000,
          reversals: 5000,
          expenseCount: 1,
          reversalCount: 1,
          methods: {'cash': 5000, 'upi': 10000},
          purposes: [
            ExpensePurposeTotal(
              'Maintenance',
              'Lights repair',
              'Main Turf',
              20000,
            ),
          ],
          purposeCount: 1,
        ),
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseDailyBreakdown(
            summary: summary,
            anchor: DateTime(2026, 10),
            currency: 'INR',
            selectedDay: null,
            onDay: (day) => selected = day,
            onClearDay: () {},
          ),
        ),
      ),
    );
    expect(find.text('Expenses ₹ 200.00'), findsOneWidget);
    expect(find.text('Reversals ₹ 50.00'), findsOneWidget);
    expect(find.text('Net spent ₹ 150.00'), findsOneWidget);
    expect(
      find.text('Maintenance · Lights repair · Main Turf · ₹ 200.00'),
      findsOneWidget,
    );
    expect(find.text('Cash ₹ 50.00'), findsOneWidget);
    expect(find.text('UPI ₹ 100.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('expense-day-2026-10-15')));
    expect(selected, 15);
  });

  testWidgets('selected day exposes add and download actions', (tester) async {
    var added = false, downloaded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpenseDailyBreakdown(
            summary: ExpenseSummary(0, 0, const {}, const []),
            anchor: DateTime(2026, 10),
            currency: 'INR',
            selectedDay: 15,
            onDay: (_) {},
            onClearDay: () {},
            onAddExpense: () => added = true,
            onDownloadDay: () => downloaded = true,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('expense-day-add')));
    await tester.tap(find.byKey(const ValueKey('expense-day-download')));
    expect(added, true);
    expect(downloaded, true);
  });
}
