import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/coaching/repositories/coach_api.dart';
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/team/cubit/team_coaches_cubit.dart';
import 'package:eden_booking/modules/team/models/staff_coaches.dart';
import 'package:eden_booking/modules/team/repositories/team_coaches_repository.dart';
import 'package:eden_booking/modules/team/widgets/staff_coaching_section.dart';
import 'package:eden_booking/modules/team/screens/staff_assignment_screen.dart';
import 'package:eden_booking/modules/team/cubit/staff_assignment_cubit.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'pool_setup_test.dart' show PoolSource;

Map<String, dynamic> staff(
  String id,
  String name, {
  List<String> pools = const [],
  bool coach = true,
  String business = 'swimming',
}) => {
  'id': id,
  'display_name': name,
  'email': '$id@example.com',
  'role': 'staff',
  'active': true,
  'permissions': [if (coach) 'coach'],
  'assignments': [
    {'business_id': business, 'resource_ids': pools},
  ],
};

/// A pool workspace with a team; coach plan saves change only plan coaches.
class TeamSource extends PoolSource {
  bool owner = true, ownerCoach = false;
  List<Map<String, dynamic>> members = [];
  Map<String, dynamic> get ownerRow => {
    'id': 'owner',
    'display_name': 'Owner',
    'email': 'owner@example.com',
    'role': 'owner',
    'active': true,
    'permissions': [if (ownerCoach) 'coach'],
    'assignments': [],
  };
  @override
  Future<Workspace> load() async {
    final data = await super.load();
    return Workspace(
      organization: data.organization,
      businesses: data.businesses,
      locations: data.locations,
      membership: owner ? ownerRow : {'id': 'member', 'role': 'staff'},
    );
  }

  @override
  Future<Map<String, dynamic>> team() async => {
    'members': [ownerRow, ...members],
    'invitations': [],
  };
  @override
  Future<void> updateMember(String id, Map<String, dynamic> data) async {
    members = [
      for (final m in members)
        if (m['id'] == id) {...m, ...data} else m,
    ];
  }

  void setCoaches(Map<String, String?> coaches) {
    configuration = {
      ...configuration!,
      'plans': [
        for (final p in configuration!['plans'] as List)
          coaches.containsKey(p['id'])
              ? {...p, 'coach_id': coaches[p['id']]}
              : p,
      ],
    };
    version++;
  }
}

class FakeCoachApi extends Fake implements CoachApi {
  FakeCoachApi(this.source);
  final TeamSource source;
  List<String> clashes = const [];
  int conflictChecks = 0;
  @override
  Future<void> assignPlans(
    String businessId,
    int version,
    Map<String, String?> coaches,
  ) async {
    if (version != source.version) {
      throw const AppException('Settings changed.', code: 'CONFLICT');
    }
    source.setCoaches(coaches);
  }

  @override
  Future<void> setOwnerCoach(bool coach) async {
    source.ownerCoach = coach;
    if (!coach) {
      source.setCoaches({
        for (final p in source.configuration!['plans'] as List)
          if (p['coach_id'] == 'owner') p['id'] as String: null,
      });
    }
  }

  @override
  Future<List<String>> conflicts(
    String businessId,
    String coachId,
    Set<String> planIds,
  ) async {
    conflictChecks++;
    return clashes;
  }
}

Future<
  ({
    TeamSource source,
    WorkspaceCubit session,
    FakeCoachApi api,
    ConfigurationTeamCoachesRepository repository,
  })
