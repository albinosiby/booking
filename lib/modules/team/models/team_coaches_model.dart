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
  }) : coaches = List.unmodifiable(coaches),
       plans = List.unmodifiable(plans),
       spaces = List.unmodifiable(spaces);
  final String id, name;
  final int version;
  final List<PoolCoach> coaches;
  final List<CoachPlan> plans;
  final List<CoachSpace> spaces;
  @override
  List<Object?> get props => [id, name, version, coaches, plans, spaces];
}

enum CoachEditor { add, assign, spaces }

class TeamCoachesModel extends Equatable {
  TeamCoachesModel({
    Iterable<CoachBusiness> businesses = const [],
    this.loading = false,
    this.busy = false,
    this.error,
    this.editor,
    this.businessId,
    this.coachId,
    this.name = '',
    this.phone = '',
    Iterable<String> planIds = const [],
    Iterable<String> spaceIds = const [],
  }) : businesses = List.unmodifiable(businesses),
       planIds = Set.unmodifiable(planIds),
       spaceIds = Set.unmodifiable(spaceIds);
  final List<CoachBusiness> businesses;
  final bool loading, busy;
  final String? error, businessId, coachId;
  final String name, phone;
  final CoachEditor? editor;
  final Set<String> planIds, spaceIds;
  PoolCoach? get selectedCoach =>
      selectedBusiness?.coaches.where((c) => c.id == coachId).firstOrNull;
  List<CoachPlan> get eligiblePlans =>
      selectedBusiness?.plans
          .where((p) => p.coveredBy(selectedCoach?.poolIds ?? []))
          .toList() ??
      [];
  List<CoachPlan> get affectedPlans =>
      selectedBusiness?.plans
          .where((p) => p.coachId == coachId && !p.coveredBy(spaceIds))
          .toList() ??
      [];

  CoachBusiness? get selectedBusiness =>
      businesses.where((b) => b.id == businessId).firstOrNull;
  TeamCoachesModel copy({
    Iterable<CoachBusiness>? businesses,
    bool? loading,
    bool? busy,
    String? error,
    CoachEditor? editor,
    String? businessId,
    String? coachId,
    String? name,
    String? phone,
    Iterable<String>? planIds,
    Iterable<String>? spaceIds,
    bool clearEditor = false,
  }) => TeamCoachesModel(
    businesses: businesses ?? this.businesses,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error,
    editor: clearEditor ? null : editor ?? this.editor,
    businessId: businessId ?? this.businessId,
    coachId: coachId ?? this.coachId,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    planIds: planIds ?? this.planIds,
    spaceIds: spaceIds ?? this.spaceIds,
  );
  @override
  List<Object?> get props => [
    businesses,
    loading,
    busy,
    error,
    editor,
    businessId,
    coachId,
    name,
    phone,
    planIds,
    spaceIds,
  ];
}
