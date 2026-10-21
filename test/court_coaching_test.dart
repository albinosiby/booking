import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/court/cubit/court_setup_cubit.dart';
import 'package:eden_booking/modules/court/models/court_configuration.dart';
import 'package:eden_booking/modules/court/models/court_screen_models.dart';
import 'package:eden_booking/modules/court/repositories/court_repository.dart';
import 'package:eden_booking/modules/court/screens/court_setup_screen.dart';
import 'package:eden_booking/modules/team/repositories/team_coaches_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'court_setup_test.dart' show CourtSource, FakeCourtRepository;
import 'pool_setup_test.dart' show PoolSource, FakePoolRepository;

CourtConfiguration courts() => CourtConfiguration(
  courts: [
    CourtResource(id: 'c1', name: 'Court 1'),
    CourtResource(id: 'c2', name: 'Court 2'),
  ],
  plans: [
    CourtPlan(
      id: 'p1',
      name: 'Junior batch',
      courtIds: ['c1'],
      price: '3000.00',
    ),
  ],
);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  test('court plans round-trip and are omitted when absent', () {
    expect(CourtConfiguration().toJson().containsKey('plans'), isFalse);
    expect(CourtConfiguration().toJson().containsKey('coaches'), isFalse);
    final c = courts().copyWith(
      coaches: [
        CourtCoach(
          id: 'k',
          name: 'Asha',
          phone: '9876500001',
          courtIds: ['c1'],
        ),
      ],
    );
    final json = c.toJson();
    expect(json['plans'][0]['court_ids'], ['c1']);
    expect(json['plans'][0]['kind'], 'coaching');
    expect(json['plans'][0]['price_minor'], 300000);
    expect(json['coaches'][0]['court_ids'], ['c1']);
    expect(CourtConfiguration.fromJson(json), c);
  });

  test('court plan validation requires coach coverage and court hours', () {
    final c = courts();
    expect(c.validate(), isNull);
    final uncovered = c.copyWith(
      coaches: [
        CourtCoach(
          id: 'k',
          name: 'Asha',
          phone: '9876500001',
          courtIds: ['c2'],
        ),
      ],
      plans: [c.plans.single.copyWith(coachId: 'k')],
    );
    expect(uncovered.validate(), contains('coach'));
    final outside = c.copyWith(
      plans: [
        c.plans.single.copyWith(
          hours: CourtHours(opens: '05:00', closes: '23:00'),
        ),
      ],
    );
    expect(outside.validate(), contains('Court 1 hours'));
    final unpriced = c.copyWith(plans: [c.plans.single.copyWith(price: '')]);
    expect(unpriced.validate(), isNull);
    expect(unpriced.validate(complete: true), contains('price'));
  });

  test('removing a court strips it from plans and coaches', () {
    final c = courts()
        .copyWith(
          coaches: [
            CourtCoach(
              id: 'k',
              name: 'Asha',
              phone: '9876500001',
              courtIds: ['c1', 'c2'],
            ),
          ],
        )
        .withoutCourt('c1');
    expect(c.courts.map((v) => v.id), ['c2']);
    expect(c.plans.single.courtIds, isEmpty);
    expect(c.coaches.single.courtIds, ['c2']);
  });

  test('court setup cubit adds, edits and removes coaching plans', () async {
    final source = CourtSource()..configuration = courts().toJson();
    final workspace = WorkspaceCubit(source);
    await workspace.load();
    final c = CourtSetupCubit(workspace, FakeCourtRepository(source), 'courts');
    addTearDown(c.close);
    addTearDown(workspace.close);
    c.addPlan();
    expect(c.state.section, CourtSection.coaching);
    final id = c.state.selectedId!;
    expect(c.state.selectedPlan!.courtIds, ['c1']);
    c.updatePlan(id, (p) => p.copyWith(courtIds: ['c1', 'c2'], seats: '4'));
    expect(c.state.coachingModel.selected!.seats, '4');
    c.removeCourt('c2');
    expect(c.state.draft.plans.firstWhere((p) => p.id == id).courtIds, ['c1']);
    c.removePlan(id);
    expect(c.state.draft.plans.map((p) => p.id), ['p1']);
    expect(c.state.dirty, isTrue);
  });

  test(
    'Team coaches manage court coaches and court-plan assignments',
    () async {
      final source = CourtSource()..configuration = courts().toJson();
      final repository = ConfigurationTeamCoachesRepository(
        source,
        FakePoolRepository(PoolSource()),
        FakeCourtRepository(source),
      );
      var b = (await repository.load()).single;
      expect(b.court, isTrue);
      expect(b.spacesLabel, 'courts');
      expect(b.spaces.map((s) => s.name), ['Court 1', 'Court 2']);
      await repository.add(b.id, b.version, 'Asha', '9876500001');
      b = (await repository.load()).single;
      final coach = b.coaches.single.id;
      await expectLater(
        repository.assign(b.id, b.version, coach, {'p1'}),
        throwsA(isA<AppException>()),
      );
      await repository.assignSpaces(b.id, b.version, coach, {'c1'});
      b = (await repository.load()).single;
      await repository.assign(b.id, b.version, coach, {'p1'});
      final saved = CourtConfiguration.fromJson(source.configuration!);
      expect(saved.coaches.single.courtIds, ['c1']);
      expect(saved.plans.single.coachId, coach);
      expect(saved.validate(), isNull);
      b = (await repository.load()).single;
      await expectLater(
        repository.assignSpaces(b.id, b.version, coach, {'c2'}),
        throwsA(isA<AppException>()),
      );
      await repository.assignSpaces(b.id, b.version, coach, {
        'c2',
      }, removeAffectedPlans: true);
      expect(
        CourtConfiguration.fromJson(source.configuration!).plans.single.coachId,
        isNull,
      );
    },
  );

  testWidgets('Court settings open the coaching plan editor at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = CourtSource()..configuration = courts().toJson();
    getIt.registerSingleton<WorkspaceRepository>(source);
    registerFeatureDependencies(getIt);
    await getIt.unregister<CourtRepository>();
    getIt.registerSingleton<CourtRepository>(FakeCourtRepository(source));
    final workspace = WorkspaceCubit(source);
    await workspace.load();
    addTearDown(workspace.close);
    await tester.pumpWidget(
      BlocProvider.value(
        value: workspace,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (context, child) => MaterialApp(
            theme: darkTheme(),
            home: const CourtSetupScreen(businessId: 'courts'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final section = find.byKey(const ValueKey('court-section-coaching'));
    await tester.ensureVisible(section);
    await tester.tap(section);
    await tester.pumpAndSettle();
    expect(find.text('Junior batch'), findsOneWidget);
    await tester.tap(find.text('Junior batch'));
    await tester.pumpAndSettle();
    expect(find.text('Maximum students per class'), findsWidgets);
    expect(find.text('Unassigned'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // Court plans sell play days without coaching-only fields.
    await tester.tap(find.text('Back to list'));
    await tester.pumpAndSettle();
    final add = find.text('Add court plan');
    await tester.ensureVisible(add);
    await tester.tap(add);
    await tester.pumpAndSettle();
    expect(find.text('Number of play days'), findsWidgets);
    expect(find.text('Maximum students per class'), findsNothing);
    expect(find.text('Allowed playing days and times'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test(
    'court play plans omit coaching fields and stay out of coach assignment',
    () async {
      final play = CourtPlan(
        id: 'play',
        kind: 'play',
        name: 'Play pass',
        courtIds: ['c1'],
        price: '2000.00',
        coachId: 'ignored',
      );
      final json = play.toJson();
      expect(json['kind'], 'play');
      expect(json['class_duration_minutes'], isNull);
      expect(json['class_seats'], isNull);
      expect(json['coach_id'], isNull);
      expect(CourtPlan.fromJson(json).coaching, isFalse);
      final config = courts().copyWith(plans: [...courts().plans, play]);
      expect(config.validate(), isNull);
      final source = CourtSource()..configuration = config.toJson();
      final repository = ConfigurationTeamCoachesRepository(
        source,
        FakePoolRepository(PoolSource()),
        FakeCourtRepository(source),
      );
      final b = (await repository.load()).single;
      expect(b.plans.map((p) => p.id), ['p1']);
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final c = CourtSetupCubit(
        workspace,
        FakeCourtRepository(source),
        'courts',
      );
      addTearDown(c.close);
      addTearDown(workspace.close);
      c.addPlan(coaching: false);
      expect(c.state.selectedPlan!.kind, 'play');
      expect(c.state.selectedPlan!.name, 'Court plan 2');
    },
  );
}
