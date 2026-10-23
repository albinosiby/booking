import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/team/cubit/team_cubit.dart';
import 'package:eden_booking/modules/team/cubit/staff_assignment_cubit.dart';
import 'package:eden_booking/modules/team/models/staff_access_draft.dart';
import 'package:eden_booking/modules/team/models/team_email_result.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/team/screens/team_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'staff_assignment_test.dart' show StaffRepository;

class EmailTeam extends Fake implements TeamRepository {
  final members = <Map<String, dynamic>>[];
  final removed = <(String, bool)>[];
  final entry = <String, dynamic>{
    'id': 'pending',
    'display_name': 'Pending Staff',
    'email': 'staff@example.com',
    'role': 'staff',
    'permissions': <String>[],
    'assignments': <Map<String, dynamic>>[],
    'join_mode': 'email_login',
    'email_status': 'failed',
    'expires_at': 'infinity',
  };
  int revocations = 0, resends = 0, adds = 0;
  bool failEmail = false;
  Completer<void>? loadWait;
  @override
  Future<Map<String, dynamic>> load() async {
    await loadWait?.future;
    return {
      'members': members,
      'invitations': [entry],
    };
  }

  @override
  Future<void> revoke(String id, {bool invitation = false}) async {
    revocations++;
    removed.add((id, invitation));
    if (invitation) {
      entry['revoked_at'] = DateTime.now().toIso8601String();
    } else {
      members.firstWhere((member) => member['id'] == id)['active'] = false;
    }
  }

  @override
  Future<TeamEmailResult> resendEmail(String id) async {
    resends++;
    entry['email_status'] = failEmail ? 'failed' : 'sent';
    return TeamEmailResult(entry['email_status']);
  }

  @override
  Future<TeamEmailResult> add(StaffAccessDraft draft) async {
    adds++;
    return const TeamEmailResult('failed');
  }
}

class RefreshFailure extends StaffRepository {
  bool failLoad = false;
  @override
  Future<Workspace> load() async {
    if (failLoad) throw StateError('offline');
    return super.load();
  }
}

void main() {
  tearDown(() async => getIt.reset());
  for (final size in [const Size(320, 844), const Size(1440, 1000)]) {
    testWidgets('email pending access actions work at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = EmailTeam();
      getIt.registerFactory<TeamCubit>(() => TeamCubit(repo));
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const TeamScreen()),
          GoRoute(
            path: '/team/edit',
            builder: (_, state) =>
                Text('Editing ${(state.extra as Map)['pending_access']}'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) =>
              MaterialApp.router(theme: darkTheme(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Add team member'), findsOneWidget);
      expect(find.text('Awaiting sign-in'), findsWidgets);
      expect(find.text('Email not sent'), findsOneWidget);
      final actions = find.byTooltip(
        'Pending access actions for Pending Staff',
      );
      await tester.ensureVisible(actions);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Resend access email'));
      await tester.pumpAndSettle();
      expect(repo.resends, 1);
      expect(find.text('Email sent'), findsOneWidget);
      await tester.ensureVisible(find.text('Cancel access'));
      await tester.tap(find.text('Cancel access'));
      await tester.pumpAndSettle();
      expect(repo.revocations, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.revocations, 0);
      await tester.ensureVisible(actions);
      await tester.tap(actions);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit access'));
      await tester.pumpAndSettle();
      expect(find.text('Editing true'), findsOneWidget);
      router.pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Cancel access'));
      await tester.tap(find.text('Cancel access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.removed, [('pending', true)]);
      expect(find.text('Cancelled'), findsOneWidget);
      expect(find.text('Cancel access'), findsNothing);
      expect(tester.takeException(), isNull);
    });
    testWidgets('staff removal is visible and confirmed at ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = EmailTeam();
      for (final (id, role, active) in [
        ('owner', 'owner', true),
        ('staff', 'staff', true),
        ('former', 'staff', false),
      ]) {
        repo.members.add({
          'id': id,
          'display_name': id,
          'email': '$id@example.com',
          'role': role,
          'active': active,
        });
      }
      getIt.registerFactory<TeamCubit>(() => TeamCubit(repo));
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) =>
              MaterialApp(theme: darkTheme(), home: const TeamScreen()),
        ),
      );
      await tester.pumpAndSettle();
      // Only active non-owners receive a removal control.
      expect(find.text('Remove access'), findsOneWidget);
      await tester.ensureVisible(find.text('Remove access'));
      await tester.tap(find.text('Remove access'));
      await tester.pumpAndSettle();
      expect(repo.removed, isEmpty);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.removed, isEmpty);
      await tester.tap(find.text('Remove access'));
      await tester.pumpAndSettle();
      repo.loadWait = Completer<void>();
      await tester.tap(find.text('Confirm'));
      await tester.pump();
      expect(repo.removed, [('staff', false)]);
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Remove access'),
      );
      expect(button.onPressed, isNull);
      repo.loadWait!.complete();
      await tester.pumpAndSettle();
      expect(find.text('Remove access'), findsNothing);
      expect(find.text('Staff access removed.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
  test(
    'team mutations stay disabled until their refreshed list arrives',
    () async {
      final repo = EmailTeam();
      final team = TeamCubit(repo);
      await team.load();
      repo.loadWait = Completer<void>();
      final revoke = team.revoke('pending', invitation: true);
      await Future<void>.delayed(Duration.zero);
      expect(team.state.busy, true);
      await team.load();
      await team.resendEmail('pending');
      expect(repo.resends, 0);
      repo.loadWait!.complete();
      await revoke;
      expect(team.state.busy, false);
      expect(team.state.notice, 'Pending access cancelled.');
      await team.close();
      await team.revoke('pending');
      expect(repo.revocations, 1);
    },
  );
  test(
    'a saved grant remains successful when the follow-up workspace refresh fails',
    () async {
      final source = RefreshFailure(), repo = EmailTeam();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final cubit = StaffAssignmentCubit(workspace, repo);
      source.failLoad = true;
      final result = await cubit.add(
        StaffAccessDraft(
          name: 'Test Staff',
          email: 'staff@example.com',
          role: 'staff',
          permissions: [],
          assignments: [BusinessAssignment('b', [])],
        ),
      );
      expect(result, isNotNull);
      expect(result!.sent, false);
      expect(repo.adds, 1);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.busy, false);
      await cubit.close();
      await workspace.close();
    },
  );
  test(
    'email resend failure stays visible without losing pending access',
    () async {
      final repo = EmailTeam()..failEmail = true;
      final team = TeamCubit(repo);
      await team.load();
      await team.resendEmail('pending');
      expect(team.state.invitations, hasLength(1));
      expect(team.state.notice, contains('Email could not be sent'));
      expect(team.state.error, isNull);
      await team.close();
    },
  );
}
