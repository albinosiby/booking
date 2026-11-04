import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/accounts/widgets/finance_period_widgets.dart';

void main() {
  testWidgets('trend chart switches between bars and an interactive line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    int? selectedDay;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 280,
            child: FinanceTrendChart(
              values: const [0, 10000, 20000, 5000, 0],
              yearly: false,
              currency: 'INR',
              title: 'Daily income',
              onMonth: (_) {},
              onDay: (day) => selectedDay = day,
            ),
          ),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('finance-bar-1')), findsOneWidget);
    await tester.tap(find.byTooltip('Line chart'));
    await tester.pump();
    expect(find.byKey(const ValueKey('finance-line-chart')), findsOneWidget);
    expect(find.byKey(const ValueKey('finance-bar-1')), findsNothing);
    final chart = find.byKey(const ValueKey('finance-line-chart'));
    await tester.tapAt(tester.getCenter(chart));
    expect(selectedDay, 3);
    await tester.tap(find.byTooltip('Bar chart'));
    await tester.pump();
    expect(find.byKey(const ValueKey('finance-bar-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
