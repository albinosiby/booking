import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/repositories/rest_admission_repository.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_form_model.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'pool_booking_options_test.dart' show PoolPlans;
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

class AuditPlans extends PoolPlans {
  int previews = 0;
  int? authoritativeTotal;
  Object? failure;
  final savedDrafts = <AdmissionDraft>[];
  @override
  Future<AdmissionPreview> preview(AdmissionDraft d) async {
    previews++;
    return AdmissionPreview(
      'preview-$previews',
      '2030-07-31',
      authoritativeTotal ?? (d.planId == 'coach' ? 450000 : 300000),
      [],
    );
  }

  @override
  Future<String> create(
    AdmissionDraft d,
    AdmissionPreview p,
    String key,
  ) async {
    keys.add(key);
    if (failure != null) throw failure!;
    savedDrafts.add(d);
    return 'saved';
  }
}

class AdmissionApi extends Fake implements RestApiService {
  Object? submitted;
  @override
  Future<dynamic> retainedRead(
    String path, {
    Duration freshFor = const Duration(seconds: 20),
    Duration retainFor = const Duration(minutes: 15),
  }) async => {
    'currency': 'INR',
    'can_manage': true,
    'can_attend': true,
    'can_collect': true,
    'is_owner': true,
    'businesses': [],
  };
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool readOnly = false,
  }) async {
    submitted = data;
    return {'id': 'saved'};
  }
}