>
fixture({List<Map<String, dynamic>> members = const []}) async {
  final source = TeamSource()
    ..members = [...members]
    ..configuration = PoolConfiguration(
      pools: [
        PoolResource(
          id: 'pool',
          name: 'Pool A',
          capacity: '20',
          minDepth: '3',
          maxDepth: '5',
          regularSwimming: false,
        ),
        PoolResource(
          id: 'pool-b',
          name: 'Pool B',
          capacity: '20',
          minDepth: '3',
          maxDepth: '5',
          regularSwimming: false,
        ),
      ],
      plans: [
        PoolPlan(
          id: 'beginner',
          kind: 'coaching',
          name: 'Beginner coaching',
          poolIds: ['pool'],
          price: '2000',
        ),
        PoolPlan(
          id: 'advanced',
          kind: 'coaching',
          name: 'Advanced coaching',
          poolIds: ['pool-b'],
          price: '3000',
        ),
      ],
    ).toJson();
  final session = WorkspaceCubit(source);
  await session.load();
  final api = FakeCoachApi(source);
  return (
    source: source,
    session: session,
    api: api,
    repository: ConfigurationTeamCoachesRepository(source, api),
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  test(
    'Coaches are staff with the coach flag, limited to their pools',
    () async {
      final f = await fixture(
        members: [
          staff('ravi', 'Ravi', pools: ['pool']),
          staff('mia', 'Mia', coach: false),
          staff('elsewhere', 'Elsewhere', business: 'other'),
        ],
      );
      addTearDown(f.session.close);
      var b = (await f.repository.load()).businesses.single;
      expect(b.coaches.map((c) => c.name), ['Ravi']);
      expect(b.coaches.single.poolIds, ['pool']);
      await expectLater(
        f.repository.assign(b.id, b.version, 'ravi', {'advanced'}),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        f.repository.assign(b.id, b.version, 'mia', {'beginner'}),
        throwsA(isA<AppException>()),
      );
      await f.repository.assign(b.id, b.version, 'ravi', {'beginner'});
      b = (await f.repository.load()).businesses.single;
      expect(b.plans.first.coachId, 'ravi');
      // Unrestricted staff teach in every pool of the business.
      f.source.members.add(staff('asha', 'Asha'));
      b = (await f.repository.load()).businesses.single;
      expect(b.coaches.last.poolIds, ['pool', 'pool-b']);
      await f.repository.assign(b.id, b.version, 'asha', {
        'beginner',
        'advanced',
      });
      b = (await f.repository.load()).businesses.single;
      expect(b.plans.every((p) => p.coachId == 'asha'), isTrue);
      await f.repository.assign(b.id, b.version, 'asha', {'advanced'});
      b = (await f.repository.load()).businesses.single;
      expect(b.plans.first.coachId, isNull);
      await expectLater(
        f.repository.assign(b.id, b.version - 1, 'asha', {}),
        throwsA(isA<AppException>()),
      );
    },
  );

  test(
    'The owner opts in to coaching and releases plans when opting out',
    () async {
      final f = await fixture();
      final c = TeamCoachesCubit(f.repository, f.session);
      addTearDown(c.close);
      addTearDown(f.session.close);
      await c.load();
      expect(c.state.ownerCoach, isFalse);
      expect(c.state.businesses.single.coaches, isEmpty);
      expect(await c.setOwnerCoach(true), isTrue);
      expect(c.state.ownerCoach, isTrue);
      final b = c.state.businesses.single;
      expect(b.coaches.single.owner, isTrue);
      expect(b.coaches.single.poolIds, ['pool', 'pool-b']);
      c.beginAssign(b.id, 'owner');
      c.toggle('beginner', true);
      expect(await c.saveEditor(), isTrue);
      expect(c.state.plansOf('owner').map((p) => p.id), ['beginner']);
      expect(await c.setOwnerCoach(false), isTrue);
      expect(c.state.plansOf('owner'), isEmpty);
    },
  );

  test('Assigned plans no longer covered can be unticked', () async {
    final f = await fixture(
      members: [
        staff('ravi', 'Ravi', pools: ['pool', 'pool-b']),
      ],
    );
    addTearDown(f.session.close);
    var b = (await f.repository.load()).businesses.single;
    await f.repository.assign(b.id, b.version, 'ravi', {
      'beginner',
      'advanced',
    });
    f.source.members = [
      staff('ravi', 'Ravi', pools: ['pool']),
    ];
    final c = TeamCoachesCubit(f.repository, f.session);
    addTearDown(c.close);
    await c.load();
    b = c.state.businesses.single;
    c.beginAssign(b.id, 'ravi');
    expect(c.state.eligiblePlans.map((p) => p.id), ['beginner', 'advanced']);
    expect(await c.saveEditor(), isFalse);
    expect(c.state.error, contains('every pool'));
    c.toggle('advanced', false);
    expect(await c.saveEditor(), isTrue);
    expect(c.state.businesses.single.plans.map((p) => p.coachId), [
      'ravi',
      null,
    ]);
    // Editor errors don't stay on the page after closing.
    c.beginAssign(b.id, 'ravi');
    c.toggle('advanced', true);
    expect(await c.saveEditor(), isFalse);
    c.closeEditor();
    expect(c.state.error, isNull);
  });

  test('Conflicts are only checked when the coach gains plans', () async {
    final f = await fixture(members: [staff('ravi', 'Ravi')]);
    final c = TeamCoachesCubit(f.repository, f.session);
    addTearDown(c.close);
    addTearDown(f.session.close);
    await c.load();
    final b = c.state.businesses.single;
    c.beginAssign(b.id, 'ravi');
    expect(await c.assignmentConflicts(), isEmpty);
    expect(f.api.conflictChecks, 0);
    f.api.clashes = ['Beginner coaching and Swim club · 2030-06-04 17:00'];
    c.toggle('beginner', true);
    expect(await c.assignmentConflicts(), f.api.clashes);
    expect(f.api.conflictChecks, 1);
  });

  test('Coach management blocks staff after access changes', () async {
    final f = await fixture(members: [staff('ravi', 'Ravi')]);
    final c = TeamCoachesCubit(f.repository, f.session);
    addTearDown(c.close);
    addTearDown(f.session.close);
    await c.load();
    expect(c.state.businesses.single.coaches, hasLength(1));
    f.source.owner = false;
    await f.session.load();
    await Future<void>.delayed(Duration.zero);
    expect(c.authorized, isFalse);
    expect(c.state.businesses, isEmpty);
    expect(await c.saveEditor(), isFalse);
    await expectLater(f.repository.load(), throwsA(isA<AppException>()));
  });

  test('Old coach contacts are dropped and their plans become Unassigned', () {
    final json = PoolConfiguration(
      pools: [PoolResource(id: 'pool', name: 'Pool A')],
      plans: [
        PoolPlan(id: 'a', kind: 'coaching', poolIds: ['pool'], coachId: 'c'),
        PoolPlan(id: 'b', kind: 'coaching', poolIds: ['pool'], coachId: 'm'),
      ],
    ).toJson();
    json['coaches'] = [
      {'id': 'c', 'name': 'Legacy Coach', 'phone': '9876543210'},
    ];
    final restored = PoolConfiguration.fromJson(json);
    expect(restored.plans.map((p) => p.coachId), [null, 'm']);
    expect(restored.toJson().containsKey('coaches'), isFalse);
  });

  test('Released plans follow the staff access being saved', () async {
    final f = await fixture();
    addTearDown(f.session.close);
    f.source.setCoaches({'beginner': 'ravi', 'advanced': 'ravi'});
    final data = await f.source.load();
    List<String> released({
      bool coach = true,
      Map<String, List<String>> assignments = const {'swimming': []},
    }) => releasedPlans(
      data.businesses,
      'ravi',
      coach: coach,
      assignments: assignments,
    );
    expect(released(), isEmpty);
    expect(released(coach: false), ['Beginner coaching', 'Advanced coaching']);
    expect(
      released(
        assignments: {
          'swimming': ['pool'],
        },
      ),
      ['Advanced coaching'],
    );
    expect(released(assignments: {}), hasLength(2));
  });

  testWidgets('Staff coaching section assigns plans on narrow large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final f = await fixture(
      members: [
        staff('ravi', 'Ravi Kumar', pools: ['pool']),
      ],
    );
    addTearDown(f.session.close);
    getIt.registerFactoryParam<TeamCoachesCubit, WorkspaceSession, void>(
      (session, _) => TeamCoachesCubit(f.repository, session),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: f.session,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: AppTheme.build(Brightness.light),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.6)),
              child: child!,
            ),
            home: const AppPage(
              title: 'Staff details',
              children: [StaffCoachingSection(memberId: 'ravi')],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Coaching plans'), findsOneWidget);
    expect(find.byTooltip('Invite coach'), findsNothing);
    await tester.ensureVisible(find.text('Assign coaching plans'));
    await tester.tap(find.text('Assign coaching plans'));
    await tester.pumpAndSettle();
    expect(find.text('Advanced coaching'), findsNothing);
    await tester.ensureVisible(find.text('Beginner coaching'));
    await tester.tap(find.text('Beginner coaching'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Save assignments'));
    await tester.tap(find.text('Save assignments'));
    await tester.pumpAndSettle();
    expect(find.text('Beginner coaching'), findsOneWidget);
    expect(f.source.configuration!['plans'][0]['coach_id'], 'ravi');
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'staff details save resource changes before enabling coaching plan assignments',
    (tester) async {
      final f = await fixture(
        members: [
          staff('ravi', 'Ravi Kumar', pools: ['pool']),
        ],
      );
      addTearDown(f.session.close);
      getIt.registerFactoryParam<TeamCoachesCubit, WorkspaceSession, void>(
        (session, _) => TeamCoachesCubit(f.repository, session),
      );
      getIt.registerFactoryParam<
        StaffAssignmentCubit,
        WorkspaceSession,
        Map<String, dynamic>?
      >(
        (session, member) => StaffAssignmentCubit(
          session,
          LocalApiTeamRepository(f.source),
          member: member,
        ),
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: f.session,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              theme: darkTheme(),
              home: StaffAssignmentScreen(member: f.source.members.single),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final restriction = find.widgetWithText(
        SwitchListTile,
        'Restrict to selected resources',
      );
      await tester.ensureVisible(restriction);
      await tester.tap(restriction);
      await tester.pumpAndSettle();
      expect(find.textContaining('Save staff access before'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(
              find.widgetWithText(OutlinedButton, 'Assign coaching plans'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(find.text('Save staff access'));
      await tester.tap(find.text('Save staff access'));
      await tester.pumpAndSettle();
      expect(find.text('Edit staff access.'), findsOneWidget);
      expect(find.textContaining('Save staff access before'), findsNothing);
      await tester.ensureVisible(find.text('Assign coaching plans'));
      await tester.tap(find.text('Assign coaching plans'));
      await tester.pumpAndSettle();
      expect(find.text('Advanced coaching'), findsOneWidget);
      await tester.ensureVisible(find.text('Advanced coaching'));
      await tester.tap(find.text('Advanced coaching'));
      await tester.ensureVisible(find.text('Save assignments'));
      await tester.tap(find.text('Save assignments'));
      await tester.pumpAndSettle();
      expect(f.source.configuration!['plans'][1]['coach_id'], 'ravi');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('owner coaching is managed from their staff responsibilities', (
    tester,
  ) async {
    final f = await fixture();
    addTearDown(f.session.close);
    getIt.registerFactoryParam<TeamCoachesCubit, WorkspaceSession, void>(
      (session, _) => TeamCoachesCubit(f.repository, session),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: f.session,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme(),
            home: StaffAssignmentScreen(member: f.source.ownerRow),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Your staff responsibilities.'), findsOneWidget);
    expect(find.text('Staff name'), findsNothing);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Also a coach'));
    await tester.pumpAndSettle();
    expect(f.source.ownerCoach, true);
    await tester.ensureVisible(find.text('Assign coaching plans'));
    await tester.tap(find.text('Assign coaching plans'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Beginner coaching'));
    await tester.ensureVisible(find.text('Save assignments'));
    await tester.tap(find.text('Save assignments'));
    await tester.pumpAndSettle();
    expect(f.source.configuration!['plans'][0]['coach_id'], 'owner');
    expect(tester.takeException(), isNull);
  });
}
