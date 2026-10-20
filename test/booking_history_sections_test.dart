import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_history_sections.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets(
      'history sections expose collection and expandable details at 320px ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var collected = false;
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) => MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
                useMaterial3: true,
              ),
              home: MediaQuery(
                data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
                child: Scaffold(
                  body: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          BookingPaymentHistory(
                            currency: 'INR',
                            collectAmount: 15000,
                            onCollect: () => collected = true,
                            payments: const [
                              BookingPayment(
                                id: 'p',
                                kind: 'refund',
                                method: 'upi',
                                amount: 10000,
                                reference: 'UPI-123',
                                localReceived: '2030-06-04T10:30',
                                collector: 'Staff One',
                                reason: 'Customer request',
                              ),
                            ],
                          ),
                          const BookingActivityHistory(
                            events: [
                              BookingEvent(
                                'rescheduled',
                                'Owner',
                                '2030-06-04T10:00',
                                'New date requested',
                                '2030-06-04T09:00',
                                '2030-06-05T09:00',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('history-collect')));
        expect(collected, isTrue);
        expect(find.textContaining('−'), findsOneWidget);
        await tester.tap(find.text('Reference & notes'));
        await tester.pumpAndSettle();
        expect(find.text('Reference: UPI-123'), findsOneWidget);
        expect(find.textContaining('Previous:'), findsOneWidget);
        expect(find.textContaining('→ New:'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.byType(AppCard), findsNWidgets(2));
      },
    );
  }
  testWidgets(
    'empty history sections do not display collection or card containers',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                BookingPaymentHistory(payments: [], currency: 'INR'),
                BookingActivityHistory(events: []),
              ],
            ),
          ),
        ),
      );
      expect(find.byKey(const ValueKey('history-collect')), findsNothing);
      expect(find.byType(AppCard), findsNothing);
      expect(find.text('No payments recorded yet.'), findsOneWidget);
      expect(find.text('No booking activity yet.'), findsOneWidget);
    },
  );
}
