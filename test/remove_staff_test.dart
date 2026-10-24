import 'package:eden_booking/modules/team/cubit/team_cubit.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/team/cubit/staff_assignment_cubit.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/team/screens/staff_assignment_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'staff_assignment_test.dart' show StaffRepository;

Map<String, dynamic> member({
  String role = 'staff',
  bool active = true,
  bool pending = false,
}) => {
  'id': 'person',
  'display_name': 'Alex',
  'email': 'alex@example.com',
  'role': role,
  'active': active,
  'pending_access': pending,
  'permissions': <String>[],
  'assignments': <Map<String, dynamic>>[],
};

class RemovalSource extends StaffRepository {
  final removed = <String>[];
  Completer<void>? gate;
  bool fail = false;
  @override
  Future<void> revoke(String id, {bool invitation = false}) async {
    removed.add(id);
    await gate?.future;
    if (fail) throw StateError('failed');
  }
}

class RemovedButOffline extends Fake implements TeamRepository {
  bool removed = false;
  @override
  Future<Map<String, dynamic>> load() async {
    if (removed) throw StateError('offline');
    return {
      'members': [member()],
      'invitations': <Object>[],
    };
  }

  @override
  Future<void> revoke(String id, {bool invitation = false}) async {
    removed = true;
  }
}

void main() {
  tearDown(() async => getIt.reset());
  test('a confirmed removal stays removed if the list refresh fails', () async {
    final repository = RemovedButOffline();
    final team = TeamCubit(repository);
    await team.load();
    await team.revoke('person');
    expect(team.state.members.single['active'], isFalse);
    expect(team.state.members.single['assignments'], isEmpty);
    expect(team.state.notice, contains('History preserved'));
    expect(team.state.busy, isFalse);
    await team.close();
  });
  test(
    'removal guards owners, inactive and pending members and prevents duplicate requests',
    () async {
      final source = RemovalSource(), session = WorkspaceCubit(RemovalSource());
      await session.load();
      for (final target in [
        member(role: 'owner'),
        member(active: false),
        member(pending: true),
      ]) {
        final c = StaffAssignmentCubit(
          session,
          LocalApiTeamRepository(source),
          member: target,
        );
        expect(c.canRemove, isFalse);
        expect(await c.remove(), isFalse);
        await c.close();
      }
      final c = StaffAssignmentCubit(
        session,
        LocalApiTeamRepository(source),
        member: member(role: 'manager'),
      );
      source.gate = Completer();
      final request = c.remove();
      expect(c.state.busy, isTrue);
      expect(c.state.removing, isTrue);
      expect(await c.remove(), isFalse);
      expect(source.removed, ['person']);
      source.gate!.complete();
      expect(await request, isTrue);
      expect(c.state.removed, isTrue);
      expect(c.state.busy, isFalse);
      expect(c.canRemove, isFalse);
      await c.close();
      await session.close();
    },
  );
  test('a failed removal keeps the member available for retry', () async {
    final source = RemovalSource()..fail = true,
        session = WorkspaceCubit(RemovalSource());
    await session.load();
    final c = StaffAssignmentCubit(
      session,
      LocalApiTeamRepository(source),
      member: member(),
    );
    expect(await c.remove(), isFalse);
    expect(c.state.removed, isFalse);
    expect(c.state.busy, isFalse);
    expect(c.state.removalError, isNotNull);
    source.fail = false;
    expect(await c.remove(), isTrue);
    expect(c.state.removalError, isNull);
    await c.close();
    await session.close();
  });
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'manager removal requires confirmation and returns to team at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final source = RemovalSource();
        getIt.registerSingleton<WorkspaceRepository>(source);
        registerFeatureDependencies(getIt);
        final session = WorkspaceCubit(source);
        await session.load();
        addTearDown(session.close);
        await tester.pumpWidget(
          BlocProvider.value(
            value: session,
            child: ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => MaterialApp(
                home: Builder(
                  builder: (context) => Scaffold(
                    body: TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => StaffAssignmentScreen(
                            member: member(role: 'manager'),
                          ),
                        ),
                      ),
                      child: const Text('Open member'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open member'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Remove manager'));
        await tester.tap(find.text('Remove manager'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('attendance history will be preserved'),
          findsOneWidget,
        );
        await tester.tap(find.text('Keep member'));
        await tester.pumpAndSettle();
        expect(source.removed, isEmpty);
        await tester.tap(find.text('Remove manager'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Remove manager'));
        await tester.pumpAndSettle();
        expect(source.removed, ['person']);
        expect(find.text('Open member'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
