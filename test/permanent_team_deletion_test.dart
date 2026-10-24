import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/team/cubit/team_cubit.dart';
import 'package:eden_booking/modules/team/models/team_deletion_target.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/team/screens/team_screen.dart';
import 'package:eden_booking/modules/team/widgets/team_desktop_widgets.dart';

Map<String, dynamic> person(String id, String role, bool active) => {
  'id': id,
  'display_name': id == 'former' ? 'Former coach' : id,
  'email': '$id@example.com',
  'role': role,
  'active': active,
  'permissions': <String>[],
  'assignments': <Object>[],
};
Map<String, dynamic> invitation(
  String id, {
  bool cancelled = false,
  bool accepted = false,
}) => {
  'id': id,
  'display_name': id,
  'email': '$id@example.com',
  'role': 'staff',
  'permissions': <String>[],
  'expires_at': '2099-01-01T00:00:00Z',
  'revoked_at': cancelled ? '2030-01-01T00:00:00Z' : null,
  'accepted_at': accepted ? '2030-01-01T00:00:00Z' : null,
};

class Deletions extends Fake implements TeamRepository {
  final members = [
    person('owner', 'owner', true),
    person('active', 'staff', true),
    person('former', 'manager', false),
  ];
  final invites = [
    invitation('cancelled', cancelled: true),
    invitation('pending'),
  ];
  final deleted = <String>[];
  Completer<void>? gate;
  bool fail = false, offlineAfter = false;
  @override
  Future<Map<String, dynamic>> load() async {
    if (offlineAfter && deleted.isNotEmpty) throw StateError('offline');
    return {'members': members, 'invitations': invites};
  }

  @override
  Future<void> deletePermanently(String id, {bool invitation = false}) async {
    deleted.add('${invitation ? 'invitation' : 'member'}:$id');
    await gate?.future;
    if (fail) throw StateError('failed');
    (invitation ? invites : members).removeWhere((r) => r['id'] == id);
  }
}

void main() {
  tearDown(() async => getIt.reset());
  test(
    'only removed staff/managers and cancelled invitations are eligible',
    () {
      expect(
        TeamDeletionTarget.member(person('owner', 'owner', false)).eligible,
        isFalse,
      );
      expect(
        TeamDeletionTarget.member(person('active', 'staff', true)).eligible,
        isFalse,
      );
      expect(
        TeamDeletionTarget.member(person('former', 'staff', false)).eligible,
        isTrue,
      );
      expect(
        TeamDeletionTarget.invitation(invitation('pending')).eligible,
        isFalse,
      );
      expect(
        TeamDeletionTarget.invitation(
          invitation('cancelled', cancelled: true),
        ).eligible,
        isTrue,
      );
      expect(
        TeamDeletionTarget.invitation(
          invitation('accepted', cancelled: true, accepted: true),
        ).eligible,
        isFalse,
      );
    },
  );
  test(
    'Cubit guards active records, coalesces clicks and retains deletion after a failed refresh',
    () async {
      final r = Deletions();
      final team = TeamCubit(r);
      await team.load();
      await team.deletePermanently(
        TeamDeletionTarget.member(person('active', 'staff', false)),
      );
      expect(
        r.deleted,
        isEmpty,
        reason: 're-check the current saved state, not the old dialog',
      );
      r.gate = Completer();
      r.offlineAfter = true;
      final target = TeamDeletionTarget.member(r.members.last);
      final deleting = team.deletePermanently(target);
      await team.deletePermanently(target);
      expect(r.deleted, ['member:former']);
      r.gate!.complete();
      await deleting;
      expect(team.state.members.any((m) => m['id'] == 'former'), isFalse);
      expect(team.state.notice, contains('history kept'));
      expect(team.state.busy, isFalse);
      await team.close();
    },
  );
  test(
    'failed deletion keeps the record and cancelled invitations use the invitation endpoint',
    () async {
      final r = Deletions()..fail = true;
      final c = TeamCubit(r);
      await c.load();
      final target = TeamDeletionTarget.invitation(r.invites.first);
      await c.deletePermanently(target);
      expect(c.state.invitations, hasLength(2));
      expect(c.state.error, isNotNull);
      r.fail = false;
      await c.deletePermanently(target);
      expect(r.deleted.last, 'invitation:cancelled');
      expect(c.state.invitations, hasLength(1));
      await c.close();
    },
  );
  for (final width in [390.0, 1440.0]) {
    testWidgets(
      'permanent-delete confirmation preserves history and only removes the confirmed tile at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final r = Deletions();
        getIt.registerFactory<TeamCubit>(() => TeamCubit(r));
        await tester.pumpWidget(
          ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => const MaterialApp(home: TeamScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Delete permanently'), findsNWidgets(2));
        final tile = find.ancestor(
          of: find.text('Former coach'),
          matching: find.byType(TeamPersonTile),
        );
        final action = find.descendant(
          of: tile,
          matching: find.text('Delete permanently'),
        );
        await tester.ensureVisible(action);
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(
          find.textContaining(
            'login account and booking, payment and attendance history will be kept',
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Keep record'));
        await tester.pumpAndSettle();
        expect(r.deleted, isEmpty);
        await tester.tap(action);
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(FilledButton, 'Delete permanently'),
        );
        await tester.pumpAndSettle();
        expect(r.deleted, ['member:former']);
        expect(find.text('Former coach'), findsNothing);
        expect(find.text('owner'), findsOneWidget);
        expect(find.text('cancelled'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
