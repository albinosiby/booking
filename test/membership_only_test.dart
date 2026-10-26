import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/cubit/expired_members_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/repositories/admission_repository.dart';
import 'package:eden_booking/modules/admissions/screens/admission_detail_screen.dart';
import 'package:eden_booking/modules/admissions/widgets/expired_members_section.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/court/models/court_coaching.dart';
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'admissions_test.dart' show AdmissionsFake, workspace, example;
import 'admission_type_selector_test.dart' show showForm;

Admission member({String status = 'expired'}) => Admission(
  id: 'membership',
  reference: 'AD-MEMBER',
  businessId: 'business',
  poolId: 'pool',
  planId: 'plan',
  customer: example().customer,
  planName: 'Monthly membership',
  kind: 'swimming',
  coach: 'Unassigned',
  mode: 'membership',
  status: status,
  start: '2030-06-01',
  expiry: '2030-06-30',
  allowance: 0,
  used: 0,
  remaining: 0,
  total: 10000,
  paid: 4000,
  balance: 6000,
  version: 1,
  duration: 60,
  time: '00:00',
  weekdays: const [],
  today: '2030-07-01',
  businessName: 'Academy',
  deletedAt: status == 'deleted' ? '2030-07-01T00:00:00Z' : null,
  deletedBy: status == 'deleted' ? 'owner' : null,
  deletionReason: status == 'deleted' ? 'Member left' : '',
  history: status == 'deleted'
      ? const [
          AdmissionEvent(
            'deleted',
            '2030-07-01T00:00:00Z',
            'Owner',
            'Member left',
          ),
        ]
      : const [],
);

class MembershipRepositoryFake extends AdmissionsFake
    implements MembershipActions {
  MembershipRepositoryFake() {
    record = member();
  }
  String? deletedReason;
  AppException? expiryError;
  List<BookingPaymentDraft>? collectedPayments;
  @override
  Future<AdmissionCatalog> catalog() async => const AdmissionCatalog(
    canManage: true,
    canAttend: true,
    canCollect: true,
    owner: true,
    businesses: [
      AdmissionBusiness(
        'business',
        'Academy',
        '2030-07-01',
        'Asia/Kolkata',
        [
          AdmissionPool('pool', 'Pool', [60], 60),
        ],
        [
          AdmissionPlan(
            'plan',
            'Monthly membership',
            'swimming',
            ['pool'],
            0,
            10000,
            null,
            'Unassigned',
            trackAttendance: false,
            expiryMode: 'after_months',
            expiryMonths: 1,
          ),
        ],
      ),
    ],
  );
  @override
  Future<AdmissionPage> expiredMembers({int cursor = 0}) async {
    if (expiryError != null) throw expiryError!;
    return AdmissionPage(record.deleted ? [] : [record], null);
  }

  @override
  Future<void> deleteMembership(
    Admission admission,
    String reason,
    String key,
  ) async {
    deletedReason = reason;
    record = member(status: 'deleted');
  }

  @override
  Future<void> payments(
    Admission admission,
    List<BookingPaymentDraft> entries,
    String kind,
    String reason,
    String key,
  ) async {
    collectedPayments = List.unmodifiable(entries);
  }
}

