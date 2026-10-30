import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_state.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/repositories/rest_admission_repository.dart';
import 'package:eden_booking/modules/admissions/widgets/admission_form_fields.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'admissions_test.dart' show AdmissionsFake;
import 'booking_module_test.dart' show BookingSource, FakeBookingRepository;
import 'pool_flow_audit_test.dart' show AdmissionApi;

class FeeWidgetSession extends Fake implements WorkspaceSession {
  @override
  WorkspaceState get state => const WorkspaceState(
    status: LoadStatus.ready,
    data: Workspace(
      organization: Organization(
        id: 'org',
        name: 'Eden',
        phone: '',
        currency: 'INR',
      ),
      membership: {'role': 'owner'},
    ),
  );
  @override
  Stream<WorkspaceState> get snapshots => const Stream.empty();
}

class FeePlans extends AdmissionsFake {
  FeePlans({this.collect = true});
  final bool collect;
  int previews = 0;
  final saved = <AdmissionDraft>[];
  @override
  Future<AdmissionCatalog> catalog() async => AdmissionCatalog(
    canManage: true,
    canCollect: collect,
    owner: collect,
    businesses: const [
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
            'swim',
            'Swimming plan',
            'swimming',
            ['pool'],
            25,
            250000,
            null,
            'Unassigned',
          ),
          AdmissionPlan(
            'swim-two',
            'Longer plan',
            'swimming',
            ['pool'],
            30,
            300000,
            null,
            'Unassigned',
          ),
          AdmissionPlan(
            'coach',
            'Coaching plan',
            'coaching',
            ['pool'],
            12,
            250000,
            60,
            'Alex',
          ),
        ],
      ),
    ],
  );
  @override
  Future<AdmissionPreview> preview(AdmissionDraft d) async {
    previews++;
    return AdmissionPreview(
      'preview',
      '2030-07-31',
      d.amountMinor ?? (d.planId == 'swim-two' ? 300000 : 250000),
      [],
    );
  }

  @override
  Future<String> create(
    AdmissionDraft d,
    AdmissionPreview p,
    String key,
  ) async {
    saved.add(d);
    return 'saved';
  }
}

