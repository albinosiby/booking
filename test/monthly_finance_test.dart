import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/accounts/models/accounts_models.dart';
import 'package:eden_booking/modules/accounts/models/accounts_screen_models.dart';
import 'package:eden_booking/modules/accounts/cubit/accounts_cubits.dart';
import 'package:eden_booking/modules/accounts/widgets/monthly_finance_chart.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;
import 'accounts_module_test.dart' show FakeAccountsRepository;

final months = List.generate(
  12,
  (i) => FinanceMonthAnalysis(
    month: '2030-${(i + 1).toString().padLeft(2, '0')}',
    income: i == 0
        ? 10000
        : i == 1
        ? 5000
        : 0,
    expenses: i == 0
        ? 2000
        : i == 1
        ? 1000
        : 0,
    spaces: i < 2
        ? [
            FinanceSpaceMonth(
              businessId: 'business',
              spaceId: 'one',
              business: 'Badminton',
              space: 'Court 1',
              income: i == 0 ? 10000 : 5000,
              expenses: i == 0 ? 2000 : 0,
            ),
            if (i == 1) const FinanceSpaceMonth(expenses: 1000),
          ]
        : [],
  ),
);
final catalog = FinanceCatalog(
  canView: true,
  today: '2030-02-14',
  businesses: [
    FinanceBusiness('business', 'Badminton', [
      const FinanceSpace('one', 'Court 1'),
      const FinanceSpace('two', 'Court 2'),
    ]),
  ],
);
final monthlyOverview = FinanceOverview(
  selected: const FinanceTotals(),
  today: const FinanceTotals(),
  previous: const FinanceTotals(),
  monthlyAnalysis: months,
);
final filter = const FinanceFilter(from: '2030-02-01', until: '2030-02-28');

class MonthlyRepository extends FakeAccountsRepository {
  int reads = 0;
  @override
  Future<FinanceOverview> overview(FinanceFilter filter) async {
    reads++;
    return overviewValueMonthly;
  }

  final overviewValueMonthly = monthlyOverview;
}

void main() {
  test('month selection is local and survives a background refresh', () async {
    final w = WorkspaceCubit(BookingSource());
    await w.load();
    final r = MonthlyRepository()..catalogValue = catalog;
    final bookings = FakeBookingRepository();
    final c = AccountsOverviewCubit(w, r, bookings);
    await c.load(filter: filter);
    expect(c.state.activeMonth!.month, '2030-02');
    expect(
      c.state.spaceBreakdown.where((s) => s.spaceId == 'two').single.income,
      0,
    );
    expect(
      c.state.spaceBreakdown.any((s) => s.label == 'Organization · Shared'),
      isTrue,
    );
    c.selectMonth('2030-01');
    expect(c.state.activeMonth!.income, 10000);
    expect(r.reads, 1);
    c.selectMonth('2040-01');
    expect(c.state.activeMonth!.month, '2030-01');
    await c.load();
    expect(c.state.activeMonth!.month, '2030-01');
    expect(r.reads, 2);
    expect(() => c.state.spaceBreakdown.clear(), throwsUnsupportedError);
    await c.close();
    await w.close();
    await r.events.close();
    await bookings.events.close();
  });
  for (final dark in [false, true]) {
    testWidgets('monthly bars and space totals at 320px ($dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var model = AccountsOverviewModel(
        filter: filter,
        catalog: catalog,
        overview: monthlyOverview,
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) => SingleChildScrollView(
                    child: MonthlyFinancePanel(
                      model: model,
                      currency: 'INR',
                      onMonth: (m) => setState(() => model = model.month(m)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Feb 2030'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('finance-month-2030-01')));
      await tester.pumpAndSettle();
      expect(find.text('Jan 2030'), findsOneWidget);
      expect(find.text('₹ 100.00'), findsOneWidget);
      expect(find.text('Badminton · Court 1'), findsOneWidget);
      expect(find.text('Badminton · Court 2'), findsOneWidget);
      await tester.ensureVisible(
        find.byKey(const ValueKey('finance-month-2030-02')),
      );
      await tester.tap(find.byKey(const ValueKey('finance-month-2030-02')));
      await tester.pumpAndSettle();
      expect(find.text('Organization · Shared'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('axis amounts use compact lakh, crore and k/M units', () {
    expect(financeCompact(0, 'INR'), '₹0');
    expect(financeCompact(150000, 'INR'), '₹1.5k');
    expect(financeCompact(15000000, 'INR'), '₹1.5L');
    expect(financeCompact(300000000, 'INR'), '₹30L');
    expect(financeCompact(2000000000, 'INR'), '₹2Cr');
    expect(financeCompact(-500000, 'INR'), '-₹5k');
    expect(financeCompact(250000000, 'USD'), '2.5M');
  });
  test('negative reversal months keep signed cash flow', () {
    final correction = FinanceMonthAnalysis(
      month: '2030-01',
      income: -5000,
      expenses: -2000,
      refunds: 1000,
    );
    expect(correction.net, -4000);
  });
}
