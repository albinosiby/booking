import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/repositories/admission_repository.dart';
import 'package:eden_booking/modules/admissions/screens/admission_form_screen.dart';
import 'package:eden_booking/modules/admissions/screens/admission_detail_screen.dart';
import 'package:eden_booking/modules/admissions/screens/admissions_screen.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource;

Admission example({
  String status = 'active',
  String mode = 'flexible',
  int remaining = 25,
  int version = 1,
  String kind = 'swimming',
  List<AdmissionVisit> visits = const [],
}) => Admission(
  id: 'admission',
  reference: 'AD-TEST',
  businessId: 'business',
  poolId: 'pool',
  planId: 'plan',
  customer: const BookingCustomer(
    id: 'customer',
    name: 'Anjali',
    phone: '9876543210',
  ),
  planName: '25-day swimming',
  kind: kind,
  coach: 'Unassigned',
  mode: mode,
  status: status,
  start: '2030-06-01',
  expiry: '2030-07-31',
  allowance: 25,
  used: 25 - remaining,
  remaining: remaining,
  total: 300000,
  paid: 0,
  balance: 300000,
  version: version,
  duration: 60,
  time: '06:00',
  weekdays: const [1, 3, 5],
  today: '2030-06-04',
  localNow: '2030-06-04T06:15',
  visits: visits,
  businessName: 'Swimming',
  poolName: 'Pool 1',
);

class AdmissionsFake extends Fake implements AdmissionRepository {
  Admission record = example();
  bool uncertain = false;
  final keys = <String>[];
  Completer<Admission>? delayed;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  Future<AdmissionCatalog> catalog() async => const AdmissionCatalog(
    canManage: true,
    canAttend: true,
    canCollect: true,
    owner: true,
    businesses: [
      AdmissionBusiness(
        'business',
        'Swimming',
        '2030-06-04',
        'Asia/Kolkata',
        [
          AdmissionPool('pool', 'Pool 1', [60], 60),
        ],
        [
          AdmissionPlan(
            'plan',
            '25-day swimming',
            'swimming',
            ['pool'],
            25,
            300000,
            null,
            'Unassigned',
          ),
        ],
      ),
    ],
  );
  @override
  Future<AdmissionPage> list({
    String query = '',
    String kind = 'swimming',
    String? status,
    String? businessId,
    String? spaceId,
    String? planId,
    bool previousPlans = false,
    int cursor = 0,
  }) async => AdmissionPage(
    previousPlans ||
            kind != record.kind ||
            (businessId != null && record.businessId != businessId) ||
            (spaceId != null && record.poolId != spaceId) ||
            (planId != null && record.planId != planId)
        ? []
        : [record],
    null,
  );
  @override
  Future<Admission> detail(String id) =>
      delayed?.future ?? Future.value(record);
  @override
  Future<List<BookingCustomer>> customers(String query) async => [
    record.customer,
  ];
  @override
  Future<AdmissionPreview> preview(AdmissionDraft d) async => AdmissionPreview(
    'token',
    '2030-07-31',
    d.amountMinor ?? 300000,
    d.mode == 'fixed' ? ['2030-06-05T06:00 – 2030-06-05T07:00'] : [],
  );
  @override
  Future<String> create(
    AdmissionDraft d,
    AdmissionPreview p,
    String key,
  ) async {
    keys.add(key);
    if (uncertain) {
      throw const AppException('Connection lost', code: 'NETWORK_ERROR');
    }
    return 'new-admission';
  }

  @override
  Future<void> checkIn(Admission a, String key) async {}
  @override
  Future<void> attendance(
    Admission a,
    AdmissionVisit v,
    String attendance,
    String reason,
    String key,
  ) async {}
  @override
  Future<void> payments(
    Admission a,
    List<BookingPaymentDraft> p,
    String kind,
    String reason,
    String key,
  ) async {}
  @override
  Future<void> cancel(Admission a, String reason, String key) async {}
  @override
  Future<void> sessionChange(
    Admission a,
    AdmissionVisit v,
    String action,
    String reason,
    String key, {
    String? date,
    String? time,
  }) async {}
}

class CourtAdmissionsFake extends AdmissionsFake {
  @override
  Future<AdmissionCatalog> catalog() async => const AdmissionCatalog(
    canManage: true,
    canAttend: true,
    canCollect: true,
    owner: true,
    businesses: [
      AdmissionBusiness(
        'academy',
        'Badminton academy',
        '2030-06-04',
        'Asia/Kolkata',
        [
          AdmissionPool('court', 'Court 1', [60], 60),
        ],
        [
          AdmissionPlan(
            'batch',
            'Junior batch',
            'coaching',
            ['court'],
            12,
            300000,
            60,
            'Coach Asha',
            expiryMode: 'after_months',
            expiryMonths: 1,
            seats: 8,
            activeCount: 3,
          ),
          AdmissionPlan(
            'pass',
            'Play pass',
            'play',
            ['court'],
            20,
            200000,
            null,
            'Unassigned',
            expiryMode: 'after_months',
            expiryMonths: 2,
            activeCount: 5,
          ),
        ],
        spaceKind: 'court',
      ),
    ],
  );
}

Future<WorkspaceCubit> workspace() async {
  final w = WorkspaceCubit(BookingSource());
  await w.load();
  return w;
}

