import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/bookings/cubit/booking_form_cubit.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/models/booking_form_model.dart';
import 'package:eden_booking/modules/bookings/screens/booking_form_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'admissions_test.dart' show AdmissionsFake;
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;

class PoolPlans extends AdmissionsFake {
  int catalogReads = 0;
  @override
  Future<AdmissionCatalog> catalog() async {
    catalogReads++;
    return const AdmissionCatalog(
      paymentCatalog: BookingCatalog(
        paymentAccounts: [
          BookingMoneyAccount('bank1', 'Primary Bank', 'bank', true),
          BookingMoneyAccount('bank2', 'Pool Bank', 'bank', false),
        ],
        paymentRoutes: [BookingMoneyRoute('business', 'pool', 'upi', 'bank2')],
      ),
      canManage: true,
      canCollect: true,
      owner: true,
      businesses: [
        AdmissionBusiness(
          'business',
          'Swimming',
          '2030-06-04',
          'Asia/Kolkata',
          [
            AdmissionPool('pool', 'Pool 1', [90], 90),
          ],
          [
            AdmissionPlan(
              'swim',
              '25-day swimming',
              'swimming',
              ['pool'],
              25,
              300000,
              null,
              'Unassigned',
              expiryMode: 'after_start',
              expiryDays: 45,
            ),
            AdmissionPlan(
              'coach',
              'Coaching course',
              'coaching',
              ['pool'],
              12,
              450000,
              60,
              'Alex',
              expiryMode: 'after_months',
              expiryMonths: 1,
            ),
            AdmissionPlan(
              'other',
              'Other pool plan',
              'swimming',
              ['other-pool'],
              25,
              300000,
              null,
              'Unassigned',
            ),
          ],
        ),
      ],
    );
  }
}

