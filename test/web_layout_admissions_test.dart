import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/screens/admission_detail_screen.dart';
import 'package:eden_booking/modules/admissions/screens/admission_form_screen.dart';
import 'package:eden_booking/modules/admissions/screens/admissions_screen.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'admissions_test.dart'
    show AdmissionsFake, CourtAdmissionsFake, example, workspace;

/// A fixed-schedule admission with sessions, payments and history.
Admission detailed() {
  final base = example(mode: 'fixed', remaining: 18);
  return Admission(
    id: base.id,
    reference: base.reference,
    businessId: base.businessId,
    poolId: base.poolId,
    planId: base.planId,
    customer: base.customer,
    planName: base.planName,
    kind: base.kind,
    coach: base.coach,
    mode: base.mode,
    status: base.status,
    start: base.start,
    expiry: base.expiry,
    allowance: base.allowance,
    used: base.used,
    remaining: base.remaining,
    total: 300000,
    paid: 150000,
    balance: 150000,
    version: 1,
    duration: 60,
    time: '06:00',
    weekdays: const [1, 3, 5],
    today: base.today,
    localNow: base.localNow,
    businessName: base.businessName,
    poolName: base.poolName,
    visits: [
      for (final (i, day) in ['2020-06-01', '2020-06-03', '2040-06-05'].indexed)
        AdmissionVisit(
          id: 'visit-$i',
          start: '${day}T06:00',
          end: '${day}T07:00',
          startsAt: '${day}T06:00:00Z',
          endsAt: '${day}T07:00:00Z',
          status: 'scheduled',
          attendance: i == 0 ? 'present' : 'unmarked',
          version: 1,
        ),
    ],
    payments: const [
      BookingPayment(
        id: 'payment',
        kind: 'collection',
        method: 'upi',
        amount: 150000,
        reference: '',
        localReceived: '2030-06-01T09:30',
        collector: 'Owner',
        reason: '',
      ),
    ],
    history: const [
      AdmissionEvent('created', '2030-06-01T09:30', 'Owner', ''),
      AdmissionEvent('collection', '2030-06-01T09:31', 'Owner', ''),
    ],
  );
}

Future<void> pumpDesktop(
  WidgetTester tester,
  AdmissionsFake repository,
  Widget page,
) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final w = await workspace();
  addTearDown(w.close);
  await getIt.reset();
  addTearDown(getIt.reset);
  getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
    (s, _) => AdmissionCubit(s, repository),
  );
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(1440, 1000),
      builder: (context, _) => BlocProvider.value(
        value: w,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(Brightness.dark),
          home: page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Dispose the page (and its cubit) before the workspace closes.
  addTearDown(() => tester.pumpWidget(const SizedBox()));
}

void main() {
  testWidgets('plans show optional filters, student roster and admission FAB', (
    tester,
  ) async {
    await pumpDesktop(tester, AdmissionsFake(), const AdmissionsScreen());
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('admissions-new')), findsOneWidget);
    expect(find.byTooltip('Refresh admissions'), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byTooltip('Filter admissions'), findsOneWidget);
    expect(find.byType(AppPicker), findsNothing);
    expect(find.text('Due INR 3000.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('admission-admission')), findsOneWidget);
    expect(find.text('Search name, phone or admission no.'), findsOneWidget);
    // Enrollment is available from the persistent FAB.
    expect(find.byType(AppButton), findsNothing);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('plan-plan')), findsNothing);
    expect(find.text('Enroll student'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('coaching tab shows students without package cards', (
    tester,
  ) async {
    await pumpDesktop(tester, CourtAdmissionsFake(), const AdmissionsScreen());
    expect(find.byTooltip('Filter admissions'), findsOneWidget);
    expect(find.byType(AppPicker), findsNothing);
    expect(find.text('Coaching'), findsOneWidget);
    await tester.tap(find.text('Plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coaching'));
    await tester.pumpAndSettle();
    expect(find.text('Junior batch'), findsNothing);
    expect(find.text('8 per class'), findsNothing);
    expect(find.byTooltip('New coaching admission'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admission detail puts summary beside sessions and history', (
    tester,
  ) async {
    await pumpDesktop(
      tester,
      AdmissionsFake()..record = detailed(),
      const AdmissionDetailScreen(id: 'admission'),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AppTwoPane), findsOneWidget);
    expect(find.byType(AppStatTile), findsNWidgets(4));
    expect(find.text('Sessions & attendance'), findsOneWidget);
    expect(find.text('Payments'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Collect payment'), findsOneWidget);
    expect(find.byTooltip('Refresh admission'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsOneWidget);
    expect(find.text('Present'), findsWidgets);
    // Summary column sits left of the sessions column.
    expect(
      tester.getTopLeft(find.text('25-day swimming').first).dx,
      lessThan(tester.getTopLeft(find.text('Sessions & attendance')).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('expired admission detail still offers renewal on desktop', (
    tester,
  ) async {
    await pumpDesktop(
      tester,
      AdmissionsFake()..record = example(status: 'expired', remaining: 7),
      const AdmissionDetailScreen(id: 'admission'),
    );
    expect(find.text('Renew & collect'), findsOneWidget);
    expect(find.textContaining('7 unused'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('admission form puts plan summary and review beside fields', (
    tester,
  ) async {
    await pumpDesktop(
      tester,
      CourtAdmissionsFake(),
      const AdmissionFormScreen(businessId: 'academy', planId: 'batch'),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(AppTwoPane), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admission-plan-summary')),
      findsOneWidget,
    );
    expect(find.text('Student name'), findsOneWidget);
    expect(find.text('Collect full · INR 3000.00'), findsOneWidget);
    expect(find.text('Review admission'), findsOneWidget);
    final summary = tester.getTopLeft(
      find.byKey(const ValueKey('admission-plan-summary')),
    );
    expect(
      summary.dx,
      greaterThan(tester.getTopLeft(find.text('Customer')).dx),
    );
    // Quick collection still fills the payment editor.
    await tester.tap(find.byKey(const ValueKey('admission-collect-half')));
    await tester.pumpAndSettle();
    expect(find.text('Split with another method'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