void main() {
  test(
    'per-plan tracking flag persists and membership-only plans serialize no attendance allowance or class fields',
    () {
      final court = CourtPlan(
        id: 'court-plan',
        trackAttendance: false,
        allowance: '',
        seats: '',
      );
      final courtJson = court.toJson();
      expect(courtJson['track_attendance'], false);
      expect(courtJson['allowance'], 0);
      expect(courtJson['class_duration_minutes'], isNull);
      expect(CourtPlan.fromJson(courtJson).trackAttendance, false);
      expect(court.copyWith(trackAttendance: true).trackAttendance, true);
      final pool = PoolPlan(
        id: 'pool-plan',
        kind: 'coaching',
        trackAttendance: false,
        allowance: '',
        seats: '',
      );
      expect(pool.toJson()['allowance'], 0);
      expect(pool.toJson()['class_seats'], isNull);
      expect(PoolPlan.fromJson(pool.toJson()).trackAttendance, false);
      expect(PoolPlan(id: 'legacy', kind: 'swimming').trackAttendance, true);
    },
  );
  testWidgets(
    'membership enrollment and renewal hide attendance and use the current plan mode',
    (tester) async {
      final session = await workspace(),
          repository = MembershipRepositoryFake(),
          cubit = AdmissionCubit(session, repository);
      addTearDown(session.close);
      addTearDown(cubit.close);
      await cubit.loadForm(renewalId: 'membership');
      await showForm(tester, cubit, width: 320, renewalId: 'membership');
      expect(cubit.state.draft.mode, 'membership');
      expect(cubit.state.draft.weekdays, isEmpty);
      expect(find.text('Attendance mode'), findsNothing);
      expect(find.textContaining('Visit duration:'), findsNothing);
      expect(find.textContaining('Membership-only: validity'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'delete membership preserves detail, history and collection controls',
    (tester) async {
      final session = await workspace(),
          repository = MembershipRepositoryFake();
      await getIt.reset();
      addTearDown(session.close);
      addTearDown(getIt.reset);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
        (value, _) => AdmissionCubit(value, repository),
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, _) => BlocProvider.value(
            value: session,
            child: MaterialApp(
              theme: AppTheme.build(Brightness.light),
              home: const AdmissionDetailScreen(id: 'membership'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sessions & attendance'), findsNothing);
      await tester.tap(find.byTooltip('Delete membership'));
      await tester.pumpAndSettle();
      expect(find.textContaining('outstanding dues are kept'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Member left');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete membership'));
      await tester.pumpAndSettle();
      expect(repository.deletedReason, 'Member left');
      expect(find.textContaining('Membership deleted.'), findsOneWidget);
      expect(find.text('Collect payment'), findsOneWidget);
      expect(find.text('Renew plan'), findsNothing);
      expect(
        find.textContaining('Membership deleted · history'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('membership collection prefills due and splits the remainder', (
    tester,
  ) async {
    final session = await workspace(), repository = MembershipRepositoryFake();
    await getIt.reset();
    addTearDown(session.close);
    addTearDown(getIt.reset);
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
      (value, _) => AdmissionCubit(value, repository),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => BlocProvider.value(
          value: session,
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light),
            home: const AdmissionDetailScreen(id: 'membership'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Collect payment'));
    await tester.tap(find.text('Collect payment'));
    await tester.pumpAndSettle();
    Finder amountFields() => find.descendant(
      of: find.byWidgetPredicate(
        (widget) =>
            widget is ConfigurationField && widget.label == 'Amount · INR',
      ),
      matching: find.byType(TextFormField),
    );
    expect(
      tester.widget<TextFormField>(amountFields().first).controller!.text,
      '60.00',
    );
    expect(repository.collectedPayments, isNull);

    await tester.enterText(amountFields().first, '20');
    await tester.ensureVisible(find.text('Add other payment'));
    await tester.tap(find.text('Add other payment'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(amountFields().last).controller!.text,
      '40.00',
    );
    expect(repository.collectedPayments, isNull);

    await tester.enterText(amountFields().last, '45');
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repository.collectedPayments, isNull);
    expect(find.text('Check the amount collected.'), findsOneWidget);

    await tester.enterText(amountFields().last, '40');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(repository.collectedPayments?.map((p) => p.minor).toList(), [
      2000,
      4000,
    ]);
    expect(tester.takeException(), isNull);
  });
  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'Home expiry actions fit $width and open renewal and collection',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(() => tester.pumpWidget(const SizedBox()));
        final repository = MembershipRepositoryFake();
        Uri? destination;
        late final GoRouter router;
        router = GoRouter(
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => Scaffold(
                body: SingleChildScrollView(
                  child: ExpiredMembersSection(
                    repository: repository,
                    canRenew: true,
                    canCollect: true,
                    showAmounts: true,
                    currency: 'INR',
                  ),
                ),
              ),
            ),
            GoRoute(
              path: '/admissions/new',
              builder: (context, state) {
                destination = state.uri;
                return const Scaffold(body: Text('Renewal form'));
              },
            ),
            GoRoute(
              path: '/admissions/:id',
              builder: (context, state) {
                destination = state.uri;
                return const Scaffold(body: Text('Payment detail'));
              },
            ),
          ],
        );
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, _) => MaterialApp.router(
              theme: AppTheme.build(Brightness.light),
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Expired members · action needed'), findsOneWidget);
        await tester.ensureVisible(find.text('Renew'));
        await tester.tap(find.text('Renew'));
        await tester.pumpAndSettle();
        expect(destination?.queryParameters['renewal_id'], 'membership');
        router.pop();
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Collect amount'));
        await tester.tap(find.text('Collect amount'));
        await tester.pumpAndSettle();
        expect(destination?.queryParameters['collect'], 'true');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        router.dispose();
      },
    );
  }
  test('expiry feed clears a deleted record on refresh', () async {
    final repository = MembershipRepositoryFake();
    final feed = ExpiredMembersCubit(repository);
    await feed.load();
    expect(feed.state.items.length, 1);
    repository.record = member(status: 'deleted');
    await feed.load();
    expect(feed.state.items, isEmpty);
    await feed.close();
  });
  test('expiry feed clears protected rows when access is revoked', () async {
    final repository = MembershipRepositoryFake();
    final feed = ExpiredMembersCubit(repository);
    await feed.load();
    expect(feed.state.items, isNotEmpty);
    repository.expiryError = const AppException(
      'Access revoked',
      code: 'FORBIDDEN',
    );
    await feed.load();
    expect(feed.state.items, isEmpty);
    expect(feed.state.error, contains('Access denied'));
    await feed.close();
  });
}
