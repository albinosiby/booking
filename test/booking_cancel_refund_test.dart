import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_detail_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_detail_model.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/screens/booking_detail_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

const ownerCatalog = BookingCatalog(
  canView: true,
  canManage: true,
  canCollect: true,
  canRefund: true,
  paymentAccounts: [
    BookingMoneyAccount('cash', 'Cash in hand', 'cash', false),
    BookingMoneyAccount('bank', 'Refund bank', 'bank', true),
  ],
);

class RefundBookings extends FakeBookingRepository {
  bool rejectCancellation = false, failCancelledRead = false;
  Completer<void>? cancellationResponse;
  @override
  Future<String> submit(BookingCommand command) async {
    if (command.endpoint.endsWith('/status') && rejectCancellation) {
      throw const AppException('Booking changed. Reload.', code: 'CONFLICT');
    }
    final result = await super.submit(command);
    if (command.endpoint.endsWith('/status')) {
      await cancellationResponse?.future;
    }
    return result;
  }

  @override
  Future<BookingRecord> detail(String id) {
    if (failCancelledRead && records[id]?['status'] == 'cancelled') {
      throw const AppException('Offline', code: 'NETWORK');
    }
    return super.detail(id);
  }
}

Future<(WorkspaceCubit, RefundBookings, BookingDetailCubit)> fixture() async {
  final workspace = WorkspaceCubit(BookingSource());
  await workspace.load();
  final repository = RefundBookings()..catalogOverride = ownerCatalog;
  repository.records['booking'] = repository.row(
    'booking',
    const BookingSelection(
      businessId: 'business',
      resourceId: 'space',
      optionId: 'court',
      date: '2030-06-04',
      time: '09:00',
      duration: 60,
      people: 1,
    ),
    const BookingCustomer(name: 'Customer', phone: '9876543210'),
  )..['total_minor'] = 300000;
  repository.records['booking']!['payments'] = <Map<String, dynamic>>[
    {
      'id': 'cash-collection',
      'kind': 'collection',
      'method': 'cash',
      'amount_minor': 300000,
      'reference': '',
      'reason': '',
      'received_at': '2030-06-01T09:00:00Z',
      'local_received': '2030-06-01T14:30',
      'collector_name': 'Owner',
    },
  ];
  final cubit = BookingDetailCubit(workspace, repository, 'booking');
  await cubit.load();
  addTearDown(() async {
    if (!cubit.isClosed) {
      await cubit.close();
    }
    await repository.events.close();
    await workspace.close();
  });
  return (workspace, repository, cubit);
}

Future<void> cancel(BookingDetailCubit cubit) async {
  cubit.begin(BookingDetailAction.cancelAndRefund);
  cubit.reason('Customer cancelled');
  await cubit.submit();
}

