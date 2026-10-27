import 'dart:async';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/team/cubit/team_cubit.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/team/screens/staff_assignment_screen.dart';
import 'package:eden_booking/modules/team/screens/team_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _Repo extends Fake implements WorkspaceRepository {
  _Repo({this.role = 'owner'});
  final String role;
  final added = <Map<String, dynamic>>[];
  final updated = <(String, Map<String, dynamic>)>[];
  Completer<void>? wait;
  Object? failure;
  String delivery = 'sent';
  List<Map<String, dynamic>> members = [];
  List<Map<String, dynamic>> invitations = [];
  Object? teamFailure;
  Completer<void>? teamWait;

  @override
  Future<Workspace> load() async => Workspace(
    organization: const Organization(
      id: 'o',
      name: 'Eden',
      phone: '9876543210',
      currency: 'INR',
    ),
    membership: {'id': 'me', 'role': role, 'permissions': const <String>[]},
    businesses: [
      Business(
        id: 'b1',
        name: 'Eden Turf',
        type: BusinessType.turf,
        status: 'ready',
        locationId: 'l',
        version: 1,
        resources: const [
          Resource(id: 'r1', name: 'Turf 1', capacity: 1),
          Resource(id: 'r2', name: 'Turf 2', capacity: 1),
        ],
      ),
      Business(
        id: 'b2',
        name: 'Eden Courts ${'Very Long Name ' * 6}',
        type: BusinessType.badminton,
        status: 'ready',
        locationId: 'l',
        version: 1,
        resources: const [Resource(id: 'r3', name: 'Court 1', capacity: 1)],
      ),
    ],
  );

  @override
  Future<Map<String, dynamic>> addTeamMember(Map<String, dynamic> data) async {
    added.add(data);
    await wait?.future;
    if (failure != null) throw failure!;
    return {'id': 'pending', 'delivery': delivery};
  }

  @override
  Future<void> updateMember(String id, Map<String, dynamic> data) async {
    updated.add((id, data));
    await wait?.future;
    if (failure != null) throw failure!;
  }

  @override
  Future<Map<String, dynamic>> team() async {
    await teamWait?.future;
    if (teamFailure != null) throw teamFailure!;
    return {'members': members, 'invitations': invitations};
  }
}

/// A confirmed defect, kept but skipped. The id is in the test name.
void bugWidgets(String bug, String name, WidgetTesterCallback body) =>
    testWidgets('[$bug] $name', body, skip: true);

Future<(_Repo, WorkspaceCubit)> _setup(
  WidgetTester tester,
  Widget home, {
  _Repo? repo,
  Size size = const Size(390, 844),
  double scale = 1,
  bool router = false,
  List<GoRoute> extra = const [],
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await getIt.reset();
  addTearDown(getIt.reset);
  final r = repo ?? _Repo();
  getIt.registerSingleton<WorkspaceRepository>(r);
  registerFeatureDependencies(getIt);
  final workspace = WorkspaceCubit(r);
  addTearDown(workspace.close);
  await workspace.load();
  Widget builder(BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  );
  Widget app() => router
      ? MaterialApp.router(
          theme: darkTheme(),
          builder: builder,
          routerConfig: GoRouter(
            routes: [
              GoRoute(path: '/', builder: (_, _) => home),
              ...extra,
            ],
          ),
        )
      : MaterialApp(theme: darkTheme(), builder: builder, home: home);
  await tester.pumpWidget(
    BlocProvider.value(
      value: workspace,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => app(),
      ),
    ),
  );
  settle ? await tester.pumpAndSettle() : await tester.pump();
  return (r, workspace);
}

Finder _tf(String label) => find.widgetWithText(TextFormField, label);

Future<void> _enter(WidgetTester tester, String label, String value) async {
  await tester.enterText(_tf(label), value);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  final finder = find.text(text).first;
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _selectBusiness(WidgetTester tester, String name) async {
  final box = find.widgetWithText(CheckboxListTile, name);
  await tester.ensureVisible(box);
  await tester.pumpAndSettle();
  await tester.tap(box);
  await tester.pumpAndSettle();
}

Future<void> _submit(
  WidgetTester tester, [
  String label = 'Add team member',
]) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pump();
}

Future<void> _validForm(
  WidgetTester tester, {
  String name = 'Test Staff',
  String email = 'staff@example.com',
}) async {
  await _enter(tester, 'Staff name', name);
  await _enter(tester, 'Email address', email);
  await _selectBusiness(tester, 'Eden Turf');
}

