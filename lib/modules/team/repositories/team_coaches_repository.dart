import '../../../utils/exceptions/app_exception.dart';
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

/// Reuses the version-checked pool configuration save; no separate coach database.
class ConfigurationTeamCoachesRepository implements TeamCoachesRepository {
  ConfigurationTeamCoachesRepository(this.workspace, this.pools);
  final WorkspaceRepository workspace;
  final PoolRepository pools;
  Future<Workspace> _workspace() async {
    final data = await workspace.load();
    if (!data.isOwner) {
      throw const AppException('Only the owner can manage coaches.');
    }
    return data;
  }

  @override
  Future<List<CoachBusiness>> load() async {
    final data = await _workspace();
    return List.unmodifiable(
      data.businesses
          .where(
            (b) =>
                b.type == BusinessType.pool &&
                b.configuration?['kind'] == 'pool_v1',
          )
          .map((b) {
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

  Future<PoolConfiguration> _configuration(String id, int version) async {
    final data = await _workspace();
    final b = data.businesses
        .where(
          (b) =>
              b.id == id &&
              b.type == BusinessType.pool &&
              b.configuration?['kind'] == 'pool_v1',
        )
        .firstOrNull;
    if (b == null) {
      throw const AppException(
        'Save the pool configuration before adding a coach.',
      );
    }
    if (b.version != version) {
      throw const AppException(
        'Pool settings changed. Refresh coaches and try again.',
        code: 'CONFLICT',
      );
    }
    return PoolConfiguration.fromJson(b.configuration!);
  }

  @override
  Future<void> add(
    String businessId,
    int version,
    String name,
    String phone,
  ) async {
    final c = await _configuration(businessId, version);
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
      throw const AppException('A pool business can have up to 100 coaches.');
    }
    await pools.save(
      businessId,
      version,
      c.copyWith(
        coaches: [
          ...c.coaches,
          PoolCoach(
            id: const Uuid().v4(),
            name: name.trim(),
            phone: phone.trim(),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> assign(
    String businessId,
    int version,
    String coachId,
    Set<String> planIds,
  ) async {
    final c = await _configuration(businessId, version);
    if (!c.coaches.any((v) => v.id == coachId)) {
      throw const AppException(
        'This coach is no longer available. Refresh and try again.',
      );
    }
    if (planIds.any((id) => !c.plans.any((p) => p.id == id && p.coaching))) {
      throw const AppException('Choose coaching plans in this business.');
    }
    final coach = c.coaches.firstWhere((v) => v.id == coachId);
    if (c.plans.any(
      (p) =>
          planIds.contains(p.id) &&
          (p.poolIds.isEmpty || !p.poolIds.every(coach.poolIds.contains)),
    )) {
      throw const AppException(
        'Assign this coach to every eligible pool before selecting that coaching plan.',
      );
    }
    await pools.save(
      businessId,
      version,
      c.copyWith(
        plans: c.plans.map((p) {
          if (!p.coaching) return p;
          if (planIds.contains(p.id)) return p.copyWith(coachId: coachId);
          return p.coachId == coachId ? p.copyWith(clearCoach: true) : p;
        }),
      ),
    );
  }

  @override
  Future<void> assignSpaces(
    String businessId,
    int version,
    String coachId,
    Set<String> poolIds, {
    bool removeAffectedPlans = false,
  }) async {
    final c = await _configuration(businessId, version);
    if (!c.coaches.any((v) => v.id == coachId)) {
      throw const AppException('This coach is no longer available.');
    }
    if (poolIds.any((id) => !c.pools.any((p) => p.id == id))) {
      throw const AppException('Choose pool spaces in this business.');
    }
    final affected = c.plans
        .where(
          (p) =>
              p.coaching &&
              p.coachId == coachId &&
              (p.poolIds.isEmpty || !p.poolIds.every(poolIds.contains)),
        )
        .map((p) => p.id)
        .toSet();
    if (affected.isNotEmpty && !removeAffectedPlans) {
      throw const AppException(
        'Confirm removal of affected coaching-plan assignments.',
      );
    }
    await pools.save(
      businessId,
      version,
      c.copyWith(
        coaches: c.coaches.map(
          (v) => v.id == coachId ? v.withPools(poolIds) : v,
        ),
        plans: c.plans.map(
          (p) => affected.contains(p.id) ? p.copyWith(clearCoach: true) : p,
        ),
      ),
    );
  }
}
