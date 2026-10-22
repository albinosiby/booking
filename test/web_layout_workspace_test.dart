import 'package:eden_booking/modules/team/widgets/team_desktop_widgets.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/businesses/screens/business_detail_screen.dart';
import 'package:eden_booking/modules/businesses/screens/business_management_screen.dart';
import 'package:eden_booking/modules/profile/cubit/organization_edit_cubit.dart';
import 'package:eden_booking/modules/profile/cubit/profile_cubit.dart';
import 'package:eden_booking/modules/profile/screens/organization_details_screen.dart';
import 'package:eden_booking/modules/profile/screens/organization_edit_screen.dart';
import 'package:eden_booking/modules/team/cubit/team_coaches_cubit.dart';
import 'package:eden_booking/modules/team/cubit/team_cubit.dart';
import 'package:eden_booking/modules/team/models/staff_access_draft.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/team/screens/staff_assignment_screen.dart';
import 'package:eden_booking/modules/team/widgets/staff_coaching_section.dart';
import 'package:eden_booking/modules/team/screens/team_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'business_details_test.dart' as details;
import 'business_management_test.dart' show ManagementSource;
import 'organization_details_test.dart' show DetailsSource, DetailsRepository;
import 'organization_edit_test.dart' show EditRepository;
import 'staff_assignment_test.dart' show StaffRepository;
import 'team_coaches_test.dart' as coaches;

const desktopSize = Size(1440, 1000);

class FakeTeamRepository extends Fake implements TeamRepository {
  final revoked = <String>[];
  @override
  Future<Map<String, dynamic>> load() async => {
    'members': [
      {
        'id': 'owner',
        'display_name': 'Alex Thomas',
        'email': 'alex@example.com',
        'role': 'owner',
        'active': true,
      },
      {
        'id': 'manager',
        'display_name': 'Priya Nair',
        'email': 'priya@example.com',
        'role': 'manager',
        'active': true,
      },
      {
        'id': 'staff',
        'display_name': 'Rahul Menon',
        'email': 'rahul@example.com',
        'role': 'staff',
        'active': true,
      },
      {
        'id': 'former',
        'display_name': 'Sam Joseph',
        'email': 'sam@example.com',
        'role': 'staff',
        'active': false,
      },
    ],
    'invitations': [
      {
        'id': 'invite',
        'display_name': 'Meera Das',
        'email': 'meera@example.com',
        'expires_at': DateTime.now()
            .add(const Duration(days: 5))
            .toIso8601String(),
        'accepted_at': null,
        'revoked_at': null,
      },
    ],
  };
  @override
  Future<void> revoke(String id, {bool invitation = false}) async =>
      revoked.add(id);
  @override
  Future<String> invite(StaffAccessDraft draft) async => 'link';
}

/// Pumps [routes] at desktop size. [theme] lets preview tests swap fonts.
Future<GoRouter> pumpDesktop(
  WidgetTester tester,
  List<RouteBase> routes, {
  WorkspaceCubit? session,
  String initial = '/',
  Brightness brightness = Brightness.dark,
  ThemeData Function(ThemeData)? theme,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = desktopSize;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(initialLocation: initial, routes: routes);
  addTearDown(router.dispose);
  Widget app = ScreenUtilInit(
    designSize: const Size(390, 844),
    builder: (c, _) {
      final base = AppTheme.build(brightness);
      return MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: theme?.call(base) ?? base,
        routerConfig: router,
        builder: (c, child) => boundary == null
            ? child!
            : RepaintBoundary(key: boundary, child: child!),
      );
    },
  );
  if (session != null) app = BlocProvider.value(value: session, child: app);
  await tester.pumpWidget(app);
  await tester.pumpAndSettle();
  return router;
}

GoRoute page(Widget child, [String path = '/']) =>
    GoRoute(path: path, builder: (_, _) => child);

