import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/bookings/screens/booking_detail_screen.dart';
import 'package:eden_booking/modules/bookings/models/booking_detail_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_detail_cubit.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_payment_summary.dart';
import 'package:eden_booking/modules/bookings/widgets/booking_detail_overview.dart';
import 'booking_module_test.dart' show form, customer;

void main() {
  test(
    'booking call link keeps the country code and only dialable characters',
    () {
      expect(
        bookingPhoneUri('+91 (98765) 43210')?.toString(),
        'tel:+919876543210',
      );
      expect(bookingPhoneUri('98765-43210')?.toString(), 'tel:9876543210');
      expect(bookingPhoneUri(''), isNull);
      expect(bookingPhoneUri('not a phone'), isNull);
    },
  );
  testWidgets('customer Call button works at 320px with large text', (
    tester,
  ) async {
    final record = (await tester.runAsync(() async {
      final (workspace, repository, controller) = await form();
      customer(controller);
      await controller.review();
      await controller.confirm();
      final record = await repository.detail(controller.state.resultId!);
      await controller.close();
      await workspace.close();
      return record;
    }))!;
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var called = false;
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: Scaffold(
              body: SingleChildScrollView(
                child: BookingInformationCard(
                  booking: record,
                  onCall: () => called = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('booking-call-customer')));
    expect(called, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets('past confirmed booking cannot be rescheduled', (tester) async {
    final fixture = (await tester.runAsync(() async {
      final (workspace, repository, controller) = await form();
      customer(controller);
      await controller.review();
      await controller.confirm();
      final id = controller.state.resultId!;
      repository.records[id]!['starts_at'] = DateTime.now()
          .subtract(const Duration(days: 1))
          .toUtc()
          .toIso8601String();
      final reschedule = BookingFormCubit(
        workspace,
        repository,
        BookingLaunch(rescheduleId: id),
      );
      await reschedule.load();
      expect(
        reschedule.state.error,
        'This booking can no longer be rescheduled.',
      );
      await reschedule.close();
      await controller.close();
      return (workspace, repository, id);
    }))!;
    final (workspace, repository, id) = fixture;
    await getIt.reset();
    getIt.registerFactoryParam<BookingDetailCubit, WorkspaceCubit, String>(
      (session, bookingId) =>
          BookingDetailCubit(session, repository, bookingId),
    );
    addTearDown(getIt.reset);
    addTearDown(workspace.close);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => BlocProvider.value(
          value: workspace,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: BookingDetailScreen(id: id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reschedule'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('booking details show payment method history and website ID', (
    tester,
  ) async {
    final fixture = (await tester.runAsync(() async {
      final (workspace, repository, controller) = await form();
      customer(controller);
      await controller.review();
      await controller.confirm();
      final id = controller.state.resultId!;
      final row = repository.records[id]!;
      final total = row['total_minor'] as int;
      row['website_payment_submission'] = {
        'percentage': 50,
        'amount_minor': total ~/ 2,
        'transaction_id': 'UPI-DETAIL-123',
        'upi_id': 'venue@upi',
        'status': 'pending_verification',
      };
      row['payments'] = [
        {
          'id': 'cash-collection',
          'kind': 'collection',
          'method': 'cash',
          'amount_minor': total,
          'reference': '',
          'local_received': '2030-06-04T09:00',
          'collector_name': 'Owner',
        },
      ];
      await controller.close();
      return (workspace, repository, id);
    }))!;
    final (workspace, repository, id) = fixture;
    await getIt.reset();
    getIt.registerFactoryParam<BookingDetailCubit, WorkspaceCubit, String>(
      (session, bookingId) =>
          BookingDetailCubit(session, repository, bookingId),
    );
    addTearDown(getIt.reset);
    addTearDown(workspace.close);
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => BlocProvider.value(
          value: workspace,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: BookingDetailScreen(id: id),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Fully paid'), findsOneWidget);
    expect(find.text('No payment pending'), findsOneWidget);
    expect(find.text('Cash recorded'), findsOneWidget);
    expect(find.text('Payment history · 1'), findsOneWidget);
    expect(find.text('Collected by Owner'), findsOneWidget);
    expect(find.text('Transaction ID: UPI-DETAIL-123'), findsOneWidget);
    expect(find.text('Reschedule'), findsOneWidget);
    expect(find.byKey(const ValueKey('booking-call-customer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('website UPI claim stays visible beside recorded cash', (
    tester,
  ) async {
    final record = (await tester.runAsync(() async {
      final (workspace, repository, controller) = await form();
      customer(controller);
      await controller.review();
      await controller.confirm();
      final row = repository.records[controller.state.resultId!]!;
      final total = row['total_minor'] as int;
      row['website_payment_submission'] = {
        'percentage': 50,
        'amount_minor': total ~/ 2,
        'transaction_id': 'UPI-TEST-123',
        'upi_id': 'venue@upi',
        'status': 'pending_verification',
      };
      final unpaid = await repository.detail(controller.state.resultId!);
      expect(unpaid.paymentStatus, 'unpaid');
      row['payments'] = [
        {
          'id': 'cash-collection',
          'kind': 'collection',
          'method': 'cash',
          'amount_minor': total,
          'reference': '',
          'local_received': '2030-06-04T09:00',
          'collector_name': 'Owner',
        },
      ];
      final paid = await repository.detail(controller.state.resultId!);
      expect(paid.paymentStatus, 'paid');
      await controller.close();
      await workspace.close();
      return paid;
    }))!;
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, child) => MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  BookingPaymentSummary(booking: record, currency: 'INR'),
                  WebsitePaymentReviewCard(booking: record, currency: 'INR'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No payment pending'), findsOneWidget);
    expect(find.text('Cash recorded'), findsOneWidget);
    expect(
      find.text('Website payment · Verify before collecting'),
      findsOneWidget,
    );
    expect(find.textContaining('Submitted: 50%'), findsOneWidget);
    expect(
      tester
          .widget<SelectableText>(
            find.byKey(const ValueKey('booking-website-transaction-id')),
          )
          .data,
      'Transaction ID: UPI-TEST-123',
    );
    expect(tester.takeException(), isNull);
  });
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
      expect(detail.state.record!.automaticallyCheckedIn, isFalse);
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
  for (final width in [320.0, 1280.0]) {
    testWidgets('automatic end-of-day check-in is labelled clearly at $width', (
      tester,
    ) async {
      final fixture = (await tester.runAsync(() async {
        final (workspace, repository, controller) = await form();
        customer(controller);
        await controller.review();
        await controller.confirm();
        final id = controller.state.resultId!;
        final before = await repository.detail(id);
        repository.records[id]!['history'] = [
          {
            'action': 'checked_in',
            'actor_name': 'Booking OS automation',
            'local_created': '2030-06-05T00:00:00',
            'details': {
              'reason':
                  'Auto checked in at end of day; actual arrival time was not recorded.',
              'source': 'automatic_end_of_day',
            },
          },
        ];
        final after = await repository.detail(id);
        expect(after.checkedIn, true);
        expect(after.automaticallyCheckedIn, true);
        expect(after.balance, before.balance);
        expect(after.netPaid, before.netPaid);
        expect(after.status, before.status);
        await controller.close();
        return (workspace, repository, id);
      }))!;
      final (workspace, repository, id) = fixture;
      await getIt.reset();
      getIt.registerFactoryParam<BookingDetailCubit, WorkspaceCubit, String>(
        (session, bookingId) =>
            BookingDetailCubit(session, repository, bookingId),
      );
      addTearDown(getIt.reset);
      addTearDown(workspace.close);
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => BlocProvider.value(
            value: workspace,
            child: MaterialApp(
              theme: AppTheme.build(Brightness.light),
              home: BookingDetailScreen(id: id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Auto checked in'), findsOneWidget);
      expect(find.text('Check in'), findsNothing);
      expect(find.text('Balance due'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
    'collection sheet starts simple and reveals split only on request',
    (tester) async {
      final fixture = (await tester.runAsync(() async {
        final (workspace, repository, controller) = await form();
        customer(controller);
        await controller.review();
        await controller.confirm();
        final id = controller.state.resultId!;
        final before = await repository.detail(id);
        await controller.close();
        return (workspace, repository, id, before.balance);
      }))!;
      final (workspace, repository, id, balance) = fixture;
      await getIt.reset();
      getIt.registerFactoryParam<BookingDetailCubit, WorkspaceCubit, String>(
        (session, bookingId) =>
            BookingDetailCubit(session, repository, bookingId),
      );
      addTearDown(getIt.reset);
      addTearDown(workspace.close);
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => BlocProvider.value(
            value: workspace,
            child: MaterialApp(
              theme: AppTheme.build(Brightness.dark),
              home: BookingDetailScreen(id: id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('booking-summary-collect')));
      await tester.pumpAndSettle();
      expect(find.text('Collect payment'), findsOneWidget);
      expect(find.text('Split payment'), findsNothing);
      final amount = tester.widget<ConfigurationField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is ConfigurationField && widget.label == 'Amount · INR',
        ),
      );
      expect(amount.value, (balance / 100).toStringAsFixed(2));
      await tester.ensureVisible(find.text('Add another payment method'));
      await tester.tap(find.text('Add another payment method'));
      await tester.pumpAndSettle();
      expect(find.text('Split payment'), findsOneWidget);
      await tester.tap(find.byTooltip('Close payment form'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('booking-summary-collect')),
        findsOneWidget,
      );
      expect((await repository.detail(id)).balance, balance);
      expect(tester.takeException(), isNull);
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
      expect(find.text('Payment Summary'), findsOneWidget);
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