void main() {
  test(
    'renewal retains customer and gets the current plan, with no inherited payments',
    () async {
      final w = await workspace(),
          r = AdmissionsFake()
            ..record = example(status: 'expired', remaining: 7);
      final renewal = AdmissionCubit(w, r);
      await renewal.loadForm(renewalId: 'admission');
      expect(renewal.state.draft.renewedFrom, 'admission');
      expect(renewal.state.draft.customer.id, 'customer');
      expect(renewal.state.draft.planId, 'plan');
      expect(renewal.state.draft.payments, isEmpty);
      expect(renewal.state.draft.start, '2030-06-04');
      await renewal.close();
      await w.close();
    },
  );
  test(
    'uncertain enrollment locks edits and retries the same command key',
    () async {
      final w = await workspace(),
          r = AdmissionsFake(),
          c = AdmissionCubit(w, r);
      await c.loadForm();
      c.update(
        c.state.draft.copyWith(planId: 'plan', customer: r.record.customer),
      );
      await c.review();
      r.uncertain = true;
      await c.create();
      expect(c.state.locked, isTrue);
      final draft = c.state.draft;
      c.update(draft.copyWith(mode: 'fixed'));
      expect(c.state.draft, draft);
      r.uncertain = false;
      await c.retry();
      expect(r.keys.length, 2);
      expect(r.keys[0], r.keys[1]);
      expect(c.state.savedId, 'new-admission');
      expect(c.state.locked, isFalse);
      await c.close();
      await w.close();
    },
  );
  test(
    'a late detail result cannot restore data after access changes',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = AdmissionsFake()..delayed = Completer<Admission>();
      final c = AdmissionCubit(w, r);
      final load = c.loadDetail('admission');
      await Future<void>.delayed(Duration.zero);
      // Clearing the active workspace invalidates the Cubit scope.
      w.clear();
      r.delayed!.complete(example());
      await load;
      expect(c.state.detail, isNull);
      await c.close();
      await w.close();
    },
  );
  for (final width in [320.0, 900.0]) {
    testWidgets('admission form and expired detail fit ${width.toInt()}px', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await workspace(),
          r = AdmissionsFake()
            ..record = example(status: 'expired', remaining: 7);
      await getIt.reset();
      getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
        (s, _) => AdmissionCubit(s, r),
      );
      Widget app(Widget child) => ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => BlocProvider.value(
          value: w,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: child,
          ),
        ),
      );
      await tester.pumpWidget(app(const AdmissionFormScreen()));
      await tester.pumpAndSettle();
      expect(find.text('New admission'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        app(const AdmissionDetailScreen(id: 'admission')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Renew & collect'), findsOneWidget);
      expect(find.textContaining('7 unused'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await getIt.reset();
      await w.close();
    });
  }
  testWidgets('court coaching admissions use court labels', (tester) async {
    final w = await workspace(), r = CourtAdmissionsFake();
    await getIt.reset();
    getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
      (s, _) => AdmissionCubit(s, r),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => BlocProvider.value(
          value: w,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: const AdmissionFormScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Student name'), findsOneWidget);
    expect(find.text('Court'), findsWidgets);
    expect(find.text('Swimmer name'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await getIt.reset();
    await w.close();
  });
  testWidgets('admissions list and plans tab fit 320px with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final w = await workspace(), r = CourtAdmissionsFake();
    await getIt.reset();
    getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
      (s, _) => AdmissionCubit(s, r),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => BlocProvider.value(
          value: w,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const AdmissionsScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Court-only organizations offer court plans and coaching, not swimming.
    expect(find.text('Swimming'), findsNothing);
    expect(find.byTooltip('Filter admissions'), findsOneWidget);
    expect(find.byType(AppPicker), findsNothing);
    expect(find.text('Coaching'), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Play pass'), findsNothing);
    expect(find.text('Junior batch'), findsNothing);
    expect(find.text('Enroll student'), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    await tester.tap(find.text('Coaching'));
    await tester.pumpAndSettle();
    expect(find.text('Junior batch'), findsNothing);
    expect(find.byTooltip('New coaching admission'), findsOneWidget);
    expect(find.text('Enroll student'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await getIt.reset();
    await w.close();
  });
  testWidgets(
    'admission payment is optional with quick full, half or other collection at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final w = await workspace(), r = CourtAdmissionsFake();
      await getIt.reset();
      getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
        (s, _) => AdmissionCubit(s, r),
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => BlocProvider.value(
            value: w,
            child: MaterialApp(
              theme: AppTheme.build(Brightness.dark),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(1.3)),
                child: child!,
              ),
              home: const AdmissionFormScreen(
                businessId: 'academy',
                planId: 'batch',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(Finder f) async {
        await tester.ensureVisible(f);
        await tester.pumpAndSettle();
        await tester.tap(f);
        await tester.pumpAndSettle();
      }

      expect(find.text('Add other payment'), findsNothing);
      expect(find.textContaining('confirm unpaid'), findsOneWidget);
      expect(find.text('Collect full · INR 3000.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap(find.byKey(const ValueKey('admission-collect-half')));
      final amount = find.descendant(
        of: find.byWidgetPredicate(
          (w) => w is ConfigurationField && w.label == 'Amount · INR',
        ),
        matching: find.byType(EditableText),
      );
      expect(tester.widget<EditableText>(amount).controller.text, '1500.00');
      expect(find.text('Split with another method'), findsOneWidget);
      expect(find.text('Pay balance'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Removing the entry returns to the optional collection choices.
      await tap(find.byTooltip('Remove payment'));
      await tap(find.byKey(const ValueKey('admission-collect-full')));
      expect(tester.widget<EditableText>(amount).controller.text, '3000.00');
      await tap(find.byTooltip('Remove payment'));
      await tap(find.byKey(const ValueKey('admission-collect-other')));
      expect(tester.widget<EditableText>(amount).controller.text, '');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await getIt.reset();
      await w.close();
    },
  );
}