void main() {
  tearDown(() => getIt.reset());
  test(
    'paid booking cancellation opens refund form without recording a refund',
    () async {
      final (_, repository, cubit) = await fixture();
      expect(cubit.state.canCancelAndRefund, isTrue);
      expect(cubit.state.record!.refundDue, 0);
      cubit.begin(BookingDetailAction.cancelAndRefund);
      await cubit.submit();
      expect(repository.submitted, isEmpty);
      expect(cubit.state.error, contains('reason'));
      cubit.reason('Customer cancelled');
      await cubit.submit();
      expect(cubit.state.action, BookingDetailAction.refund);
      expect(cubit.state.record!.status, 'cancelled');
      expect(cubit.state.record!.refundDue, 300000);
      expect(repository.submitted.single.body['status'], 'cancelled');
      expect(cubit.state.record!.payments, hasLength(1));
      cubit.cancelEdit();
      expect(cubit.state.action, BookingDetailAction.none);
      expect(cubit.state.record!.status, 'cancelled');
      expect(cubit.state.record!.refundDue, 300000);
    },
  );

  for (final method in ['cash', 'upi']) {
    test(
      'cancelled cash collection can be refunded using $method with a separate save',
      () async {
        final (_, repository, cubit) = await fixture();
        await cancel(cubit);
        final row = cubit.state.payments.single.id;
        cubit.updatePayment(
          row,
          (p) => p.copyWith(method: method, amount: '3001'),
        );
        cubit.reason('Customer refund');
        await cubit.submit();
        expect(repository.submitted, hasLength(1));
        expect(cubit.state.error, contains('exceeds'));
        cubit.updatePayment(
          row,
          (p) => p.copyWith(
            amount: '1000',
            accountId: method == 'upi' ? 'bank' : null,
          ),
        );
        await cubit.submit();
        expect(repository.submitted, hasLength(2));
        expect(repository.submitted.last.body['kind'], 'refund');
        final payment =
            (repository.submitted.last.body['payments'] as List).single;
        expect(payment['method'], method);
        if (method == 'upi') {
          expect(payment['account_id'], 'bank');
        }
        expect(cubit.state.record!.refundDue, 200000);
        expect(cubit.state.record!.balance, 0);
        expect(cubit.state.record!.status, 'cancelled');
      },
    );
  }

  for (final lookupFails in [false, true]) {
    test(
      'lost cancellation response recovers original command (lookup fails: $lookupFails)',
      () async {
        final (_, repository, cubit) = await fixture();
        repository.loseResponse = true;
        repository.lookupFails = lookupFails;
        await cancel(cubit);
        if (lookupFails) {
          expect(cubit.state.locked, isTrue);
          expect(cubit.state.action, BookingDetailAction.cancelAndRefund);
          cubit.cancelEdit();
          expect(cubit.state.action, BookingDetailAction.cancelAndRefund);
          repository.lookupFails = false;
          await cubit.submit();
          expect(repository.submitted[0].key, repository.submitted[1].key);
          expect(repository.submitted[0].body, repository.submitted[1].body);
        }
        expect(cubit.state.record!.version, 2);
        expect(cubit.state.action, BookingDetailAction.refund);
        expect(cubit.state.record!.payments, hasLength(1));
      },
    );
  }

  test(
    'failed cancellation leaves payment and confirmed booking intact',
    () async {
      final (_, repository, cubit) = await fixture();
      repository.rejectCancellation = true;
      await cancel(cubit);
      expect(cubit.state.record!.status, 'confirmed');
      expect(cubit.state.action, BookingDetailAction.cancelAndRefund);
      expect(cubit.state.pending, isNull);
      expect(cubit.state.record!.payments, hasLength(1));
      expect(cubit.state.error, contains('changed'));
    },
  );

  test(
    'cancellation read failure retires stale record and resumes refund after reload',
    () async {
      final (_, repository, cubit) = await fixture();
      repository.failCancelledRead = true;
      await cancel(cubit);
      expect(repository.records['booking']!['status'], 'cancelled');
      expect(cubit.state.record, isNull);
      expect(cubit.state.locked, isFalse);
      expect(cubit.state.error, contains('Cancellation was recorded'));
      repository.failCancelledRead = false;
      await cubit.load();
      cubit.begin(BookingDetailAction.refund);
      expect(cubit.state.action, BookingDetailAction.refund);
      expect(repository.submitted, hasLength(1));
    },
  );

  test('saved refund with a failed refresh cannot be sent again', () async {
    final (_, repository, cubit) = await fixture();
    await cancel(cubit);
    cubit.payBalance(cubit.state.payments.single.id);
    cubit.reason('Customer refund');
    repository.failCancelledRead = true;
    await cubit.submit();
    expect(repository.records['booking']!['payments'], hasLength(2));
    expect(cubit.state.record, isNull);
    expect(cubit.state.pending, isNull);
    expect(cubit.state.locked, isFalse);
    expect(cubit.state.error, contains('action was recorded'));
    repository.failCancelledRead = false;
    await cubit.load();
    expect(cubit.state.record!.refundDue, 0);
    expect(repository.submitted, hasLength(2));
  });

  test(
    'staff, unpaid, final-status and admission bookings cannot start combined flow',
    () async {
      final (_, repository, cubit) = await fixture();
      final collection = Map<String, dynamic>.from(
        (repository.records['booking']!['payments'] as List).single,
      );
      for (final scenario in ['staff', 'unpaid', 'cancelled', 'admission']) {
        repository.catalogOverride = scenario == 'staff'
            ? const BookingCatalog(canManage: true, canCollect: true)
            : ownerCatalog;
        final record = repository.records['booking']!;
        record['status'] = scenario == 'cancelled' ? 'cancelled' : 'confirmed';
        record['admission_id'] = scenario == 'admission' ? 'membership' : null;
        record['payments'] = <Map<String, dynamic>>[
          if (scenario != 'unpaid') Map<String, dynamic>.from(collection),
        ];
        await cubit.load();
        expect(cubit.state.canCancelAndRefund, isFalse, reason: scenario);
        cubit.begin(BookingDetailAction.cancelAndRefund);
        expect(cubit.state.action, BookingDetailAction.none, reason: scenario);
      }
      expect(repository.submitted, isEmpty);
    },
  );

  test(
    'late cancellation response does not open refund after workspace access changes',
    () async {
      final (workspace, repository, cubit) = await fixture();
      final response = Completer<void>();
      repository.cancellationResponse = response;
      final saving = cancel(cubit);
      final source = workspace.repository as BookingSource;
      source.value = Workspace(
        organization: source.value.organization,
        membership: const {'role': 'staff'},
        businesses: source.value.businesses,
      );
      await workspace.load();
      response.complete();
      await saving;
      expect(cubit.state.record, isNull);
      expect(cubit.state.action, BookingDetailAction.none);
    },
  );

  for (final (width, method) in [(320.0, 'cash'), (1280.0, 'upi')]) {
    testWidgets('owner cancels then records $method refund at $width pixels', (
      tester,
    ) async {
      final (workspace, repository, cubit) = await fixture();
      getIt.registerFactoryParam<BookingDetailCubit, WorkspaceCubit, String>(
        (_, _) => cubit,
      );
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              home: BookingDetailScreen(id: 'booking'),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                ),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Record refund'), findsNothing);
      final cancelButton = find.byKey(const ValueKey('booking-cancel-action'));
      await tester.ensureVisible(cancelButton);
      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
      expect(repository.submitted, isEmpty);
      Future<void> enter(String label, String value) async {
        final field = find.byWidgetPredicate(
          (w) => w is ConfigurationField && w.label == label,
        );
        await tester.ensureVisible(field);
        await tester.enterText(
          find.descendant(of: field, matching: find.byType(EditableText)),
          value,
        );
        await tester.pumpAndSettle();
      }

      await enter('Cancellation reason', 'Customer cancelled');
      await tester.ensureVisible(find.text('Confirm cancellation'));
      await tester.tap(find.text('Confirm cancellation'));
      await tester.pumpAndSettle();
      expect(cubit.state.action, BookingDetailAction.refund);
      expect(cubit.state.record!.status, 'cancelled');
      expect(repository.submitted, hasLength(1));
      expect(find.text('Refund method'), findsOneWidget);
      if (method == 'upi') {
        final picker = find.byWidgetPredicate(
          (w) => w is AppPicker && w.label == 'Refund method',
        );
        await tester.ensureVisible(picker);
        await tester.tap(picker);
        await tester.pumpAndSettle();
        await tester.tap(find.text('UPI').last);
        await tester.pumpAndSettle();
        expect(find.text('From: Refund bank'), findsOneWidget);
        await tester.tap(find.byTooltip('Change refund account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Refund bank').last);
        await tester.pumpAndSettle();
      } else {
        expect(find.text('From: Cash in hand'), findsOneWidget);
      }
      await enter('Amount · INR', '3000');
      await enter('Refund reason', 'Customer refund');
      await tester.ensureVisible(find.text('Save changes'));
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      expect(cubit.state.record!.refundDue, 0);
      expect(cubit.state.record!.status, 'cancelled');
      expect(repository.submitted, hasLength(2));
      expect(
        (repository.submitted.last.body['payments'] as List).single['method'],
        method,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
