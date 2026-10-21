import '../../../utils/exceptions/app_exception.dart';
import '../../court/models/court_configuration.dart';
import '../../court/repositories/court_repository.dart';
import '../../pool/models/pool_configuration.dart';
import '../../pool/repositories/pool_repository.dart';
import '../../workspace/models/workspace.dart';
import '../../workspace/repositories/workspace_repository_interface.dart';
import '../models/team_coaches_model.dart';
import 'package:uuid/uuid.dart';

abstract interface class TeamCoachesRepository {
  Future<List<CoachBusiness>> load();
  Future<void> add(String businessId, int version, String name, String phone);
  Future<void> assignSpaces(
    String businessId,
    int version,
    String coachId,
    Set<String> poolIds, {
    bool removeAffectedPlans = false,
  });
  Future<void> assign(
    String businessId,
    int version,
    String coachId,
    Set<String> planIds,
  );
}

const _courtTypes = {
  BusinessType.badminton,
  BusinessType.tennis,
  BusinessType.basketball,
};

/// A pool or court configuration seen through the coach editor. Court coaches
/// are presented as [PoolCoach] contacts whose `poolIds` hold court IDs.
class _CoachTarget {
  _CoachTarget({
    required this.court,
    required this.coaches,
    required this.plans,
    required this.spaceIds,
    required this.write,
  });
  final bool court;
  final List<PoolCoach> coaches;
  final List<CoachPlan> plans;
  final Set<String> spaceIds;

  /// Saves [coaches] and applies plan coach changes (null clears the coach).
  final Future<void> Function(
    List<PoolCoach> coaches,
    Map<String, String?> planCoaches,
  )
  write;
  String get spaces => court ? 'courts' : 'pool spaces';
}

/// Reuses the version-checked pool or court configuration save; no separate
/// coach database.
class ConfigurationTeamCoachesRepository implements TeamCoachesRepository {
  ConfigurationTeamCoachesRepository(this.workspace, this.pools, [this.courts]);
  final WorkspaceRepository workspace;
  final PoolRepository pools;
  final CourtRepository? courts;
  Future<Workspace> _workspace() async {
    final data = await workspace.load();
    if (!data.isOwner) {
      throw const AppException('Only the owner can manage coaches.');
    }
    return data;
  }

  bool _pool(Business b) =>
      b.type == BusinessType.pool && b.configuration?['kind'] == 'pool_v1';
  bool _court(Business b) =>
      courts != null &&
      _courtTypes.contains(b.type) &&
      b.configuration?['kind'] == 'court_v1';

  @override
  Future<List<CoachBusiness>> load() async {
    final data = await _workspace();
    return List.unmodifiable(
      data.businesses.where((b) => _pool(b) || _court(b)).map((b) {
        if (_court(b)) {
          final c = CourtConfiguration.fromJson(b.configuration!);
          return CoachBusiness(
            id: b.id,
            name: b.name,
            version: b.version,
            court: true,
            coaches: c.coaches.map(_poolCoach),
            spaces: c.courts.map((p) => CoachSpace(p.id, p.name)),
            plans: c.plans
                .where((p) => p.coaching)
                .map((p) => CoachPlan(p.id, p.name, p.coachId, p.courtIds)),
          );
        }
        final c = PoolConfiguration.fromJson(b.configuration!);
        return CoachBusiness(
          id: b.id,
          name: b.name,
          version: b.version,
          coaches: c.coaches,
          spaces: c.pools.map((p) => CoachSpace(p.id, p.name)),
          plans: c.plans
              .where((p) => p.coaching)
              .map((p) => CoachPlan(p.id, p.name, p.coachId, p.poolIds)),
        );
      }),
    );
  }

  static PoolCoach _poolCoach(CourtCoach c) =>
      PoolCoach(id: c.id, name: c.name, phone: c.phone, poolIds: c.courtIds);