Future<WorkspaceCubit> organizationSession() async {
  final repo = DetailsRepository();
  final session = WorkspaceCubit(DetailsSource());
  addTearDown(session.close);
  await session.load();
  getIt.registerFactoryParam<ProfileCubit, WorkspaceSession, void>(
    (s, _) => ProfileCubit(s, repo),
  );
  getIt.registerFactoryParam<OrganizationEditCubit, WorkspaceSession, void>(
    (s, _) => OrganizationEditCubit(s, EditRepository()),
  );
  return session;
}

Future<(WorkspaceCubit, ManagementSource)> businessSession({
  bool configured = false,
}) async {
  final source = ManagementSource();
  if (configured) {
    source.businesses = [
      details.business('turf', configuration: details.config('turf')),
      ...source.businesses.skip(1),
    ];
  }
  getIt.registerSingleton<WorkspaceRepository>(source);
  registerFeatureDependencies(getIt);
  final session = WorkspaceCubit(source);
  addTearDown(session.close);
  await session.load();
  return (session, source);
}

Future<(WorkspaceCubit, FakeTeamRepository)> teamSession() async {
  final source = StaffRepository();
  getIt.registerSingleton<WorkspaceRepository>(source);
  registerFeatureDependencies(getIt);
  final team = FakeTeamRepository();
  await getIt.unregister<TeamCubit>();
  getIt.registerFactory<TeamCubit>(() => TeamCubit(team));
  final session = WorkspaceCubit(source);
  addTearDown(session.close);
  await session.load();
  return (session, team);
}