void main() {
  test(
    'swimming duration counter follows pool minimum, steps by 30 and leaves coaching fixed',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final c = AdmissionCubit(w, AuditPlans());
      await c.loadForm(
        businessId: 'business',
        poolId: 'pool',
        formKind: 'swimming',
      );
      expect(c.state.minimumVisitDuration, 90);
      c.adjustVisitDuration(-1);
      expect(c.state.draft.duration, 90);
      c.adjustVisitDuration(1);
      expect(c.state.draft.duration, 120);
      c.adjustVisitDuration(1);
      expect(c.state.draft.duration, 150);
      c.adjustVisitDuration(-1);
      expect(c.state.draft.duration, 120);
      c.update(c.state.draft.copyWith(duration: 105));
      expect(c.state.validVisitDuration, isFalse);
      await c.loadForm(
        businessId: 'business',
        poolId: 'pool',
        formKind: 'coaching',
      );
      c.adjustVisitDuration(1);
      expect(c.state.draft.duration, 60);
      await c.close();
      await w.close();
    },
  );

  test(
    'plan expiry uses configured days, calendar months, years or fixed date',
    () {
      AdmissionPlan plan(
        String mode, {
        int? days,
        int? months,
        int? years,
        String? date,
      }) => AdmissionPlan(
        'p',
        'Plan',
        'swimming',
        ['pool'],
        25,
        10000,
        null,
        'Unassigned',
        expiryMode: mode,
        expiryDays: days,
        expiryMonths: months,
        expiryYears: years,
        expiryDate: date,
      );
      expect(
        plan('after_start', days: 25).expiryFor('2030-06-04'),
        '2030-06-29',
      );
      expect(
        plan('after_months', months: 1).expiryFor('2030-01-31'),
        '2030-02-28',
      );
      expect(
        plan('after_years', years: 1).expiryFor('2028-02-29'),
        '2029-02-28',
      );
      expect(
        plan('fixed_date', date: '2030-12-31').expiryFor('2030-06-04'),
        '2030-12-31',
      );
    },
  );

  test(
    'Single visit keeps pool time range and confirms exactly one split-payment booking',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final b = FakeBookingRepository(flexible: true);
      b.catalogOverride = BookingCatalog(
        canView: true,
        canManage: true,
        canCollect: true,
        businesses: [
          BookingBusiness(
            id: 'business',
            name: 'Pool',
            type: 'pool',
            timezone: 'Asia/Kolkata',
            today: '2030-06-04',
            spaces: [
              BookingSpace(
                id: 'pool',
                name: 'Pool 1',
                capacity: 20,
                options: [
                  BookingOption(
                    id: 'hourly',
                    name: 'Visit',
                    kind: 'hourly',
                    durations: [60],
                    defaultDuration: 60,
                    minimumDuration: 60,
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      final c = BookingFormCubit(w, b, const BookingLaunch());
      await c.load();
      c.chooseCustomer(
        const BookingCustomer(name: 'Swimmer', phone: '9876543210'),
      );
      await c.slots();
      c.time('09:00');
      c.finishDuration(120);
      for (final payment in [
        ('cash', '100'),
        ('upi', '200'),
        ('card', '200'),
      ]) {
        c.addPayment();
        c.updatePayment(
          c.state.draft.payments.last.id,
          (p) => p.copyWith(method: payment.$1, amount: payment.$2),
        );
      }
      expect(c.state.poolMode, PoolBookingMode.singleVisit);
      await c.review();
      expect(c.state.review, isTrue);
      await c.confirm();
      expect(c.state.resultId, isNotNull);
      expect(b.submitted.length, 1);
      expect(c.state.draft.duration, 120);
      expect(c.state.draft.received, 50000);
      await c.close();
      await w.close();
    },
  );
  for (final kind in ['swimming', 'coaching']) {
    test(
      '$kind validates split payments and supports unpaid, partial and full confirmation',
      () async {
        final w = WorkspaceCubit(BookingSource());
        await w.load();
        final r = AuditPlans();
        for (final paid in [0, 10000, kind == 'coaching' ? 450000 : 300000]) {
          final c = AdmissionCubit(w, r);
          await c.loadForm(
            businessId: 'business',
            poolId: 'pool',
            formKind: kind,
            strictLocation: true,
            customer: const BookingCustomer(
              name: 'Swimmer',
              phone: '9876543210',
            ),
          );
          if (paid > 0) {
            c.update(
              c.state.draft.copyWith(
                payments: [
                  for (final method in ['cash', 'upi', 'card', 'bank_transfer'])
                    BookingPaymentDraft(
                      amount: (paid / 400).toString(),
                      method: method,
                      accountId: method == 'cash' ? null : 'bank',
                    ),
                ],
              ),
            );
          }
          await c.review();
          expect(c.state.preview, isNotNull);
          expect(c.state.paymentEntry.received, paid);
          await c.create();
          expect(c.state.savedId, 'saved');
          final count = r.keys.length;
          await c.create();
          expect(r.keys.length, count);
          expect(r.savedDrafts.last.payments.length, paid == 0 ? 0 : 4);
          await c.close();
        }
        await w.close();
      },
    );
  }
  test(
    'overpayments and invalid payments cannot pass review; server price changes are checked too',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = AuditPlans(), c = AdmissionCubit(w, r);
      await c.loadForm(
        businessId: 'business',
        poolId: 'pool',
        formKind: 'swimming',
        customer: const BookingCustomer(name: 'Swimmer', phone: '9876543210'),
      );
      c.update(
        c.state.draft.copyWith(payments: [BookingPaymentDraft(amount: '3001')]),
      );
      await c.review();
      expect(c.state.preview, isNull);
      expect(r.previews, 0);
      expect(c.state.error, contains('exceeds'));
      c.update(
        c.state.draft.copyWith(payments: [BookingPaymentDraft(amount: '0')]),
      );
      await c.review();
      expect(c.state.preview, isNull);
      expect(r.previews, 0);
      c.update(
        c.state.draft.copyWith(payments: [BookingPaymentDraft(amount: '3000')]),
      );
      r.authoritativeTotal = 290000;
      await c.review();
      expect(c.state.preview, isNull);
      expect(c.state.error, contains('current plan amount'));
      await c.close();
      await w.close();
    },
  );
  test(
    'definitive confirmation failure requires a new review; unknown result retries the same command',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = AuditPlans(), c = AdmissionCubit(w, r);
      await c.loadForm(
        businessId: 'business',
        poolId: 'pool',
        formKind: 'swimming',
        customer: const BookingCustomer(name: 'Swimmer', phone: '9876543210'),
      );
      await c.review();
      r.failure = const AppException('Plan changed', code: 'CONFLICT');
      await c.create();
      expect(c.state.preview, isNull);
      expect(c.state.locked, isFalse);
      await c.create();
      expect(r.keys.length, 1);
      await c.review();
      r.failure = const AppException('Timeout', code: 'NETWORK_ERROR');
      await c.create();
      final key = r.keys.last;
      expect(c.state.locked, isTrue);
      await c.create();
      expect(r.keys.length, 2);
      r.failure = null;
      await c.retry();
      expect(r.keys.last, key);
      expect(c.state.savedId, 'saved');
      await c.close();
      await w.close();
    },
  );
  test(
    'admission repository supplies bank mapping and serializes manual account choices and split payments',
    () async {
      final b = FakeBookingRepository()
        ..catalogOverride = const BookingCatalog(
          paymentAccounts: [
            BookingMoneyAccount('bank', 'Primary Bank', 'bank', true),
          ],
          paymentRoutes: [BookingMoneyRoute('business', 'pool', 'upi', 'bank')],
        );
      final api = AdmissionApi(), r = RestAdmissionRepository(api, b);
      final catalog = await r.catalog();
      expect(
        catalog.paymentCatalog.paymentDestination('upi', 'business', 'pool'),
        'bank',
      );
      final d = AdmissionDraft(
        businessId: 'business',
        poolId: 'pool',
        planId: 'swim',
        payments: [
          BookingPaymentDraft(method: 'cash', amount: '100'),
          BookingPaymentDraft(method: 'upi', amount: '200', accountId: 'bank'),
          BookingPaymentDraft(),
        ],
      );
      await r.create(
        d,
        const AdmissionPreview('preview', '2030-07-31', 300000, []),
        'key',
      );
      final body = api.submitted as Map;
      final payments = body['payments'] as List;
      expect(payments.length, 2);
      expect(payments[1]['account_id'], 'bank');
      expect(payments[1]['amount_minor'], 20000);
      expect(body['command_key'], 'key');
      expect(body['preview_token'], 'preview');
    },
  );
}
