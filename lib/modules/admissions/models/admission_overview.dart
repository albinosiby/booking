import 'package:equatable/equatable.dart';
import 'admission_models.dart';

/// One independently paginated roster. A null plan represents previous plans.
class AdmissionRoster extends Equatable {
  const AdmissionRoster({
    required this.id,
    this.plan,
    this.items = const [],
    this.next,
    this.loading = false,
    this.error,
  });
  final String id;
  final AdmissionPlan? plan;
  final List<Admission> items;
  final int? next;
  final bool loading;
  final String? error;

  AdmissionRoster copyWith({
    List<Admission>? items,
    int? next,
    bool clearNext = false,
    bool? loading,
    String? error,
  }) => AdmissionRoster(
    id: id,
    plan: plan,
    items: items ?? this.items,
    next: clearNext ? null : next ?? this.next,
    loading: loading ?? this.loading,
    error: error,
  );

  @override
  List<Object?> get props => [id, plan, items, next, loading, error];
}

class AdmissionOverview extends Equatable {
  const AdmissionOverview({
    this.coaching = false,
    this.businessId,
    this.spaceId,
    this.query = '',
    this.status,
    this.rosters = const {},
  });
  final bool coaching;
  final String? businessId, spaceId, status;
  final String query;
  final Map<String, AdmissionRoster> rosters;

  AdmissionOverview copyWith({
    bool? coaching,
    String? businessId,
    String? spaceId,
    bool clearSelection = false,
    bool clearSpace = false,
    String? query,
    String? status,
    bool clearStatus = false,
    Map<String, AdmissionRoster>? rosters,
  }) => AdmissionOverview(
    coaching: coaching ?? this.coaching,
    businessId: clearSelection ? null : businessId ?? this.businessId,
    spaceId: clearSelection || clearSpace ? null : spaceId ?? this.spaceId,
    query: query ?? this.query,
    status: clearStatus ? null : status ?? this.status,
    rosters: rosters == null ? this.rosters : Map.unmodifiable(rosters),
  );

  @override
  List<Object?> get props => [
    coaching,
    businessId,
    spaceId,
    query,
    status,
    rosters,
  ];
}
