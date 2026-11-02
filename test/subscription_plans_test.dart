import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_state.dart';
import 'package:eden_booking/modules/admissions/cubit/payment_reminders_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/repositories/admission_repository.dart';
import 'package:eden_booking/modules/admissions/repositories/rest_admission_repository.dart';
import 'package:eden_booking/modules/admissions/widgets/admission_form_fields.dart';
import 'package:eden_booking/modules/admissions/widgets/admission_slot_chart.dart';
import 'package:eden_booking/modules/admissions/widgets/subscription_sections.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/court/models/court_configuration.dart';
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/notifications/models/booking_notification.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'admissions_test.dart' show AdmissionsFake, example, workspace;
import 'booking_module_test.dart' show FakeBookingRepository;
import 'pool_flow_audit_test.dart' show AdmissionApi;

const monthly = AdmissionSubscription(
  monthly: 150000,
  months: 3,
  fees: [
    AdmissionFee('2030-06-01', 150000),
    AdmissionFee('2030-07-01', 150000),
    AdmissionFee('2030-08-01', 150000),
  ],
);

class SubscriptionFake extends AdmissionsFake implements MembershipActions {
  List<Admission> dueSoon = const [], unpaid = const [];
  final collected = <(String, List<BookingPaymentDraft>, String)>[];
  AppException? collectError;
  bool subscriptionsOn = true;
  @override
  Future<AdmissionCatalog> catalog() async => AdmissionCatalog(
    canManage: true,
    canAttend: true,
    canCollect: true,
    owner: true,
    businesses: [
      AdmissionBusiness(
        'business',
        'Badminton club',
        '2030-06-01',
        'Asia/Kolkata',
        const [
          AdmissionPool(
            'court',
            'Court 1',
            [60],
            60,
            openDays: [1, 2, 3, 4, 5, 6, 7],
            opensAt: '06:00',
            closesAt: '22:00',
          ),
        ],
        const [],
        spaceKind: 'court',
        subscriptions: subscriptionsOn,
      ),
    ],
  );
  @override
  Future<AdmissionPage> paymentReminders(
    String group, {
    int cursor = 0,
  }) async => AdmissionPage(group == 'due_soon' ? dueSoon : unpaid, null);
  @override
  Future<void> collectDue(
    Admission admission,
    List<BookingPaymentDraft> payments,
    String key,
  ) async {
    collected.add((admission.id, payments, key));
    final error = collectError;
    if (error != null) throw error;
  }

  @override
  Future<AdmissionPage> expiredMembers({int cursor = 0}) async =>
      const AdmissionPage([], null);
  @override
  Future<void> deleteMembership(
    Admission admission,
    String reason,
    String key,
  ) async {}
}

Admission term({
  String id = 'term',
  String status = 'active',
  int paid = 80000,
  int owed = 70000,
}) {
  final base = example(status: status, mode: 'fixed', kind: 'play');
  return Admission(
    id: id,
    reference: 'AD-$id',
    businessId: 'business',
    poolId: 'court',
    planId: subscriptionPlanId,
    customer: const BookingCustomer(
      id: 'customer',
      name: 'Rahul',
      phone: '9876543210',
    ),
    planName: 'Subscription',
    kind: 'play',
    coach: 'Unassigned',
    mode: 'fixed',
    status: status,
    start: '2030-06-01',
    expiry: '2030-09-01',
    allowance: 28,
    used: 0,
    remaining: 28,
    total: 450000,
    paid: paid,
    balance: 450000 - paid,
    version: 1,
    duration: 120,
    time: '17:00',
    weekdays: const [6, 7],
    businessName: 'Badminton club',
    poolName: 'Court 1',
    today: base.today,
    subscription: monthly,
    dueNow: paid + owed,
    owedNow: owed,
    nextDueOn: '2030-07-01',
    nextDue: 150000,
  );
}

