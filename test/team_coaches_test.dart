import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/team/cubit/team_coaches_cubit.dart';
import 'package:eden_booking/modules/team/repositories/team_coaches_repository.dart';
import 'package:eden_booking/modules/team/screens/team_coaches_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'pool_setup_test.dart' show PoolSource, FakePoolRepository;

class AccessPoolSource extends PoolSource {
  bool owner = true;
  @override
  Future<Workspace> load() async {
    final data = await super.load();
    return Workspace(
      organization: data.organization,
      businesses: data.businesses,
      locations: data.locations,
      membership: {'id': 'member', 'role': owner ? 'owner' : 'staff'},
    );
  }
}

Future<
  ({
    PoolSource source,
    WorkspaceCubit session,
    ConfigurationTeamCoachesRepository repository,
  })
>
fixture() async {
  final source = AccessPoolSource()
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
  final pools = FakePoolRepository(source);
  return (
    source: source,
    session: session,
    repository: ConfigurationTeamCoachesRepository(source, pools),
  );
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  tearDown(() => getIt.reset());
  test(
    'Team coach addition preserves pool settings, then assigns and unassigns plans',
    () async {
      final f = await fixture();
      addTearDown(f.session.close);
      final before = f.source.configuration!;
      var b = (await f.repository.load()).single;
      expect(b.coaches, isEmpty);
      expect(b.plans.every((p) => p.coachId == null), isTrue);
      await f.repository.add(
        b.id,
        b.version,
        ' Alex Coach ',
        '+91 98765 43210',
      );
      b = (await f.repository.load()).single;
      expect(b.coaches.single.name, 'Alex Coach');
      expect(b.plans.every((p) => p.coachId == null), isTrue);
      expect(f.source.configuration!['pools'], before['pools']);
      expect(f.source.configuration!['plans'], before['plans']);
      final coachId = b.coaches.single.id;
      await expectLater(
        f.repository.add(b.id, b.version, 'Duplicate', '+919876543210'),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        f.repository.assign(b.id, b.version, coachId, {b.plans.first.id}),
        throwsA(isA<AppException>()),
      );
      await f.repository.assignSpaces(
        b.id,
        b.version,
        coachId,
        b.spaces.map((p) => p.id).toSet(),
      );
      b = (await f.repository.load()).single;
      await f.repository.assign(
        b.id,
        b.version,
        coachId,
        b.plans.map((p) => p.id).toSet(),
      );
      b = (await f.repository.load()).single;
      expect(b.plans.every((p) => p.coachId == coachId), isTrue);
      await f.repository.assign(b.id, b.version, coachId, {b.plans.first.id});
      b = (await f.repository.load()).single;
      expect(b.plans.first.coachId, coachId);
      expect(b.plans.last.coachId, isNull);
      await expectLater(
        f.repository.assign(b.id, b.version - 1, coachId, {}),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        f.repository.assign(b.id, b.version, coachId, {'foreign-plan'}),
        throwsA(isA<AppException>()),
      );
    },
  );
  test(
    'Coach Cubit can select/unselect plans and updates the workspace after saving',
    () async {
      final f = await fixture();
      final c = TeamCoachesCubit(f.repository, f.session);
      addTearDown(c.close);
      addTearDown(f.session.close);
      await c.load();
      c.beginAdd();
      c.name('Alex Coach');
      c.phone('9876543210');
      expect(await c.saveEditor(), isTrue);
      c.closeEditor();
      var b = c.state.businesses.single;
      c.beginSpaces(b.id, b.coaches.single.id);
      c.toggleSpace(b.spaces.first.id, true);
      expect(await c.saveEditor(), isTrue);
      c.closeEditor();
      b = c.state.businesses.single;
      c.beginAssign(b.id, b.coaches.single.id);
      c.toggle(b.plans.first.id, true);
      expect(c.state.planIds, {b.plans.first.id});
      c.toggle(b.plans.first.id, false);
      expect(c.state.planIds, isEmpty);
      c.toggle(b.plans.first.id, true);
      expect(await c.saveEditor(), isTrue);
      expect(
        c.state.businesses.single.plans.first.coachId,
        b.coaches.single.id,
      );
      expect(
        f
            .session
            .state
            .data
            .businesses
            .single
            .configuration!['plans'][0]['coach_id'],
        b.coaches.single.id,
      );
    },
  );
  test(
    'Coach management blocks staff and purges retained contacts after access changes',
    () async {
      final f = await fixture();
      final c = TeamCoachesCubit(f.repository, f.session);
      addTearDown(c.close);
      addTearDown(f.session.close);
      await c.load();
      c.beginAdd();
      c.name('Alex Coach');
      c.phone('9876543210');
      expect(await c.saveEditor(), isTrue);
      expect(c.state.businesses.single.coaches, hasLength(1));
      (f.source as AccessPoolSource).owner = false;
      await f.session.load();
      await Future<void>.delayed(Duration.zero);
      expect(c.authorized, isFalse);
      expect(c.state.businesses, isEmpty);
      expect(await c.saveEditor(), isFalse);
      await expectLater(f.repository.load(), throwsA(isA<AppException>()));
    },
  );
  test(
    'A plan left without pools keeps its coach and can still be unticked',
    () async {
      final f = await fixture();
      addTearDown(f.session.close);
      var b = (await f.repository.load()).single;
      await f.repository.add(b.id, b.version, 'Alex Coach', '9876543210');
      b = (await f.repository.load()).single;
      final id = b.coaches.single.id;
      await f.repository.assignSpaces(b.id, b.version, id, {'pool', 'pool-b'});
      b = (await f.repository.load()).single;
      await f.repository.assign(b.id, b.version, id, {'beginner', 'advanced'});
      // Older data: the advanced plan lost its pools but kept its coach.
      final config = PoolConfiguration.fromJson(f.source.configuration!);
      f.source.configuration = config
          .copyWith(
            plans: config.plans.map(
              (p) => p.id == 'advanced' ? p.copyWith(poolIds: []) : p,
            ),
          )
          .toJson();
      final c = TeamCoachesCubit(f.repository, f.session);
      addTearDown(c.close);
      await c.load();
      b = c.state.businesses.single;
      c.beginSpaces(b.id, id);
      c.toggleSpace('pool-b', false);
      expect(c.state.affectedPlans, isEmpty);
      c.closeEditor();
      c.beginAssign(b.id, id);
      expect(c.state.eligiblePlans.map((p) => p.id), contains('advanced'));
      expect(await c.saveEditor(), isTrue);
      c.beginAssign(b.id, id);
      c.toggle('advanced', false);
      expect(await c.saveEditor(), isTrue);
      expect(
        c.state.businesses.single.plans
            .firstWhere((p) => p.id == 'advanced')
            .coachId,
        isNull,
      );
    },
  );
  test('Closing the editor does not leave its error on the page', () async {
    final f = await fixture();
    final c = TeamCoachesCubit(f.repository, f.session);
    addTearDown(c.close);
    addTearDown(f.session.close);
    await c.load();
    c.beginAdd();
    expect(await c.saveEditor(), isFalse);
    expect(c.state.error, isNotNull);
    c.closeEditor();
    expect(c.state.error, isNull);
  });
  test(
    'Removing spaces needs confirmation and removes only affected plan assignments',
    () async {
      final f = await fixture();
      addTearDown(f.session.close);
      var b = (await f.repository.load()).single;
      await f.repository.add(b.id, b.version, 'Alex Coach', '9876543210');
      b = (await f.repository.load()).single;
      final id = b.coaches.single.id;
      await f.repository.assignSpaces(b.id, b.version, id, {'pool', 'pool-b'});
      b = (await f.repository.load()).single;
      await f.repository.assign(
        b.id,
        b.version,
        id,
        b.plans.map((p) => p.id).toSet(),
      );
      final c = TeamCoachesCubit(f.repository, f.session);
      addTearDown(c.close);
      await c.load();
      c.beginSpaces(b.id, id);
      c.toggleSpace('pool-b', false);
      expect(c.state.affectedPlans.single.name, 'Advanced coaching');
      final beforeVersion = f.source.version;
      expect(await c.saveEditor(), isFalse);
      expect(f.source.version, beforeVersion);
      expect(c.state.spaceIds, {'pool'});
      expect(await c.saveEditor(removeAffectedPlans: true), isTrue);
      b = c.state.businesses.single;
      expect(b.plans.first.coachId, id);
      expect(b.plans.last.coachId, isNull);
      expect(b.coaches.single.poolIds, ['pool']);
      await expectLater(
        f.repository.assignSpaces(b.id, b.version, id, {'foreign-pool'}),
        throwsA(isA<AppException>()),
      );
      await expectLater(
        f.repository.assignSpaces(b.id, b.version - 1, id, {}),
        throwsA(isA<AppException>()),
      );
      await f.repository.assignSpaces(
        b.id,
        b.version,
        id,
        {},
        removeAffectedPlans: true,
      );
      b = (await f.repository.load()).single;
      expect(b.coaches.single.poolIds, isEmpty);
      expect(b.plans.every((p) => p.coachId == null), isTrue);
    },
  );
  test(
    'Legacy coach contacts retain spaces inferred from existing plan assignments',
    () {
      final config = PoolConfiguration(
        pools: [PoolResource(id: 'pool', name: 'Pool A')],
        plans: [
          PoolPlan(
            id: 'plan',
            kind: 'coaching',
            poolIds: ['pool'],
            coachId: 'coach',
          ),
        ],
      );
      final json = config.toJson();
      json['coaches'] = [
        {'id': 'coach', 'name': 'Legacy Coach', 'phone': '9876543210'},
      ];
      final restored = PoolConfiguration.fromJson(json);
      expect(restored.coaches.single.poolIds, ['pool']);
      expect(restored.plans.single.coachId, 'coach');
      expect(restored.toJson()['coaches'][0]['pool_ids'], ['pool']);
    },
  );
  testWidgets(
    'Team coach screen supports add and assignment on narrow large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final f = await fixture();
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
              home: const TeamCoachesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('No coaches added. Coaching plans remain Unassigned.'),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byTooltip('Add coach'),
        ),
        findsOneWidget,
      );
      expect(find.text('Add coach'), findsNothing);
      await tester.tap(find.byTooltip('Add coach'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Coach name'),
        'Alex Coach',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'),
        '9876543210',
      );
      await tester.ensureVisible(find.text('Save coach'));
      await tester.tap(find.text('Save coach'));
      await tester.pumpAndSettle();
      expect(find.text('Alex Coach'), findsOneWidget);
      await tester.ensureVisible(find.text('Assign pool spaces'));
      await tester.tap(find.text('Assign pool spaces'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Pool A'));
      await tester.tap(find.text('Pool A'));
      await tester.ensureVisible(find.text('Save assignments'));
      await tester.tap(find.text('Save assignments'));
      await tester.pumpAndSettle();
      expect(find.text('Pool A'), findsOneWidget);
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
      expect(
        f.source.configuration!['plans'][0]['coach_id'],
        f.source.configuration!['coaches'][0]['id'],
      );
      await tester.ensureVisible(find.text('Assign pool spaces'));
      await tester.tap(find.text('Assign pool spaces'));
      await tester.pumpAndSettle();
      final poolBox = find.widgetWithText(CheckboxListTile, 'Pool A');
      await tester.ensureVisible(poolBox);
      await tester.tap(poolBox);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save assignments'));
      await tester.tap(find.text('Save assignments'));
      await tester.pumpAndSettle();
      expect(find.text('Remove affected plan assignments?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(f.source.configuration!['plans'][0]['coach_id'], isNotNull);
      await tester.tap(find.text('Save assignments'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(f.source.configuration!['plans'][0]['coach_id'], isNull);
      expect(f.source.configuration!['coaches'][0]['pool_ids'], isEmpty);
      expect(find.text('No pool spaces assigned'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await f.session.close();
    },
  );
}
