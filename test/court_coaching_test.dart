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
import 'package:eden_booking/modules/coaching/repositories/coach_api.dart';
import 'package:eden_booking/modules/team/repositories/team_coaches_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'court_setup_test.dart' show CourtSource, FakeCourtRepository;

/// A court workspace whose team has one coach, Asha, on [courts].
class CourtTeamSource extends CourtSource {
  List<String> courts = ['c2'];
  @override
  Future<Map<String, dynamic>> team() async => {
    'members': [
      {
        'id': 'asha',
        'display_name': 'Asha',
        'role': 'staff',
        'active': true,
        'permissions': ['coach'],
        'assignments': [
          {'business_id': 'courts', 'resource_ids': courts},
        ],
      },
    ],
    'invitations': [],
  };
}

class CourtCoachApi extends Fake implements CoachApi {
  CourtCoachApi(this.source);
  final CourtSource source;
  @override
  Future<void> assignPlans(
    String businessId,
    int version,
    Map<String, String?> coaches,
  ) async {
    source.configuration = {
      ...source.configuration!,
      'plans': [
        for (final p in source.configuration!['plans'] as List)
          coaches.containsKey(p['id'])
              ? {...p, 'coach_id': coaches[p['id']]}
              : p,
      ],
    };
    source.version++;
  }
}

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
    final c = courts();
    final json = c.toJson();
    expect(json['plans'][0]['court_ids'], ['c1']);
    expect(json['plans'][0]['kind'], 'coaching');
    expect(json['plans'][0]['price_minor'], 300000);
    expect(json.containsKey('coaches'), isFalse);
    expect(CourtConfiguration.fromJson(json), c);
    // Old coach contacts are dropped and their plans become Unassigned.
    final legacy = c
        .copyWith(plans: [c.plans.single.copyWith(coachId: 'k')])
        .toJson();
    legacy['coaches'] = [
      {
        'id': 'k',
        'name': 'Asha',
        'phone': '9876500001',
        'court_ids': ['c1'],
      },
    ];
    expect(CourtConfiguration.fromJson(legacy).plans.single.coachId, isNull);
  });

  test('court plan validation checks court hours', () {
    final c = courts();
    expect(c.validate(), isNull);
    // Coach coverage is checked by the server against staff access.
    expect(
      c.copyWith(plans: [c.plans.single.copyWith(coachId: 'k')]).validate(),
      isNull,
    );
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

  test(
    'removing a court strips it from plans and clears empty plan coaches',
    () {
      final c = courts()
          .copyWith(plans: [courts().plans.single.copyWith(coachId: 'k')])
          .withoutCourt('c1');
      expect(c.courts.map((v) => v.id), ['c2']);
      expect(c.plans.single.courtIds, isEmpty);
      // A plan left without courts no longer keeps its coach.
      expect(c.plans.single.coachId, isNull);
    },
  );

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
    'Team coaches assign court plans to staff assigned to the courts',
    () async {
      final source = CourtTeamSource()..configuration = courts().toJson();
      final repository = ConfigurationTeamCoachesRepository(
        source,
        CourtCoachApi(source),
      );
      var b = (await repository.load()).businesses.single;
      expect(b.court, isTrue);
      expect(b.spacesLabel, 'courts');
      expect(b.spaces.map((s) => s.name), ['Court 1', 'Court 2']);
      expect(b.coaches.single.poolIds, ['c2']);
      await expectLater(
        repository.assign(b.id, b.version, 'asha', {'p1'}),
        throwsA(isA<AppException>()),
      );
      source.courts = ['c1'];
      b = (await repository.load()).businesses.single;
      await repository.assign(b.id, b.version, 'asha', {'p1'});
      final saved = CourtConfiguration.fromJson(source.configuration!);
      expect(saved.plans.single.coachId, 'asha');
      expect(saved.validate(), isNull);
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
      final source = CourtTeamSource()..configuration = config.toJson();
      final repository = ConfigurationTeamCoachesRepository(
        source,
        CourtCoachApi(source),
      );
      final b = (await repository.load()).businesses.single;
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