void main() {
  test(
    'pool context filters plans by kind and space, preserves customer and uses configured duration',
    () async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = PoolPlans(), c = AdmissionCubit(w, r);
      const customer = BookingCustomer(name: 'Anjali', phone: '9876543210');
      await c.loadForm(
        businessId: 'business',
        poolId: 'pool',
        formKind: 'swimming',
        strictLocation: true,
        customer: customer,
      );
      expect(c.state.draft.customer, customer);
      expect(c.state.availablePlans.map((p) => p.id), ['swim']);
      expect(c.state.draft.planId, 'swim');
      expect(c.state.draft.duration, 90);
      c.plan('coach');
      expect(c.state.draft.planId, 'swim');
      await c.loadForm(
        businessId: 'business',
        poolId: 'pool',
        formKind: 'coaching',
        strictLocation: true,
        customer: customer,
      );
      expect(c.state.availablePlans.map((p) => p.id), ['coach']);
      expect(c.state.plan?.coach, 'Alex');
      expect(c.state.draft.duration, 60);
      await c.loadForm(
        businessId: 'business',
        poolId: 'missing',
        formKind: 'swimming',
        strictLocation: true,
      );
      expect(c.state.draft.poolId, isNull);
      expect(c.state.availablePlans, isEmpty);
      await c.close();
      await w.close();
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'pool options switch forms, protect payments and create only an admission $brightness',
      (tester) async {
        await getIt.reset();
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        final w = WorkspaceCubit(BookingSource());
        await w.load();
        final r = PoolPlans(), b = FakeBookingRepository(flexible: true);
        b.catalogOverride = BookingCatalog(
          canView: true,
          canManage: true,
          canCollect: true,
          businesses: [
            BookingBusiness(
              id: 'business',
              name: 'Swimming',
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
                      name: 'Single visit',
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
        late BookingFormCubit booking;
        late AdmissionCubit admission;
        getIt.registerFactoryParam<
          BookingFormCubit,
          WorkspaceSession,
          BookingLaunch
        >((session, launch) => booking = BookingFormCubit(session, b, launch));
        getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
          (session, _) => admission = AdmissionCubit(session, r),
        );
        final router = GoRouter(
          initialLocation: '/booking/new',
          routes: [
            GoRoute(
              path: '/booking/new',
              builder: (_, _) => const BookingFormScreen(),
            ),
            GoRoute(
              path: '/admissions/:id',
              builder: (_, _) => const Scaffold(body: Text('Admission saved')),
            ),
          ],
        );
        addTearDown(() async {
          router.dispose();
          await getIt.reset();
          await w.close();
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        await tester.pumpWidget(
          BlocProvider.value(
            value: w,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp.router(
                theme: AppTheme.build(brightness),
                routerConfig: router,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        booking.chooseCustomer(
          const BookingCustomer(name: 'Anjali', phone: '9876543210'),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'Swimming plan'),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Swimming plan'));
        await tester.pumpAndSettle();
        expect(find.text('New booking'), findsOneWidget);
        expect(find.text('Customer'), findsOneWidget);
        expect(find.text('Space'), findsOneWidget);
        expect(find.text('Payments'), findsOneWidget);
        expect(find.text('Expiry date'), findsOneWidget);
        expect(find.text('Date & time'), findsNothing);
        expect(admission.state.draft.customer.name, 'Anjali');
        expect(admission.state.draft.poolId, 'pool');
        expect(admission.state.draft.duration, 90);
        expect(find.text('Visit duration: 90 minutes'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Increase visit duration'));
        await tester.tap(find.byTooltip('Increase visit duration'));
        await tester.pumpAndSettle();
        expect(find.text('Visit duration: 120 minutes'), findsOneWidget);
        await tester.tap(find.byTooltip('Decrease visit duration'));
        await tester.pumpAndSettle();
        expect(admission.state.draft.duration, 90);
        expect(
          tester
              .widget<IconButton>(
                find.byWidgetPredicate(
                  (w) =>
                      w is IconButton && w.tooltip == 'Decrease visit duration',
                ),
              )
              .onPressed,
          isNull,
        );

        expect(find.text('2030-07-19'), findsOneWidget);
        admission.update(
          admission.state.draft.copyWith(mode: 'fixed', weekdays: [1, 3, 5]),
        );
        await tester.pumpAndSettle();
        expect(find.text('Start time: 06:00'), findsOneWidget);
        expect(find.text('Mon'), findsWidgets);
        admission.update(
          admission.state.draft.copyWith(mode: 'flexible', weekdays: []),
        );
        await tester.pumpAndSettle();
        expect(find.text('Start time: 06:00'), findsNothing);

        expect(tester.takeException(), isNull);
        final previous = admission;
        final metadataReads = r.catalogReads;
        await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Coaching'));
        expect(
          tester
              .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Coaching'))
              .onSelected,
          isNotNull,
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Coaching'));
        await tester.pumpAndSettle();
        expect(find.text('Change pool option?'), findsNothing);
        expect(booking.state.poolMode, PoolBookingMode.coaching);
        await tester.pump(const Duration(milliseconds: 30));
        expect(previous.isClosed, isTrue);
        expect(r.catalogReads, metadataReads);
        expect(find.text('New booking'), findsOneWidget);
        expect(find.text('Coaching plan'), findsOneWidget);
        expect(find.text('Customer'), findsOneWidget);
        expect(find.text('Space'), findsOneWidget);
        expect(find.text('Payments'), findsOneWidget);
        expect(find.text('Coach: Alex'), findsOneWidget);
        expect(admission.state.draft.planId, 'coach');
        admission.update(
          admission.state.draft.copyWith(
            payments: [BookingPaymentDraft(amount: '100')],
          ),
        );
        await tester.pumpAndSettle();
        admission.paymentUpdate(
          admission.state.draft.payments.single.id,
          (p) => p.copyWith(method: 'upi'),
        );
        await tester.pumpAndSettle();
        expect(find.text('To: Pool Bank'), findsOneWidget);
        await tester.ensureVisible(find.byTooltip('Change receiving account'));
        await tester.tap(find.byTooltip('Change receiving account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Primary Bank').last);
        await tester.pumpAndSettle();
        expect(admission.state.draft.payments.single.accountId, 'bank1');
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'Single visit'),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Single visit'));
        await tester.pumpAndSettle();
        expect(find.text('Change pool option?'), findsOneWidget);
        await tester.tap(find.text('Keep editing'));
        await tester.pumpAndSettle();
        expect(admission.state.draft.payments.length, 1);
        await tester.tap(find.widgetWithText(ChoiceChip, 'Single visit'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Change option'));
        await tester.pumpAndSettle();
        expect(find.text('New booking'), findsOneWidget);
        expect(booking.state.draft.customer.name, 'Anjali');
        expect(booking.state.draft.payments, isEmpty);
        expect(find.text('Date & time'), findsOneWidget);
        expect(find.text('Expiry date'), findsNothing);
        await tester.ensureVisible(
          find.widgetWithText(ChoiceChip, 'Swimming plan'),
        );
        await tester.tap(find.widgetWithText(ChoiceChip, 'Swimming plan'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Review admission'));
        await tester.tap(find.text('Review admission'));
        await tester.pumpAndSettle();
        expect(find.text('New booking'), findsOneWidget);
        expect(find.text('Customer'), findsOneWidget);
        expect(find.text('Space'), findsOneWidget);
        expect(find.text('Payments'), findsOneWidget);
        await tester.ensureVisible(find.text('Confirm admission'));
        await tester.tap(find.text('Confirm admission'));
        await tester.pumpAndSettle();
        expect(find.text('Admission saved'), findsOneWidget);
        expect(r.keys.length, 1);
        expect(b.submitted, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