Future<WorkspaceCubit> coachSession({bool withCoach = true}) async {
  final f = await coaches.fixture(
    members: [
      if (withCoach) coaches.staff('arjun', 'Arjun Pillai', pools: ['pool']),
    ],
  );
  addTearDown(f.session.close);
  if (withCoach) {
    final b = (await f.repository.load()).businesses.single;
    await f.repository.assign(b.id, b.version, 'arjun', {'beginner'});
    await f.session.load();
  }
  getIt.registerFactoryParam<TeamCoachesCubit, WorkspaceSession, void>(
    (session, _) => TeamCoachesCubit(f.repository, session),
  );
  return f.session;
}

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    await getIt.reset();
  });
  tearDown(() => getIt.reset());

  testWidgets('organization details shows identity beside detail panels', (
    tester,
  ) async {
    final session = await organizationSession();
    await pumpDesktop(tester, [
      page(const OrganizationDetailsScreen()),
    ], session: session);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppTwoPane), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('Edit organization'), findsOneWidget);
    expect(find.text('Add logo'), findsOneWidget);
    for (final label in ['Contact details', 'Locations', 'Owner']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('068201'), findsOneWidget);
    // The identity card sits left of the panels.
    expect(
      tester.getCenter(find.text('Add logo')).dx,
      lessThan(tester.getCenter(find.text('Contact details')).dx),
    );
  });

  testWidgets('organization edit lays fields in two columns with a save bar', (
    tester,
  ) async {
    final session = await organizationSession();
    final router = await pumpDesktop(tester, [
      page(const Scaffold(body: Text('Organization details'))),
      page(const OrganizationEditScreen(), '/edit'),
    ], session: session);
    unawaited(router.push<void>('/edit'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AppTwoPane), findsOneWidget);
    expect(find.text('No unsaved changes.'), findsOneWidget);
    // Address line 1 sits beside the location name.
    expect(
      tester.getTopLeft(find.text('Location name')).dy,
      tester.getTopLeft(find.text('Address line 1')).dy,
    );
    await tester.enterText(find.byType(TextFormField).first, 'Eden Arena');
    await tester.pump();
    expect(find.text('You have unsaved changes.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Discard changes?'), findsOneWidget);
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('Organization details'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('businesses use a card grid with header actions and reorder', (
    tester,
  ) async {
    final (session, source) = await businessSession();
    await pumpDesktop(tester, [
      page(const BusinessManagementScreen()),
      page(const Scaffold(body: Text('Add destination')), '/businesses/add'),
    ], session: session);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppStatTile), findsNWidgets(4));
    expect(find.byType(AppGrid), findsOneWidget);
    final turf = tester.getCenter(find.text('Eden Turf'));
    final pool = tester.getCenter(find.text('Eden Swimming'));
    expect(turf.dy, pool.dy, reason: 'cards share a grid row');
    expect(turf.dx, lessThan(pool.dx));
    await tester.tap(find.byKey(const ValueKey('business-reorder')));
    await tester.pumpAndSettle();
    expect(find.byType(SliverReorderableList), findsOneWidget);
    await tester.tap(find.byTooltip('Move down').first);
    await tester.pumpAndSettle();
    expect(source.saves, 0);
    await tester.tap(find.text('Save order'));
    await tester.pumpAndSettle();
    expect(source.saves, 1);
    expect(source.businesses.first.id, 'pool');
    expect(find.byType(AppGrid), findsOneWidget);
    await tester.tap(find.text('Add business'));
    await tester.pumpAndSettle();
    expect(find.text('Add destination'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('business detail is a dashboard of tiles, spaces and panels', (
    tester,
  ) async {
    final (session, _) = await businessSession(configured: true);
    await pumpDesktop(tester, [
      page(const BusinessDetailScreen(id: 'business')),
    ], session: session);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppStatTile), findsNWidgets(4));
    expect(find.text('Business information'), findsOneWidget);
    expect(find.text('Location'), findsOneWidget);
    expect(find.text('Configure business'), findsOneWidget);
    expect(find.byType(AppGrid), findsWidgets);
    final tile = find.byType(ExpansionTile).first;
    await tester.ensureVisible(tile);
    await tester.tap(tile);
    await tester.pumpAndSettle();
    expect(find.text('Opening hours'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('team shows compact staff tiles with actions and header invite', (
    tester,
  ) async {
    final (session, team) = await teamSession();
    await pumpDesktop(tester, [page(const TeamScreen())], session: session);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppStatTile), findsWidgets);
    expect(find.text('Invite staff'), findsOneWidget);
    expect(find.text('Coaches'), findsNothing);
    expect(find.byType(TeamPersonTile), findsNWidgets(5));
    expect(find.text('Manager'), findsWidgets);
    await tester.tap(find.byTooltip('Staff actions for Priya Nair'));
    await tester.pumpAndSettle();
    expect(find.text('Edit staff'), findsOneWidget);
    expect(find.text('Remove access'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    final alex = tester.getCenter(find.text('Alex Thomas'));
    final priya = tester.getCenter(find.text('Priya Nair'));
    expect(alex.dy, priya.dy, reason: 'members share a grid row');
    await tester.ensureVisible(find.byTooltip('Cancel invitation'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel invitation'));
    await tester.pumpAndSettle();
    expect(team.revoked, ['invite']);
    tester.view.physicalSize = const Size(320, 1000);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Alex Thomas'));
    await tester.pumpAndSettle();
    expect(find.byType(TeamPersonTile), findsNWidgets(5));
    expect(
      tester.getTopLeft(find.text('Priya Nair')).dy,
      greaterThan(tester.getTopLeft(find.text('Alex Thomas')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('staff assignment puts permissions beside the form', (
    tester,
  ) async {
    final (session, _) = await teamSession();
    await pumpDesktop(tester, [
      page(const StaffAssignmentScreen()),
    ], session: session);
    expect(tester.takeException(), isNull);
    expect(find.byType(AppTwoPane), findsOneWidget);
    expect(
      tester.getCenter(find.text('Permissions')).dx,
      greaterThan(tester.getCenter(find.text('Assign businesses')).dx),
    );
    expect(find.text('Create invitation'), findsOneWidget);
  });

  testWidgets('staff details contain coaching assignments on desktop', (
    tester,
  ) async {
    final session = await coachSession();
    await pumpDesktop(tester, [
      page(
        const AppPage(
          title: 'Staff details',
          children: [StaffCoachingSection(memberId: 'arjun')],
        ),
      ),
    ], session: session);
    expect(tester.takeException(), isNull);
    expect(find.text('Invite coach'), findsNothing);
    expect(find.byTooltip('Refresh coaching plans'), findsOneWidget);
    expect(find.text('Coaching plans'), findsOneWidget);
    await tester.tap(find.text('Assign coaching plans'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Save assignments'), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
