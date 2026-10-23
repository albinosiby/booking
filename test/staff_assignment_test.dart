import 'dart:async';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/team/screens/staff_assignment_screen.dart';
import 'package:eden_booking/modules/team/cubit/staff_assignment_cubit.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/team/models/staff_access_draft.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';

class StaffRepository extends Fake implements WorkspaceRepository {
  Map<String, dynamic>? invitation;
  bool failUpdate = false;
  Completer<void>? updateWait;
  @override
  Future<void> updateMember(String id, Map<String, dynamic> data) async {
    if (failUpdate) throw StateError('save failed');
    await updateWait?.future;
  }

  @override
  Future<Workspace> load() async => const Workspace(
    organization: Organization(
      id: 'o',
      name: 'Eden',
      phone: '123456789',
      currency: 'INR',
    ),
    membership: {'role': 'owner'},
    businesses: [
      Business(
        id: 'b',
        name: 'Eden Turf',
        type: BusinessType.turf,
        status: 'ready',
        locationId: 'l',
        version: 1,
        resources: [Resource(id: 'r', name: 'Turf 1', capacity: 1)],
      ),
    ],
  );
  @override
  Future<Map<String, dynamic>> addTeamMember(Map<String, dynamic> data) async {
    invitation = data;
    return {'id': 'pending', 'delivery': 'sent'};
  }
}

void main() {
  tearDown(() async {
    await getIt.reset();
  });
  testWidgets(
    'staff form preserves selected resources and leaves financial reports disabled',
    (tester) async {
      final repository = StaffRepository();
      getIt.registerSingleton<WorkspaceRepository>(repository);
      registerFeatureDependencies(getIt);
      final workspace = WorkspaceCubit(repository);
      await workspace.load();
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) => MaterialApp(
              theme: darkTheme(),
              home: const StaffAssignmentScreen(),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextFormField).at(0), 'Test Staff');
      await tester.enterText(
        find.byType(TextFormField).at(1),
        'staff@example.com',
      );
      final business = find.widgetWithText(CheckboxListTile, 'Eden Turf');
      await tester.ensureVisible(business);
      await tester.tap(business);
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(business).value, true);
      final restrict = find.widgetWithText(
        SwitchListTile,
        'Restrict to selected resources',
      );
      await tester.ensureVisible(restrict);
      await tester.tap(restrict);
      await tester.pump();
      final resource = find.widgetWithText(CheckboxListTile, 'Turf 1');
      await tester.ensureVisible(resource);
      await tester.tap(resource);
      await tester.pump();
      final coach = find.widgetWithText(SwitchListTile, 'Also a coach');
      await tester.ensureVisible(coach);
      await tester.tap(coach);
      await tester.pump();
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, 'Mark attendance'),
            )
            .value,
        false,
      );
      for (final permission in [
        'View bookings',
        'Create and edit bookings',
        'Mark attendance',
      ]) {
        final toggle = find.widgetWithText(SwitchListTile, permission);
        await tester.ensureVisible(toggle);
        await tester.tap(toggle);
        await tester.pump();
      }
      expect(
        find.textContaining('After this team member signs in'),
        findsOneWidget,
      );
      final submit = find.text('Add team member');
      await tester.ensureVisible(submit);
      await tester.tap(submit);
      await tester.pumpAndSettle();
      expect(repository.invitation, isNotNull);
      expect(repository.invitation!['assignments'], [
        {
          'business_id': 'b',
          'resource_ids': ['r'],
        },
      ]);
      expect(
        repository.invitation!['permissions'],
        isNot(contains('view_finance')),
      );
      expect(
        repository.invitation!['permissions'],
        unorderedEquals([
          'coach',
          'view_bookings',
          'manage_bookings',
          'mark_attendance',
        ]),
      );
      expect(
        repository.invitation!['permissions'],
        isNot(contains('manage_subscriptions')),
      );
      expect(find.text('Access email sent'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await workspace.close();
    },
  );
  test(
    'coaching eligibility stays tied to saved resource access and failed saves retain edits',
    () async {
      final repository = StaffRepository();
      final workspace = WorkspaceCubit(repository);
      await workspace.load();
      final cubit = StaffAssignmentCubit(
        workspace,
        LocalApiTeamRepository(repository),
        member: {
          'id': 'staff',
          'role': 'staff',
          'permissions': ['coach'],
          'assignments': [
            {
              'business_id': 'b',
              'resource_ids': ['r'],
            },
          ],
        },
      );
      addTearDown(workspace.close);
      addTearDown(cubit.close);
      expect(cubit.coachingAccessChanged, false);
      cubit.selectPermission('mark_attendance', true);
      expect(cubit.coachingAccessChanged, false);
      cubit.restrictBusiness('b', false);
      expect(cubit.coachingAccessChanged, true);
      final draft = StaffAccessDraft(
        name: 'Test Staff',
        email: 'staff@example.com',
        role: 'staff',
        permissions: cubit.state.permissions,
        assignments: [BusinessAssignment('b', [])],
      );
      repository.failUpdate = true;
      expect(await cubit.update('staff', draft), false);
      expect(cubit.coachingAccessChanged, true);
      repository.failUpdate = false;
      expect(await cubit.update('staff', draft), true);
      expect(cubit.coachingAccessChanged, false);
      expect(cubit.state.accessRevision, 1);
      cubit.selectPermission('coach', false);
      expect(cubit.coachingAccessChanged, true);
    },
  );

  test(
    'a change made while a save is pending is never treated as saved access',
    () async {
      final repository = StaffRepository()..updateWait = Completer<void>();
      final workspace = WorkspaceCubit(repository);
      await workspace.load();
      final cubit = StaffAssignmentCubit(
        workspace,
        LocalApiTeamRepository(repository),
      );
      addTearDown(workspace.close);
      addTearDown(cubit.close);
      cubit.selectBusiness('b', true);
      final draft = StaffAccessDraft(
        name: 'Test Staff',
        email: 'staff@example.com',
        role: 'staff',
        permissions: [],
        assignments: [BusinessAssignment('b', [])],
      );
      final pending = cubit.update('staff', draft);
      cubit.selectPermission('coach', true);
      repository.updateWait!.complete();
      expect(await pending, true);
      expect(cubit.coachingAccessChanged, true);
    },
  );
}
