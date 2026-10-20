import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/businesses/models/business_draft.dart';
import 'package:eden_booking/modules/businesses/cubit/resource_setup_cubit.dart';
import 'package:eden_booking/modules/team/cubit/staff_assignment_cubit.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/team/models/staff_access_draft.dart';

class Source extends Fake implements WorkspaceRepository {
  int writes = 0;
  final snapshot = const Workspace(
    businesses: [
      Business(
        id: 'pool',
        name: 'Pool',
        type: BusinessType.pool,
        status: 'draft',
        locationId: 'location',
        version: 1,
        resources: [],
      ),
    ],
  );
  @override
  Future<Workspace> load() async => snapshot;
  @override
  Future<void> addBusiness(Map<String, dynamic> data) async {
    writes++;
  }
}

class AlternativeTeamRepository extends Fake implements TeamRepository {
  StaffAccessDraft? saved;
  @override
  Future<String> invite(StaffAccessDraft draft) async {
    saved = draft;
    return 'private-link';
  }
}

class AlternativeBusinessRepository extends Fake implements BusinessRepository {
  BusinessConfiguration? saved;
  bool fail = false;
  @override
  Future<void> configure(String id, BusinessConfiguration configuration) async {
    if (fail) throw AppException('Owner access required.', code: 'FORBIDDEN');
    saved = configuration;
  }
}

void main() {
  test(
    'staff screen works with an alternative repository and retains immutable choices after refresh',
    () async {
      final source = Source(), repository = AlternativeTeamRepository();
      final session = WorkspaceCubit(source);
      await session.load();
      final screen = StaffAssignmentCubit(session, repository);
      screen.selectBusiness('pool', true);
      screen.restrictBusiness('pool', true);
      screen.selectResource('pool', 'lane', true);
      expect(
        () => screen.state.resources['pool']!.add('other'),
        throwsUnsupportedError,
      );
      final draft = StaffAccessDraft(
        name: 'Manager',
        email: 'staff@example.com',
        role: screen.state.role,
        permissions: screen.state.permissions,
        assignments: [
          BusinessAssignment('pool', screen.state.resources['pool']!),
        ],
      );
      expect(await screen.invite(draft), 'private-link');
      await Future<void>.delayed(Duration.zero);
      expect(repository.saved, same(draft));
      expect(screen.state.resources['pool'], {'lane'});
      expect(screen.state.permissions, isNot(contains('view_finance')));
      expect(screen.state.busy, false);
      await screen.close();
      await session.close();
    },
  );
  test(
    'resource screen preserves wizard settings after persistence refresh',
    () async {
      final source = Source(), repository = AlternativeBusinessRepository();
      final session = WorkspaceCubit(source);
      await session.load();
      final screen = ResourceSetupCubit(session, repository, 'pool');
      screen.selectStep(1);
      screen.selectDay(7, false);
      screen.selectEntitlement('visits');
      final configuration = BusinessConfiguration(
        version: 1,
        opensAt: '06:00',
        closesAt: '23:00',
        days: screen.state.days.toList(),
        durationMinutes: 60,
        priceMinor: 120000,
        bufferMinutes: 0,
        planName: 'Monthly',
        validityDays: 30,
        entitlement: screen.state.entitlement,
        visitLimit: 20,
      );
      expect(await screen.configure('pool', configuration), true);
      await Future<void>.delayed(Duration.zero);
      expect(repository.saved, same(configuration));
      expect(screen.state.step, 1);
      expect(screen.state.days, isNot(contains(7)));
      expect(screen.state.entitlement, 'visits');
      await screen.close();
      await session.close();
    },
  );
  test(
    'failed feature write restores busy state and preserves selections',
    () async {
      final session = WorkspaceCubit(Source());
      await session.load();
      final repository = AlternativeBusinessRepository()..fail = true;
      final screen = ResourceSetupCubit(session, repository, 'pool');
      screen.selectStep(1);
      screen.selectDay(7, false);
      final configuration = BusinessConfiguration(
        version: 1,
        opensAt: '06:00',
        closesAt: '23:00',
        days: screen.state.days.toList(),
        durationMinutes: 60,
        priceMinor: 120000,
        bufferMinutes: 0,
      );
      expect(await screen.configure('pool', configuration), false);
      await Future<void>.delayed(Duration.zero);
      expect(screen.state.busy, false);
      expect(screen.state.error, 'Owner access required.');
      expect(screen.state.step, 1);
      expect(screen.state.days, isNot(contains(7)));
      await screen.close();
      await session.close();
    },
  );
}
