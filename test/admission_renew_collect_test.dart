import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/screens/admission_form_screen.dart';
import 'admissions_test.dart' show AdmissionsFake, example, workspace;

class RenewalRepository extends AdmissionsFake {
  RenewalRepository({
    this.manage = true,
    this.collect = true,
    this.fee = 250000,
  }) {
    record = example(status: 'expired');
  }
  final bool manage, collect;
  final int fee;
  int previews = 0;
  final commands = <AdmissionDraft>[];
  @override
  Future<AdmissionCatalog> catalog() async => AdmissionCatalog(
    canManage: manage,
    canCollect: collect,
    owner: manage && collect,
    businesses: [
      AdmissionBusiness(
        'business',
        'Swimming',
        '2030-06-04',
        'Asia/Kolkata',
        const [
          AdmissionPool('pool', 'Pool 1', [60], 60),
        ],
        [
          AdmissionPlan(
            'plan',
            'Current plan',
            'swimming',
            ['pool'],
            25,
            fee,
            null,
            'Unassigned',
            expiryMode: 'after_months',
            expiryMonths: 1,
          ),
          const AdmissionPlan(
            'other',
            'Longer plan',
            'swimming',
            ['pool'],
            30,
            300000,
            null,
            'Unassigned',
            expiryMode: 'after_months',
            expiryMonths: 2,
          ),
        ],
      ),
    ],
  );
  @override
  Future<AdmissionPreview> preview(AdmissionDraft draft) async {
    previews++;
    return AdmissionPreview(
      'token',
      '2030-07-04',
      draft.amountMinor ?? (draft.planId == 'other' ? 300000 : fee),
      [],
    );
  }

  @override
  Future<String> create(
    AdmissionDraft draft,
    AdmissionPreview preview,
    String key,
  ) async {
    commands.add(draft);
    return super.create(draft, preview, key);
  }
}

