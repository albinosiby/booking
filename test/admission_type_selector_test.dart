import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/screens/admission_form_screen.dart';
import 'package:eden_booking/modules/admissions/widgets/admission_form_fields.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'admissions_test.dart' show AdmissionsFake, example, workspace;

class AdmissionTypeRepository extends AdmissionsFake {
  @override
  Future<AdmissionCatalog> catalog() async => const AdmissionCatalog(
    canManage: true,
    canAttend: true,
    canCollect: true,
    businesses: [
      AdmissionBusiness(
        'business',
        'Swim academy',
        '2030-06-04',
        'Asia/Kolkata',
        [
          AdmissionPool('pool', 'Main pool', [60], 60),
          AdmissionPool('training', 'Training pool', [60], 60),
        ],
        [
          AdmissionPlan(
            'plan',
            'Monthly access',
            'swimming',
            ['pool'],
            25,
            300000,
            null,
            'Unassigned',
          ),
          AdmissionPlan(
            'coaching',
            'Technique coaching',
            'coaching',
            ['pool', 'training'],
            12,
            400000,
            90,
            'Coach Asha',
          ),
        ],
      ),
    ],
  );
}

Future<void> showForm(
  WidgetTester tester,
  AdmissionCubit cubit, {
  double width = 390,
  String? renewalId,
}) async {
  tester.view.physicalSize = Size(width, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (context, _) => MaterialApp(
        theme: AppTheme.build(Brightness.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(width == 320 ? 1.3 : 1)),
          child: child!,
        ),
        home: AdmissionFormScreen(controller: cubit, renewalId: renewalId),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

AppPicker typePicker(WidgetTester tester) =>
    tester.widget<AppPicker>(find.byKey(const ValueKey('admission-type')));

Future<void> chooseType(WidgetTester tester, String label) async {
  final picker = find.byKey(const ValueKey('admission-type'));
  await tester.ensureVisible(picker);
  await tester.pumpAndSettle();
  await tester.tap(picker);
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Admission coachingRenewal() {
  final a = example(kind: 'coaching');
  return Admission(
    id: a.id,
    reference: a.reference,
    businessId: a.businessId,
    poolId: a.poolId,
    planId: 'coaching',
    customer: a.customer,
    planName: 'Technique coaching',
    kind: a.kind,
    coach: 'Coach Asha',
    mode: a.mode,
    status: a.status,
    start: a.start,
    expiry: a.expiry,
    allowance: a.allowance,
    used: a.used,
    remaining: a.remaining,
    total: a.total,
    paid: a.paid,
    balance: a.balance,
    version: a.version,
    duration: 90,
    time: a.time,
    weekdays: a.weekdays,
  );
}

void main() {
  for (final width in [320.0, 1440.0]) {
    testWidgets(
      'admission type switches matching plans at ${width.toInt()}px',
      (tester) async {
        final session = await workspace();
        final cubit = AdmissionCubit(session, AdmissionTypeRepository());
        addTearDown(session.close);
        addTearDown(cubit.close);
        await cubit.loadForm(
          formKind: 'plans',
          businessId: 'business',
          poolId: 'pool',
        );
        cubit.update(
          cubit.state.draft.copyWith(
            customer: const BookingCustomer(
              name: 'Anjali',
              phone: '9876543210',
            ),
            mode: 'fixed',
            time: '08:00',
            weekdays: const [1, 3],
            duration: 120,
          ),
        );
        final original = cubit.state.draft;
        await showForm(tester, cubit, width: width);
        expect(typePicker(tester).items.map((item) => item.label), [
          'Plan',
          'Coaching',
        ]);
        await chooseType(tester, 'Coaching');
        expect(cubit.state.formKind, 'coaching');
        expect(cubit.state.draft.planId, isNull);
        expect(cubit.state.draft.duration, 60);
        expect(cubit.state.draft.customer, original.customer);
        expect(cubit.state.draft.businessId, original.businessId);
        expect(cubit.state.draft.poolId, original.poolId);
        expect(cubit.state.draft.start, original.start);
        expect(cubit.state.draft.mode, original.mode);
        expect(cubit.state.draft.time, original.time);
        expect(cubit.state.draft.weekdays, original.weekdays);
        final planPicker = tester.widget<AppPicker>(
          find.byWidgetPredicate(
            (widget) => widget is AppPicker && widget.label == 'Coaching plan',
          ),
        );
        expect(planPicker.items.map((item) => item.value), ['coaching']);
        expect(
          planPicker.items.single.label,
          'Technique coaching · INR 4000.00',
        );
        cubit.plan('coaching');
        await tester.pumpAndSettle();
        expect(cubit.state.draft.duration, 90);
        await chooseType(tester, 'Plan');
        expect(cubit.state.formKind, 'plans');
        expect(cubit.state.draft.planId, isNull);
        expect(cubit.state.draft.duration, 60);
        expect(cubit.state.availablePlans.map((plan) => plan.id), ['plan']);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('empty category still lets the user choose another type', (
    tester,
  ) async {
    final session = await workspace();
    final cubit = AdmissionCubit(session, AdmissionTypeRepository());
    addTearDown(session.close);
    addTearDown(cubit.close);
    await cubit.loadForm(
      formKind: 'plans',
      businessId: 'business',
      poolId: 'training',
    );
    await showForm(tester, cubit);
    expect(find.text('No access plans'), findsOneWidget);
    expect(typePicker(tester).enabled, isTrue);
    await chooseType(tester, 'Coaching');
    expect(find.text('No access plans'), findsNothing);
    expect(find.text('Coaching plan'), findsOneWidget);
    expect(cubit.state.draft.poolId, 'training');
    expect(tester.takeException(), isNull);
  });

  for (final (planId, kind, label, expectedPlans) in [
    ('removed-plan', 'plans', 'Plan', ['plan']),
    ('coaching', 'coaching', 'Coaching plan', ['coaching']),
  ]) {
    testWidgets('untyped $planId prefill resolves a matching admission type', (
      tester,
    ) async {
      final session = await workspace();
      final cubit = AdmissionCubit(session, AdmissionTypeRepository());
      addTearDown(session.close);
      addTearDown(cubit.close);
      await cubit.loadForm(
        businessId: 'business',
        poolId: 'pool',
        planId: planId,
      );
      await showForm(tester, cubit);
      expect(cubit.state.formKind, kind);
      expect(typePicker(tester).value, kind);
      final planPicker = tester.widget<AppPicker>(
        find.byWidgetPredicate(
          (widget) => widget is AppPicker && widget.label == label,
        ),
      );
      expect(planPicker.items.map((item) => item.value), expectedPlans);
      if (planId == 'coaching') {
        expect(cubit.state.draft.planId, 'coaching');
        expect(cubit.state.draft.duration, 90);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('renewal keeps original type and disables changing it', (
    tester,
  ) async {
    final session = await workspace();
    final repository = AdmissionTypeRepository()..record = coachingRenewal();
    final cubit = AdmissionCubit(session, repository);
    addTearDown(session.close);
    addTearDown(cubit.close);
    await cubit.loadForm(renewalId: 'admission', formKind: 'plans');
    await showForm(tester, cubit, renewalId: 'admission');
    expect(find.text('Renew admission'), findsOneWidget);
    expect(typePicker(tester).value, 'coaching');
    expect(typePicker(tester).enabled, isFalse);
    cubit.admissionType('plans');
    expect(cubit.state.formKind, 'coaching');
    expect(cubit.state.draft.planId, 'coaching');
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded booking schedule keeps its existing type controls', (
    tester,
  ) async {
    final session = await workspace();
    final cubit = AdmissionCubit(session, AdmissionTypeRepository());
    addTearDown(session.close);
    addTearDown(cubit.close);
    await cubit.loadForm(formKind: 'coaching');
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: Scaffold(
            body: SingleChildScrollView(
              child: AdmissionScheduleFields(cubit: cubit, state: cubit.state),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Admission type'), findsNothing);
    final picker = tester.widget<AppPicker>(
      find.byWidgetPredicate(
        (widget) => widget is AppPicker && widget.label == 'Plan',
      ),
    );
    expect(picker.items.single.label, contains(' · Coaching · '));
    expect(tester.takeException(), isNull);
  });
}
