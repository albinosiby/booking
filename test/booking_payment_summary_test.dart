import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/bookings/models/booking_detail_model.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_detail_cubit.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_payment_summary.dart';
import 'booking_module_test.dart' show form, customer;

void main() {
  test(
    'check-in records arrival without changing payment or final booking status',
    () async {
      final (w, r, c) = await form();
      customer(c);
      await c.review();
      await c.confirm();
      final id = c.state.resultId!;
      final detail = BookingDetailCubit(w, r, id);
      await detail.load();
      final original = detail.state.record!;
      expect(detail.state.canCheckIn, isTrue);
      detail.begin(BookingDetailAction.checkedIn);
      await detail.submit();
      expect(detail.state.record!.checkedIn, isTrue);
      expect(detail.state.record!.status, 'confirmed');
      expect(detail.state.record!.balance, original.balance);
      expect(detail.state.record!.netPaid, original.netPaid);
      expect(detail.state.canCheckIn, isFalse);
      detail.begin(BookingDetailAction.checkedIn);
      expect(detail.state.action, BookingDetailAction.none);
      await detail.close();
      await c.close();
      await w.close();
    },
  );
  for (final dark in [false, true]) {
    testWidgets('payment summary is readable and collects at 320px ($dark)', (
      tester,
    ) async {
      final record = (await tester.runAsync(() async {
        final (w, r, c) = await form();
        customer(c);
        await c.review();
        await c.confirm();
        final record = await r.detail(c.state.resultId!);
        await c.close();
        await w.close();
        return record;
      }))!;
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var tapped = false;
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: ThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
            ),
            home: MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
              child: Scaffold(
                body: SingleChildScrollView(
                  child: BookingPaymentSummary(
                    booking: record,
                    currency: 'INR',
                    onCollect: () => tapped = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Payment summary'), findsOneWidget);
      expect(find.text('Balance due'), findsOneWidget);
      expect(find.text('Booking total'), findsOneWidget);
      expect(find.text('Amount received'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('booking-summary-collect')));
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
