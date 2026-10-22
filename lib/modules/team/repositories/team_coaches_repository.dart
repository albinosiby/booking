import '../../../utils/exceptions/app_exception.dart';
import '../../coaching/repositories/coach_api.dart';
import '../../court/models/court_configuration.dart';
import '../../pool/models/pool_configuration.dart';
import '../../workspace/models/workspace.dart';
import '../../workspace/repositories/workspace_repository_interface.dart';
import '../models/staff_coaches.dart';
import '../models/team_coaches_model.dart';

abstract interface class TeamCoachesRepository {
  Future<CoachTeam> load();
  Future<void> assign(
    String businessId,
    int version,
    String coachId,
    Set<String> planIds,
  );

  /// The owner opts in or out of coaching; opting out releases their plans.
  Future<void> setOwnerCoach(bool coach);

  /// Upcoming classes that would overlap for [coachId] if they coached
  /// exactly [planIds]; one readable line per clash.
  Future<List<String>> conflicts(
    String businessId,
    String coachId,
    Set<String> planIds,
  );
}

const _courtTypes = {
  BusinessType.badminton,
  BusinessType.tennis,
  BusinessType.basketball,
};

/// Coaches are team members with the coach flag. Their spaces come from their
/// staff assignment, and plans are assigned without other setting changes.
class ConfigurationTeamCoachesRepository implements TeamCoachesRepository {
  ConfigurationTeamCoachesRepository(this.workspace, this.api);
  final WorkspaceRepository workspace;
  final CoachApi api;
  Future<Workspace> _workspace() async {
    final data = await workspace.load();
    if (!data.isOwner) {
      throw const AppException('Only the owner can manage coaches.');
    }
    return data;
  }

  static CoachBusiness? _business(Business b, Map<String, dynamic> team) {
    final kind = b.configuration?['kind'];
    final List<CoachSpace> spaces;
    final List<CoachPlan> plans;
    if (_courtTypes.contains(b.type) && kind == 'court_v1') {
      final c = CourtConfiguration.fromJson(b.configuration!);
      spaces = [for (final p in c.courts) CoachSpace(p.id, p.name)];
      plans = [
        for (final p in c.plans.where((p) => p.coaching))
          CoachPlan(p.id, p.name, p.coachId, p.courtIds),
      ];
    } else if (b.type == BusinessType.pool && kind == 'pool_v1') {
      final c = PoolConfiguration.fromJson(b.configuration!);
      spaces = [for (final p in c.pools) CoachSpace(p.id, p.name)];
      plans = [
        for (final p in c.plans.where((p) => p.coaching))
          CoachPlan(p.id, p.name, p.coachId, p.poolIds),
      ];
    } else {
      return null;
    }
    final all = spaces.map((s) => s.id);
    return CoachBusiness(
      id: b.id,
      name: b.name,
      version: b.version,
      court: kind == 'court_v1',
      spaces: spaces,
      plans: plans,
      // An empty staff assignment means every space of the business.
      coaches: [
        for (final c in staffCoaches(team, b.id))
          PoolCoach(
            id: c.id,
            name: c.name,
            owner: c.owner,
            poolIds: c.poolIds.isEmpty ? all : c.poolIds.where(all.contains),
          ),
      ],
    );
  }

  @override
  Future<CoachTeam> load() async {
    final data = await _workspace();
    final team = await workspace.team();
    return CoachTeam(
      ownerCoach: data.isCoach,
      members: [
        for (final m in team['members'] as List) Map<String, dynamic>.from(m),
      ],
      businesses: [for (final b in data.businesses) ?_business(b, team)],
    );
  }

  @override
  Future<void> assign(
    String businessId,
    int version,
    String coachId,
    Set<String> planIds,
  ) async {
    final data = await _workspace();
    final b = data.businesses.where((b) => b.id == businessId).firstOrNull;
    final c = b == null ? null : _business(b, await workspace.team());
    if (b == null || c == null) {
      throw const AppException(
        'Save the pool or court configuration before assigning a coach.',
      );
    }
    if (b.version != version) {
      throw const AppException(
        'Settings changed. Refresh staff details and try again.',
        code: 'CONFLICT',
      );
    }
    final coach = c.coaches.where((v) => v.id == coachId).firstOrNull;
    if (coach == null) {
      throw const AppException(
        'This coach is no longer available. Refresh and try again.',
      );
    }
    if (planIds.any((id) => !c.plans.any((p) => p.id == id))) {
      throw const AppException('Choose coaching plans in this business.');
    }
    if (c.plans.any(
      (p) =>
          planIds.contains(p.id) &&
          !(p.coachId == coachId
              ? p.keepsCoach(coach.poolIds)
              : p.coveredBy(coach.poolIds)),
    )) {
      throw AppException(
        'Assign ${coach.name} to every ${c.court ? 'court' : 'pool'} of that coaching plan first, in their staff access.',
      );
    }
    await api.assignPlans(businessId, version, {
      for (final p in c.plans)
        if (planIds.contains(p.id))
          p.id: coachId
        else if (p.coachId == coachId)
          p.id: null,
    });
  }

  @override
  Future<void> setOwnerCoach(bool coach) async {
    await _workspace();
    await api.setOwnerCoach(coach);
  }

  @override
  Future<List<String>> conflicts(
    String businessId,
    String coachId,
    Set<String> planIds,
  ) => api.conflicts(businessId, coachId, planIds);
}