void main() {
  for (final kind in ['swimming', 'coaching']) {
    test(
      '$kind agrees 2300 against a configured 2500, preserves partial payments and resets fee on plan change',
      () async {
        final session = WorkspaceCubit(BookingSource());
        await session.load();
        final repository = FeePlans();
        final c = AdmissionCubit(session, repository);
        await c.loadForm(
          businessId: 'business',
          poolId: 'pool',
          formKind: kind,
          customer: const BookingCustomer(name: 'Anjali', phone: '9876543210'),
        );
        expect(c.state.planAmount, 250000);
        c.planAmount('2300');
        expect(c.state.planAmount, 230000);
        c.startCollection(100000);
        expect(c.state.paymentEntry.remaining, 130000);
        c.payBalance(c.state.draft.payments.single.id);
        expect(c.state.paymentEntry.received, 230000);
        expect(c.state.paymentEntry.remaining, 0);
        await c.review();
        expect(c.state.preview!.total, 230000);
        c.planAmount('2100');
        expect(
          c.state.draft.amount,
          '2300',
        ); // Preview must be edited before changing its fee.
        await c.create();
        expect(repository.saved.single.amountMinor, 230000);
        expect(repository.saved.single.payments.single.minor, 230000);
        await c.close();
        final changed = AdmissionCubit(session, repository);
        await changed.loadForm(
          businessId: 'business',
          poolId: 'pool',
          formKind: 'swimming',
        );
        changed.planAmount('2300');
        changed.plan('swim-two');
        expect(changed.state.draft.amount, isNull);
        expect(changed.state.planAmount, 300000);
        await changed.close();
        await session.close();
      },
    );
  }

  test(
    'invalid fee and overpayment never reach preview, and unauthorized fee changes are blocked',
    () async {
      final session = WorkspaceCubit(BookingSource());
      await session.load();
      final repo = FeePlans();
      final editor = AdmissionCubit(session, repo);
      await editor.loadForm(
        businessId: 'business',
        poolId: 'pool',
        formKind: 'swimming',
        customer: const BookingCustomer(name: 'Anjali', phone: '9876543210'),
      );
      for (final value in ['', '-1', 'abc', '1.234', '1000000.01']) {
        editor.planAmount(value);
        await editor.review();
        expect(editor.state.preview, isNull);
        expect(editor.state.error, contains('valid plan amount'));
      }
      expect(repo.previews, 0);
      editor.planAmount('2300');
      editor.startCollection(250000);
      await editor.review();
      expect(editor.state.error, contains('exceeds'));
      expect(repo.previews, 0);
      await editor.close();
      final denied = AdmissionCubit(session, FeePlans(collect: false));
      await denied.loadForm(
        businessId: 'business',
        poolId: 'pool',
        formKind: 'swimming',
        customer: const BookingCustomer(name: 'Anjali', phone: '9876543210'),
      );
      denied.planAmount('2300');
      expect(denied.state.draft.amount, isNull);
      denied.update(denied.state.draft.copyWith(amount: '2300'));
      await denied.review();
      expect(denied.state.error, contains('permission'));
      await denied.close();
      await session.close();
    },
  );

  test(
    'repository sends the final fee in minor units and omits the override for unchanged clients',
    () async {
      final api = AdmissionApi(),
          repository = RestAdmissionRepository(
            AdmissionApi(),
            FakeBookingRepository(),
          );
      expect(
        repository
            .body(const AdmissionDraft())
            .containsKey('plan_amount_minor'),
        isFalse,
      );
      expect(
        repository.body(
          const AdmissionDraft(amount: '2300.50'),
        )['plan_amount_minor'],
        230050,
      );
      expect(
        () => repository.body(const AdmissionDraft(amount: '')),
        throwsException,
      );
      final transport = RestAdmissionRepository(api, FakeBookingRepository());
      await transport.create(
        const AdmissionDraft(amount: '2300'),
        const AdmissionPreview('preview', '2030-07-31', 230000, []),
        'key',
      );
      expect((api.submitted as Map)['plan_amount_minor'], 230000);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      'fee entry changes full collection and balance without a discount control; dark=$dark',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final c = AdmissionCubit(FeeWidgetSession(), FeePlans());
        addTearDown(c.close);
        await c.loadForm(
          businessId: 'business',
          poolId: 'pool',
          formKind: 'coaching',
          customer: const BookingCustomer(name: 'Anjali', phone: '9876543210'),
        );
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              theme: dark ? darkTheme() : lightTheme(),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: BlocBuilder<AdmissionCubit, AdmissionState>(
                      bloc: c,
                      builder: (_, s) => Column(
                        children: [
                          AdmissionPlanAmountField(cubit: c, state: s),
                          const SizedBox(height: 12),
                          AdmissionPaymentFields(cubit: c, state: s),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final amount = find.descendant(
          of: find.byType(AdmissionPlanAmountField),
          matching: find.byType(TextFormField),
        );
        expect(
          tester.widget<TextFormField>(amount).controller!.text,
          '2500.00',
        );
        await tester.enterText(amount, '2300');
        await tester.pumpAndSettle();
        expect(find.text('Collect full · INR 2300.00'), findsOneWidget);
        expect(find.textContaining('Discount'), findsNothing);
        await tester.tap(find.text('Collect full · INR 2300.00'));
        await tester.pumpAndSettle();
        expect(c.state.paymentEntry.received, 230000);
        expect(c.state.paymentEntry.remaining, 0);
        await c.review();
        await tester.pumpAndSettle();
        expect(c.state.preview!.total, 230000);
        expect(tester.widget<TextFormField>(amount).enabled, isFalse);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