void main() {
  group('staff access form: name and email', () {
    testWidgets('empty submit shows both errors and a business prompt', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _submit(tester);
      expect(find.text('Enter at least two characters'), findsOneWidget);
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(repo.added, isEmpty);
    });

    for (final bad in ['', ' ', 'A', '   A   ', 'a' * 121]) {
      testWidgets('invalid staff name length ${bad.length}', (tester) async {
        final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
        await _enter(tester, 'Staff name', bad);
        await _enter(tester, 'Email address', 'staff@example.com');
        await _selectBusiness(tester, 'Eden Turf');
        await _submit(tester);
        expect(repo.added, isEmpty);
        expect(
          find.textContaining(RegExp('at least two|120 characters')),
          findsOneWidget,
        );
      });
    }

    for (final bad in [
      'plain',
      'a@b',
      'a b@example.com',
      'staff@@example.com',
      '@example.com',
      'staff@example',
      'staff@example.com, other@example.com',
    ]) {
      testWidgets('invite email "$bad" is rejected', (tester) async {
        final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
        await _validForm(tester, email: bad);
        await _submit(tester);
        expect(find.text('Enter a valid email'), findsOneWidget);
        expect(repo.added, isEmpty);
      });
    }

    testWidgets('pasted email is trimmed and lower-cased before sending', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _validForm(tester, email: '  Staff.Member+Tag@Example.COM \n');
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(repo.added.single['email'], 'staff.member+tag@example.com');
    });

    testWidgets('unicode and emoji names are sent trimmed but intact', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _validForm(tester, name: '  ഏബിൻ José 😀  ');
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(repo.added.single['display_name'], 'ഏബിൻ José 😀');
    });

    bugWidgets('BUG-1', 'a staff name of 61 emoji is accepted', (tester) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _validForm(tester, name: '😀' * 61);
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(repo.added, hasLength(1));
    });

    bugWidgets('BUG-4', 'a 300 character invite email is rejected locally', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _validForm(tester, email: '${'a' * 290}@example.com');
      await _submit(tester);
      expect(repo.added, isEmpty);
    });

    testWidgets('email field uses the email keyboard', (tester) async {
      await _setup(tester, const StaffAssignmentScreen());
      final editable = tester.widget<EditableText>(
        find.descendant(
          of: _tf('Email address'),
          matching: find.byType(EditableText),
        ),
      );
      expect(editable.keyboardType, TextInputType.emailAddress);
    });
  });

  group('staff access form: roles, businesses, resources', () {
    testWidgets('no business selected shows a prompt and sends nothing', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _enter(tester, 'Staff name', 'Test Staff');
      await _enter(tester, 'Email address', 'staff@example.com');
      await _submit(tester);
      expect(find.text('Select at least one business.'), findsOneWidget);
      expect(repo.added, isEmpty);
    });

    testWidgets('restricting a business without resources is rejected', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _validForm(tester);
      await _tapText(tester, 'Restrict to selected resources');
      await _submit(tester);
      expect(
        find.text('Select at least one resource for restricted businesses.'),
        findsOneWidget,
      );
      expect(repo.added, isEmpty);
    });

    testWidgets('selected resources are sent as the assignment', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _validForm(tester);
      await _tapText(tester, 'Restrict to selected resources');
      await _selectBusiness(tester, 'Turf 2');
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(repo.added.single['assignments'], [
        {
          'business_id': 'b1',
          'resource_ids': ['r2'],
        },
      ]);
    });

    testWidgets('owner role needs no business and sends no permissions', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _enter(tester, 'Staff name', 'Second Owner');
      await _enter(tester, 'Email address', 'owner2@example.com');
      await _tapText(tester, 'Staff');
      await tester.tap(find.text('Owner').last);
      await tester.pumpAndSettle();
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(repo.added.single['role'], 'owner');
      expect(repo.added.single['assignments'], isEmpty);
      expect(repo.added.single['permissions'], isEmpty);
    });

    testWidgets('permissions toggled on are sent, finance stays off', (
      tester,
    ) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _validForm(tester);
      await _tapText(tester, 'View bookings');
      await _tapText(tester, 'Record expenses');
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(
        repo.added.single['permissions'],
        unorderedEquals(['view_bookings', 'record_expenses']),
      );
    });

    testWidgets('a non-owner cannot submit the form', (tester) async {
      final (repo, _) = await _setup(
        tester,
        const StaffAssignmentScreen(),
        repo: _Repo(role: 'manager'),
      );
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Add team member'),
      );
      expect(button.onPressed, isNull);
      expect(repo.added, isEmpty);
    });
  });

  group('staff access form: submit behaviour', () {
    testWidgets('double tap adds exactly one team member', (tester) async {
      final (repo, _) = await _setup(
        tester,
        const StaffAssignmentScreen(),
        repo: _Repo()..wait = Completer<void>(),
      );
      await _validForm(tester);
      final button = find.widgetWithText(FilledButton, 'Add team member');
      await tester.ensureVisible(button);
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(repo.added, hasLength(1));
      repo.wait!.complete();
      await tester.pumpAndSettle();
      expect(repo.added, hasLength(1));
    });

    testWidgets('inputs and toggles are disabled while saving', (tester) async {
      final (repo, _) = await _setup(
        tester,
        const StaffAssignmentScreen(),
        repo: _Repo()..wait = Completer<void>(),
      );
      await _validForm(tester);
      await _submit(tester);
      for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(f.enabled, isFalse);
      }
      repo.wait!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('backend rejection is shown and the form can be retried', (
      tester,
    ) async {
      final repo = _Repo()
        ..failure = const AppException('That email already has access.');
      await _setup(tester, const StaffAssignmentScreen(), repo: repo);
      await _validForm(tester);
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('That email already has access.'), findsOneWidget);
      expect(find.text('staff@example.com'), findsOneWidget);
      repo.failure = null;
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(repo.added, hasLength(2));
    });

    testWidgets('success shows the email result dialog', (tester) async {
      final (repo, _) = await _setup(tester, const StaffAssignmentScreen());
      await _validForm(tester);
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Access email sent'), findsOneWidget);
      expect(repo.added, hasLength(1));
    });

    testWidgets('undelivered email is reported as saved, not sent', (
      tester,
    ) async {
      final repo = _Repo()..delivery = 'failed';
      await _setup(tester, const StaffAssignmentScreen(), repo: repo);
      await _validForm(tester);
      await _submit(tester);
      await tester.pumpAndSettle();
      expect(find.text('Access saved · email not sent'), findsOneWidget);
    });

    testWidgets('editing an existing member locks the email', (tester) async {
      final member = {
        'id': 'm1',
        'display_name': 'Existing Staff',
        'email': 'existing@example.com',
        'role': 'staff',
        'active': true,
        'permissions': ['view_bookings'],
        'assignments': [
          {'business_id': 'b1', 'resource_ids': <String>[]},
        ],
      };
      final (repo, _) = await _setup(
        tester,
        StaffAssignmentScreen(member: member),
      );
      final email = tester.widget<TextField>(
        find.descendant(
          of: _tf('Email address'),
          matching: find.byType(TextField),
        ),
      );
      expect(email.enabled, isFalse);
      await _enter(tester, 'Staff name', 'Renamed Staff');
      await _submit(tester, 'Save staff access');
      await tester.pumpAndSettle();
      expect(repo.updated.single.$1, 'm1');
      expect(repo.updated.single.$2['display_name'], 'Renamed Staff');
      expect(repo.updated.single.$2['email'], 'existing@example.com');
    });

    testWidgets('editing a member with an empty name is rejected', (
      tester,
    ) async {
      final member = {
        'id': 'm1',
        'display_name': 'Existing Staff',
        'email': 'existing@example.com',
        'role': 'staff',
        'active': true,
        'permissions': <String>[],
        'assignments': [
          {'business_id': 'b1', 'resource_ids': <String>[]},
        ],
      };
      final (repo, _) = await _setup(
        tester,
        StaffAssignmentScreen(member: member),
      );
      await _enter(tester, 'Staff name', '   ');
      await _submit(tester, 'Save staff access');
      expect(find.text('Enter at least two characters'), findsOneWidget);
      expect(repo.updated, isEmpty);
    });
  });

  group('staff access form: small screen and large text', () {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('fits 320x568 at text scale $scale', (tester) async {
        await _setup(
          tester,
          const StaffAssignmentScreen(),
          size: const Size(320, 568),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
        await _enter(tester, 'Staff name', 'N' * 120);
        await _enter(tester, 'Email address', '${'e' * 100}@example.com');
        await _selectBusiness(
          tester,
          'Eden Courts Very Long Name Very Long Name Very Long Name Very Long Name Very Long Name Very Long Name ',
        );
        await _submit(tester);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('team list screen states', () {
    Map<String, dynamic> member(
      String id,
      String name, {
      String role = 'staff',
      bool active = true,
      String? email,
    }) => {
      'id': id,
      'display_name': name,
      'email': email ?? '$id@example.com',
      'role': role,
      'active': active,
      'permissions': <String>[],
      'assignments': <Map<String, dynamic>>[],
    };

    testWidgets('loading then empty state', (tester) async {
      final repo = _Repo()..teamWait = Completer<void>();
      await _setup(
        tester,
        const TeamScreen(),
        repo: repo,
        router: true,
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Loading your team…'), findsOneWidget);
      repo.teamWait!.complete();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Loading your team…'), findsNothing);
      expect(find.text('Members'), findsNothing);
      expect(find.text('Add team member'), findsOneWidget);
    });

    testWidgets('error state offers retry that reloads', (tester) async {
      final repo = _Repo()..teamFailure = const AppException('Team offline');
      await _setup(tester, const TeamScreen(), repo: repo, router: true);
      expect(find.text('Team offline'), findsOneWidget);
      repo.teamFailure = null;
      repo.members = [member('m1', 'Asha')];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Team offline'), findsNothing);
      expect(find.text('Asha'), findsOneWidget);
    });

    testWidgets('unexpected load error is generic', (tester) async {
      final repo = _Repo()..teamFailure = StateError('relation "team" missing');
      await _setup(tester, const TeamScreen(), repo: repo, router: true);
      expect(find.text('Could not load your team.'), findsOneWidget);
      expect(find.textContaining('relation'), findsNothing);
    });

    for (final size in [const Size(320, 568), const Size(1440, 900)]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets(
          'long, emoji and empty names render without overflow at ${size.width}x${size.height} scale $scale',
          (tester) async {
            final repo = _Repo()
              ..members = [
                member('m1', 'X' * 120, email: '${'y' * 80}@example.com'),
                member('m2', 'ഏബിൻ José 😀'),
                member('m3', '', role: 'manager'),
                member('m4', 'Removed Person', active: false),
                member('me', 'Owner', role: 'owner'),
              ]
              ..invitations = [
                {
                  'id': 'i1',
                  'display_name': 'Pending ${'P' * 80}',
                  'email': 'pending@example.com',
                  'role': 'staff',
                  'permissions': <String>[],
                  'join_mode': 'email_login',
                  'email_status': 'failed',
                  'expires_at': 'infinity',
                },
              ];
            await _setup(
              tester,
              const TeamScreen(),
              repo: repo,
              size: size,
              scale: scale,
              router: true,
            );
            expect(tester.takeException(), isNull);
            expect(find.text('ഏബിൻ José 😀'), findsOneWidget);
          },
        );
      }
    }

    bugWidgets(
      'BUG-19',
      'a member without a display name does not crash the list',
      (tester) async {
        final repo = _Repo()
          ..members = [
            {
              'id': 'm1',
              'display_name': null,
              'email': 'noname@example.com',
              'role': 'staff',
              'active': true,
              'permissions': <String>[],
              'assignments': <Map<String, dynamic>>[],
            },
          ];
        await _setup(tester, const TeamScreen(), repo: repo, router: true);
        expect(tester.takeException(), isNull);
      },
    );
  });

  bugWidgets(
    'BUG-18',
    'a member whose second name word starts with an emoji renders (initials)',
    (tester) async {
      final repo = _Repo()
        ..members = [
          {
            'id': 'm1',
            'display_name': 'Asha 😀 Nair',
            'email': 'asha@example.com',
            'role': 'staff',
            'active': true,
            'permissions': <String>[],
            'assignments': <Map<String, dynamic>>[],
          },
        ];
      await _setup(tester, const TeamScreen(), repo: repo, router: true);
      expect(tester.takeException(), isNull);
    },
  );

  test('TeamCubit exposes no stale error after a successful reload', () async {
    final repo = _Repo()..teamFailure = const AppException('boom');
    final cubit = TeamCubit(LocalApiTeamRepository(repo));
    await cubit.load();
    expect(cubit.state.error, 'boom');
    repo.teamFailure = null;
    await cubit.load();
    expect(cubit.state.error, isNull);
    await cubit.close();
  });
}