void main() {
  test(
    'combined renewal prefills only the current new fee and creates nothing before confirmation',
    () async {
      final session = await workspace(), repository = RenewalRepository();
      final cubit = AdmissionCubit(session, repository);
      addTearDown(cubit.close);
      addTearDown(session.close);
      await cubit.loadForm(renewalId: 'admission', collectOnRenewal: true);
      expect(cubit.state.renewAndCollect, isTrue);
      expect(cubit.state.draft.renewedFrom, 'admission');
      expect(cubit.state.draft.customer.id, 'customer');
      expect(cubit.state.draft.start, '2030-06-04');
      expect(cubit.state.expiry, '2030-07-04');
      expect(cubit.state.paymentEntry.received, 250000);
      expect(cubit.state.paymentEntry.remaining, 0);
      expect(repository.record.balance, 300000);
      expect(repository.commands, isEmpty);
      await cubit.review();
      expect(cubit.state.preview?.total, 250000);
      expect(repository.commands, isEmpty);
      await Future.wait([cubit.create(), cubit.create()]);
      expect(repository.commands, hasLength(1));
      expect(repository.commands.single.payments.single.minor, 250000);
      expect(repository.record.balance, 300000);
    },
  );

  test(
    'default collection follows fee and plan changes while explicit partial payments remain editable',
    () async {
      final session = await workspace(), repository = RenewalRepository();
      final cubit = AdmissionCubit(session, repository);
      addTearDown(cubit.close);
      addTearDown(session.close);
      await cubit.loadForm(renewalId: 'admission', collectOnRenewal: true);
      final id = cubit.state.draft.payments.single.id;
      cubit.paymentUpdate(
        id,
        (p) => p.copyWith(method: 'upi', reference: 'transfer'),
      );
      cubit.planAmount('');
      cubit.planAmount('2300');
      expect(cubit.state.paymentEntry.received, 230000);
      expect(cubit.state.draft.payments.single.method, 'upi');
      cubit.plan('other');
      expect(cubit.state.paymentEntry.received, 300000);
      cubit.paymentUpdate(id, (p) => p.copyWith(amount: '1000'));
      cubit.planAmount('2800');
      expect(cubit.state.paymentEntry.received, 100000);
      expect(cubit.state.paymentEntry.remaining, 180000);
      await cubit.review();
      expect(cubit.state.preview?.total, 280000);
      expect(cubit.state.error, isNull);
    },
  );

  test(
    'combined renewal requires a collection for a positive fee and rejects excess payment',
    () async {
      final session = await workspace(), repository = RenewalRepository();
      final cubit = AdmissionCubit(session, repository);
      addTearDown(cubit.close);
      addTearDown(session.close);
      await cubit.loadForm(renewalId: 'admission', collectOnRenewal: true);
      cubit.update(cubit.state.draft.copyWith(payments: []));
      await cubit.review();
      expect(cubit.state.error, contains('payment collected'));
      expect(repository.previews, 0);
      cubit.startCollection(260000);
      await cubit.review();
      expect(cubit.state.preview, isNull);
      expect(cubit.state.error, isNotNull);
      expect(repository.commands, isEmpty);
    },
  );

  test(
    'zero-fee renewal creates no payment and ordinary renewal remains optional',
    () async {
      final session = await workspace(), repository = RenewalRepository(fee: 0);
      final cubit = AdmissionCubit(session, repository);
      addTearDown(cubit.close);
      addTearDown(session.close);
      await cubit.loadForm(renewalId: 'admission', collectOnRenewal: true);
      expect(cubit.state.draft.payments, isEmpty);
      await cubit.review();
      expect(cubit.state.preview?.total, 0);
      await cubit.create();
      expect(repository.commands.single.payments, isEmpty);
      final ordinary = AdmissionCubit(session, RenewalRepository());
      addTearDown(ordinary.close);
      await ordinary.loadForm(renewalId: 'admission');
      expect(ordinary.state.renewAndCollect, isFalse);
      expect(ordinary.state.draft.payments, isEmpty);
    },
  );

  for (final manage in [false, true]) {
    test(
      'combined renewal refuses missing ${manage ? 'collection' : 'management'} permission',
      () async {
        final session = await workspace(),
            repository = RenewalRepository(manage: manage, collect: !manage);
        final cubit = AdmissionCubit(session, repository);
        addTearDown(cubit.close);
        addTearDown(session.close);
        await cubit.loadForm(renewalId: 'admission', collectOnRenewal: true);
        expect(cubit.state.renewAndCollect, isFalse);
        expect(cubit.state.error, isNotNull);
        expect(cubit.state.draft.payments, isEmpty);
        expect(repository.commands, isEmpty);
      },
    );
  }

  test(
    'active plans cannot use combined renewal and uncertain retries keep the same payment command',
    () async {
      final session = await workspace(),
          repository = RenewalRepository()..record = example();
      final cubit = AdmissionCubit(session, repository);
      addTearDown(cubit.close);
      addTearDown(session.close);
      await cubit.loadForm(renewalId: 'admission', collectOnRenewal: true);
      expect(cubit.state.error, contains('expired or completed'));
      repository.record = example(status: 'expired');
      await cubit.loadForm(renewalId: 'admission', collectOnRenewal: true);
      await cubit.review();
      repository.uncertain = true;
      await cubit.create();
      expect(cubit.state.locked, isTrue);
      final payment = cubit.state.draft.payments.single;
      repository.uncertain = false;
      await cubit.retry();
      expect(repository.keys, hasLength(2));
      expect(repository.keys.toSet(), hasLength(1));
      expect(repository.commands.last.payments.single, same(payment));
    },
  );

  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'combined renewal reviews and confirms the new fee at $width pixels',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final session = await workspace(), repository = RenewalRepository();
        final cubit = AdmissionCubit(session, repository);
        addTearDown(cubit.close);
        addTearDown(session.close);
        await cubit.loadForm(renewalId: 'admission', collectOnRenewal: true);
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              home: AdmissionFormScreen(
                controller: cubit,
                renewalId: 'admission',
                collectOnRenewal: true,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Renew & collect'), findsOneWidget);
        expect(find.textContaining('Earlier outstanding fees'), findsOneWidget);
        final amount = find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is ConfigurationField && w.label == 'Amount · INR',
          ),
          matching: find.byType(EditableText),
        );
        expect(tester.widget<EditableText>(amount).controller.text, '2500.00');
        await tester.ensureVisible(find.text('Review renewal'));
        await tester.tap(find.text('Review renewal'));
        await tester.pumpAndSettle();
        expect(find.text('Collecting INR 2500.00'), findsOneWidget);
        expect(find.text('Balance due INR 0.00'), findsOneWidget);
        expect(repository.commands, isEmpty);
        final confirm = find.widgetWithText(AppButton, 'Renew & collect');
        expect(confirm, findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