void main() {
  test(
    'subscription form: months or custom days, monthly fee, and the request it sends',
    () async {
      final w = await workspace(),
          r = SubscriptionFake(),
          c = AdmissionCubit(w, r);
      await c.loadForm(
        formKind: 'subscription',
        businessId: 'business',
        poolId: 'court',
        date: '2030-06-01',
      );
      final s = c.state;
      expect(s.subscription, isTrue);
      expect(s.draft.planId, subscriptionPlanId);
      expect(s.draft.mode, 'fixed');
      expect(s.draft.months, 1);
      expect(s.plan!.kind, 'play');
      expect(s.availablePlans, isEmpty);
      expect(s.planAmountError, 'Enter the monthly fee.');
      expect(s.expiry, '2030-07-01');
      expect(s.endDurations.first, 60);

      c.planAmount('1500');
      c.update(c.state.draft.copyWith(months: 3, weekdays: [6, 7]));
      expect(c.state.planAmount, 450000);
      expect(c.state.expiry, '2030-09-01');
      expect(c.state.planAmountError, isNull);
      final request = slotChartRequest(c.state)!;
      expect(request.toJson()['subscription'], {'months': 3, 'ends_on': null});
      expect(request.toJson().containsKey('plan_id'), isFalse);

      c.update(c.state.draft.copyWith(endsOn: '2030-06-20'));
      expect(c.state.planAmount, 150000);
      expect(c.state.expiry, '2030-06-20');

      final body = RestAdmissionRepository(
        AdmissionApi(),
        FakeBookingRepository(),
      ).body(c.state.draft);
      expect(body.containsKey('plan_id'), isFalse);
      expect(body.containsKey('plan_amount_minor'), isFalse);
      expect(body['subscription'], {
        'monthly_minor': 150000,
        'months': null,
        'ends_on': '2030-06-20',
      });
      await c.close();

      // Renewing keeps the monthly fee, length and slot.
      r.record = term(status: 'completed');
      final renewal = AdmissionCubit(w, r);
      await renewal.loadForm(renewalId: 'term');
      expect(renewal.state.subscription, isTrue);
      expect(renewal.state.draft.amount, '1500.00');
      expect(renewal.state.draft.months, 3);
      expect(renewal.state.draft.duration, 120);
      expect(renewal.state.draft.weekdays, [6, 7]);
      await renewal.close();
      await w.close();
    },
  );

  testWidgets('subscription form offers months and custom days, not plans', (
    tester,
  ) async {
    final w = await tester.runAsync(workspace),
        r = SubscriptionFake(),
        c = AdmissionCubit(w!, r);
    await tester.runAsync(
      () => c.loadForm(
        formKind: 'subscription',
        businessId: 'business',
        poolId: 'court',
        date: '2030-06-01',
      ),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: BlocBuilder<AdmissionCubit, AdmissionState>(
                bloc: c,
                builder: (context, s) => Column(
                  children: [
                    AdmissionScheduleFields(cubit: c, state: s),
                    AdmissionPlanAmountField(cubit: c, state: s),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Attendance mode'), findsNothing);
    expect(find.text('Monthly fee (INR)'), findsOneWidget);
    final three = find.byKey(const ValueKey('subscription-months-3'));
    await tester.ensureVisible(three);
    await tester.tap(three);
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.state.draft.months, 3);
    final weekends = find.byKey(const ValueKey('subscription-days-weekends'));
    await tester.ensureVisible(weekends);
    await tester.tap(weekends);
    await tester.pump(const Duration(milliseconds: 400));
    expect(c.state.draft.weekdays, [6, 7]);
    expect(find.byKey(const ValueKey('subscription-summary')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await c.close();
      await w.close();
    });
  });

  test('monthly fees fill in order and fee pushes open the subscription', () {
    final a = term(paid: 200000);
    final cover = feeCoverage(a);
    expect([for (final c in cover) c.paid], [150000, 50000, 0]);
    final push = BookingNotification.fromData({
      'event_id': '11111111-1111-4111-8111-111111111111',
      'admission_id': '22222222-2222-4222-8222-222222222222',
      'recipient_user_id': 'user',
      'event_type': 'subscription_fee_due',
    });
    expect(push?.route, '/admissions/22222222-2222-4222-8222-222222222222');
    expect(push?.toData()['admission_id'], push?.admissionId);
    expect(
      BookingNotification.fromData({
        'event_id': '11111111-1111-4111-8111-111111111111',
        'recipient_user_id': 'user',
        'event_type': 'subscription_fee_due',
      }),
      isNull,
    );
  });

  test(
    'an unconfirmed Home collection retries with the same command key',
    () async {
      final r = SubscriptionFake()
        ..unpaid = [term(id: 'old', status: 'expired')];
      final c = PaymentRemindersCubit(r, 'unpaid');
      await c.load();
      r.collectError = const AppException('Offline', code: 'NETWORK');
      await c.collect(c.state.items.single, [
        BookingPaymentDraft(amount: '300'),
      ]);
      expect(c.state.uncertainId, 'old');
      // A new collection is refused until the unknown one is resolved.
      await c.collect(c.state.items.single, [
        BookingPaymentDraft(amount: '100'),
      ]);
      expect(r.collected.length, 1);
      r.collectError = null;
      await c.retry();
      expect(r.collected.length, 2);
      expect(r.collected[1].$3, r.collected[0].$3);
      expect(r.collected[1].$2.single.minor, 30000);
      expect(c.state.uncertainId, isNull);
      r.collectError = const AppException('Changed', code: 'CONFLICT');
      await c.collect(c.state.items.single, [
        BookingPaymentDraft(amount: '50'),
      ]);
      expect(c.state.uncertainId, isNull);
      expect(c.state.error, isNotNull);
      await c.close();
    },
  );

  test('Configure saves the Subscriptions switch for courts and pools', () {
    expect(
      CourtConfiguration().toJson().containsKey('subscriptions_enabled'),
      false,
    );
    final court = CourtConfiguration(subscriptions: true).toJson();
    expect(court['subscriptions_enabled'], true);
    expect(CourtConfiguration.fromJson(court).subscriptions, true);
    final pool = PoolConfiguration(subscriptions: true).toJson();
    expect(pool['subscriptions_enabled'], true);
    expect(PoolConfiguration.fromJson(pool).subscriptions, true);
    expect(
      PoolConfiguration().toJson().containsKey('subscriptions_enabled'),
      false,
    );
    final space = {
      'id': 'b',
      'name': 'Club',
      'type': 'badminton',
      'timezone': 'UTC',
      'today': '2030-06-01',
      'resources': <Object>[],
    };
    expect(BookingBusiness.fromJson(space).subscriptions, false);
    expect(
      BookingBusiness.fromJson({...space, 'subscriptions': true}).subscriptions,
      true,
    );
  });

  test('a space with Subscriptions off refuses a new subscription', () async {
    final w = await workspace(),
        r = SubscriptionFake()..subscriptionsOn = false,
        c = AdmissionCubit(w, r);
    await c.loadForm(
      formKind: 'subscription',
      businessId: 'business',
      poolId: 'court',
      date: '2030-06-01',
    );
    expect(c.state.business!.subscriptions, false);
    c.update(
      c.state.draft.copyWith(
        customer: const BookingCustomer(name: 'Rahul', phone: '9000000001'),
        weekdays: const [6, 7],
        time: '17:00',
        amount: '1500',
      ),
    );
    await c.review();
    expect(c.state.error, contains('Subscriptions are off for this space'));
    expect(c.state.preview, isNull);
    await c.close();
  });
}