  Future<_CoachTarget> _target(String id, int version) async {
    final data = await _workspace();
    final b = data.businesses
        .where((b) => b.id == id && (_pool(b) || _court(b)))
        .firstOrNull;
    if (b == null) {
      throw const AppException(
        'Save the pool or court configuration before adding a coach.',
      );
    }
    if (b.version != version) {
      throw AppException(
        '${_court(b) ? 'Court' : 'Pool'} settings changed. Refresh coaches and try again.',
        code: 'CONFLICT',
      );
    }
    if (_court(b)) {
      final c = CourtConfiguration.fromJson(b.configuration!);
      return _CoachTarget(
        court: true,
        coaches: c.coaches.map(_poolCoach).toList(),
        plans: c.plans
            .where((p) => p.coaching)
            .map((p) => CoachPlan(p.id, p.name, p.coachId, p.courtIds))
            .toList(),
        spaceIds: c.courts.map((p) => p.id).toSet(),
        write: (coaches, planCoaches) => courts!.save(
          id,
          version,
          c.copyWith(
            coaches: coaches.map(
              (v) => CourtCoach(
                id: v.id,
                name: v.name,
                phone: v.phone,
                courtIds: v.poolIds,
              ),
            ),
            plans: c.plans.map(
              (p) => !planCoaches.containsKey(p.id)
                  ? p
                  : planCoaches[p.id] == null
                  ? p.copyWith(clearCoach: true)
                  : p.copyWith(coachId: planCoaches[p.id]),
            ),
          ),
        ),
      );
    }
    final c = PoolConfiguration.fromJson(b.configuration!);
    return _CoachTarget(
      court: false,
      coaches: c.coaches,
      plans: c.plans
          .where((p) => p.coaching)
          .map((p) => CoachPlan(p.id, p.name, p.coachId, p.poolIds))
          .toList(),
      spaceIds: c.pools.map((p) => p.id).toSet(),
      write: (coaches, planCoaches) => pools.save(
        id,
        version,
        c.copyWith(
          coaches: coaches,
          plans: c.plans.map(
            (p) => !planCoaches.containsKey(p.id)
                ? p
                : planCoaches[p.id] == null
                ? p.copyWith(clearCoach: true)
                : p.copyWith(coachId: planCoaches[p.id]),
          ),
        ),
      ),
    );
  }

  @override
  Future<void> add(
    String businessId,
    int version,
    String name,
    String phone,
  ) async {
    final c = await _target(businessId, version);
    if (name.trim().length < 2 ||
        name.trim().length > 100 ||
        !poolCoachPhoneValid(phone)) {
      throw const AppException('Enter a coach name and a valid phone number.');
    }
    String digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');
    if (c.coaches.any((v) => digits(v.phone) == digits(phone))) {
      throw const AppException(
        'A coach with this phone number already exists in this business.',
      );
    }
    if (c.coaches.length >= 100) {
      throw AppException(
        'A ${c.court ? 'court' : 'pool'} business can have up to 100 coaches.',
      );
    }
    await c.write([
      ...c.coaches,
      PoolCoach(id: const Uuid().v4(), name: name.trim(), phone: phone.trim()),
    ], const {});
  }

  @override
  Future<void> assign(
    String businessId,
    int version,
    String coachId,
    Set<String> planIds,
  ) async {
    final c = await _target(businessId, version);
    if (!c.coaches.any((v) => v.id == coachId)) {
      throw const AppException(
        'This coach is no longer available. Refresh and try again.',
      );
    }
    if (planIds.any((id) => !c.plans.any((p) => p.id == id))) {
      throw const AppException('Choose coaching plans in this business.');
    }
    final coach = c.coaches.firstWhere((v) => v.id == coachId);
    if (c.plans.any(
      (p) => planIds.contains(p.id) && !p.coveredBy(coach.poolIds),
    )) {
      throw AppException(
        c.court
            ? 'Assign this coach to every court of that coaching plan first.'
            : 'Assign this coach to every eligible pool before selecting that coaching plan.',
      );
    }
    await c.write(c.coaches, {
      for (final p in c.plans)
        if (planIds.contains(p.id))
          p.id: coachId
        else if (p.coachId == coachId)
          p.id: null,
    });
  }

  @override
  Future<void> assignSpaces(
    String businessId,
    int version,
    String coachId,
    Set<String> poolIds, {
    bool removeAffectedPlans = false,
  }) async {
    final c = await _target(businessId, version);
    if (!c.coaches.any((v) => v.id == coachId)) {
      throw const AppException('This coach is no longer available.');
    }
    if (!c.spaceIds.containsAll(poolIds)) {
      throw AppException('Choose ${c.spaces} in this business.');
    }
    final affected = c.plans
        .where((p) => p.coachId == coachId && !p.coveredBy(poolIds))
        .map((p) => p.id)
        .toSet();
    if (affected.isNotEmpty && !removeAffectedPlans) {
      throw const AppException(
        'Confirm removal of affected coaching-plan assignments.',
      );
    }
    await c.write(
      c.coaches.map((v) => v.id == coachId ? v.withPools(poolIds) : v).toList(),
      {for (final id in affected) id: null},
    );
  }
}
