import 'package:equatable/equatable.dart';
import '../../pool/models/pool_configuration.dart';

class CoachSpace extends Equatable {
  const CoachSpace(this.id, this.name);
  final String id, name;
  @override
  List<Object?> get props => [id, name];
}

class CoachPlan extends Equatable {
  CoachPlan(this.id, this.name, this.coachId, Iterable<String> poolIds)
    : poolIds = List.unmodifiable(poolIds);
  final String id, name;
  final String? coachId;
  final List<String> poolIds;
  bool coveredBy(Iterable<String> assigned) =>
      poolIds.isNotEmpty && poolIds.every(assigned.contains);

  /// Whether a coach already on this plan may stay on it. Matches the
  /// configuration validators: a plan with no spaces never blocks its coach.
  bool keepsCoach(Iterable<String> assigned) =>
      poolIds.every(assigned.contains);
  @override
  List<Object?> get props => [id, name, coachId, poolIds];
}

class CoachBusiness extends Equatable {
  CoachBusiness({
    required this.id,
    required this.name,
    required this.version,
    required Iterable<PoolCoach> coaches,
    required Iterable<CoachPlan> plans,
    required Iterable<CoachSpace> spaces,
    this.court = false,
  }) : coaches = List.unmodifiable(coaches),
       plans = List.unmodifiable(plans),
       spaces = List.unmodifiable(spaces);
  final String id, name;
  final int version;

  /// Team members who coach here; `poolIds` lists every space they teach in.
  final List<PoolCoach> coaches;
  final List<CoachPlan> plans;
  final List<CoachSpace> spaces;

  /// Court businesses assign coaches to courts instead of pool spaces.
  final bool court;
  String get spacesLabel => court ? 'courts' : 'pool spaces';
  @override
  List<Object?> get props => [id, name, version, coaches, plans, spaces, court];
}

/// Pool and court businesses with their coaches, plus the team rows that
/// open a coach's staff access.
class CoachTeam extends Equatable {
  CoachTeam({
    Iterable<CoachBusiness> businesses = const [],
    Iterable<Map<String, dynamic>> members = const [],
    this.ownerCoach = false,
  }) : businesses = List.unmodifiable(businesses),
       members = List.unmodifiable(members);
  final List<CoachBusiness> businesses;
  final List<Map<String, dynamic>> members;

  /// Whether the owner also coaches.
  final bool ownerCoach;
  @override
  List<Object?> get props => [businesses, members, ownerCoach];
}

class TeamCoachesModel extends Equatable {
  TeamCoachesModel({
    Iterable<CoachBusiness> businesses = const [],
    Iterable<Map<String, dynamic>> members = const [],
    this.ownerCoach = false,
    this.loading = false,
    this.busy = false,
    this.editing = false,
    this.error,
    this.businessId,
    this.coachId,
    Iterable<String> planIds = const [],
  }) : businesses = List.unmodifiable(businesses),
       members = List.unmodifiable(members),
       planIds = Set.unmodifiable(planIds);
  final List<CoachBusiness> businesses;
  final List<Map<String, dynamic>> members;
  final bool ownerCoach, loading, busy;

  /// Whether the plan assignment editor is open.
  final bool editing;
  final String? error, businessId, coachId;
  final Set<String> planIds;
  PoolCoach? get selectedCoach =>
      selectedBusiness?.coaches.where((c) => c.id == coachId).firstOrNull;

  /// Plans the coach covers, plus plans already assigned to them so an
  /// assignment that is no longer covered can still be unticked.
  List<CoachPlan> get eligiblePlans =>
      selectedBusiness?.plans
          .where(
            (p) =>
                p.coachId == coachId ||
                p.coveredBy(selectedCoach?.poolIds ?? []),
          )
          .toList() ??
      [];
  CoachBusiness? get selectedBusiness =>
      businesses.where((b) => b.id == businessId).firstOrNull;
  Map<String, dynamic>? member(String id) =>
      members.where((m) => m['id'] == id).firstOrNull;

  /// Plans the owner coaches anywhere, released if they stop coaching.
  List<CoachPlan> plansOf(String coachId) => [
    for (final b in businesses) ...b.plans.where((p) => p.coachId == coachId),
  ];
  TeamCoachesModel copy({
    CoachTeam? team,
    bool? loading,
    bool? busy,
    bool? editing,
    String? error,
    String? businessId,
    String? coachId,
    Iterable<String>? planIds,
  }) => TeamCoachesModel(
    businesses: team?.businesses ?? businesses,
    members: team?.members ?? members,
    ownerCoach: team?.ownerCoach ?? ownerCoach,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    editing: editing ?? this.editing,
    error: error,
    businessId: businessId ?? this.businessId,
    coachId: coachId ?? this.coachId,
    planIds: planIds ?? this.planIds,
  );
  @override
  List<Object?> get props => [
    businesses,
    members,
    ownerCoach,
    loading,
    busy,
    editing,
    error,
    businessId,
    coachId,
    planIds,
  ];
}
