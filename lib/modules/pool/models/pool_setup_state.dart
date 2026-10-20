import '../../configuration_drafts/models/configuration_draft.dart';
import '../../workspace/models/workspace_state.dart';
import '../../workspace/models/workspace.dart';
import 'pool_configuration.dart';
import 'pool_screen_models.dart';

class PoolSetupState extends WorkspaceState {
  PoolSetupState.fromSnapshot(
    WorkspaceState snapshot, {
    required this.businessId,
    required this.draft,
    required this.version,
    this.section = PoolSection.overview,
    this.selectedId,
    this.dirty = false,
    this.saving = false,
    this.editingReady = false,
    this.allowExit = false,
    this.resourceFlow = false,
    this.formError,
    this.localDraftStatus = LocalDraftStatus.idle,
    this.localDraftMessage,
    Iterable<PoolCoach> coaches = const [],
    this.coachesLoading = false,
    this.coachError,
  }) : coaches = List.unmodifiable(coaches),
       super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  factory PoolSetupState.initial(WorkspaceState snapshot, String id) {
    final b = snapshot.data.businesses.where((b) => b.id == id).firstOrNull;
    return PoolSetupState.fromSnapshot(
      snapshot,
      businessId: id,
      draft: PoolConfiguration.initial(b),
      version: b?.version ?? 1,
      editingReady: b?.ready ?? false,
    );
  }
  final String businessId;
  final PoolConfiguration draft;
  final int version;
  final PoolSection section;
  final String? selectedId, formError, coachError;
  final bool resourceFlow;
  final bool dirty, saving, editingReady, allowExit, coachesLoading;
  final List<PoolCoach> coaches;
  final LocalDraftStatus localDraftStatus;
  final String? localDraftMessage;
  Business? get business =>
      data.businesses.where((b) => b.id == businessId).firstOrNull;
  bool get disabled =>
      saving ||
      busy ||
      [
        LocalDraftStatus.loading,
        LocalDraftStatus.loadFailed,
      ].contains(localDraftStatus);
  String get currency => data.organization?.currency ?? 'INR';
  String? get message => formError ?? error;
  PoolResource? get selectedPool =>
      draft.pools.where((p) => p.id == selectedId).firstOrNull;
  PoolGroupOffer? get selectedOffer =>
      draft.offers.where((o) => o.id == selectedId).firstOrNull;
  PoolPlan? get selectedPlan =>
      draft.plans.where((p) => p.id == selectedId).firstOrNull;
  PoolOverviewModel get overviewModel =>
      PoolOverviewModel(draft, business?.ready ?? false);
  PoolResourcesModel get resourcesModel =>
      PoolResourcesModel(draft.pools, selectedPool);
  PoolPricingModel get pricingModel =>
      PoolPricingModel(draft.pools, selectedPool, currency);
  PoolGroupsModel get groupsModel =>
      PoolGroupsModel(draft.offers, draft.pools, selectedOffer, currency);
  PoolPlansModel get plansModel => PoolPlansModel(
    List.unmodifiable(
      draft.plans.where((p) => p.coaching == (section == PoolSection.coaching)),
    ),
    draft.pools,
    selectedPlan,
    currency,
    [
      ...draft.coaches,
      ...coaches.where((c) => !draft.coaches.any((d) => d.id == c.id)),
    ],
    coachesLoading,
    coachError,
    draft.plans.length,
  );
  PoolReviewModel get reviewModel => PoolReviewModel(draft, currency);
  PoolSetupState copyWith({
    WorkspaceState? snapshot,
    PoolConfiguration? draft,
    int? version,
    PoolSection? section,
    String? selectedId,
    bool clearSelection = false,
    bool? dirty,
    bool? saving,
    bool? editingReady,
    bool? allowExit,
    bool? resourceFlow,
    String? formError,
    LocalDraftStatus? localDraftStatus,
    String? localDraftMessage,
    Iterable<PoolCoach>? coaches,
    bool? coachesLoading,
    String? coachError,
    bool clearCoachError = false,
  }) => PoolSetupState.fromSnapshot(
    snapshot ?? this,
    businessId: businessId,
    draft: draft ?? this.draft,
    version: version ?? this.version,
    section: section ?? this.section,
    selectedId: clearSelection ? null : selectedId ?? this.selectedId,
    dirty: dirty ?? this.dirty,
    saving: saving ?? this.saving,
    editingReady: editingReady ?? this.editingReady,
    allowExit: allowExit ?? this.allowExit,
    resourceFlow: resourceFlow ?? this.resourceFlow,
    formError: formError,
    localDraftStatus: localDraftStatus ?? this.localDraftStatus,
    localDraftMessage: localDraftStatus == null
        ? this.localDraftMessage
        : localDraftMessage,
    coaches: coaches ?? this.coaches,
    coachesLoading: coachesLoading ?? this.coachesLoading,
    coachError: clearCoachError ? null : coachError ?? this.coachError,
  );
  @override
  List<Object?> get props => [
    ...super.props,
    localDraftStatus,
    localDraftMessage,
    businessId,
    draft,
    version,
    section,
    selectedId,
    dirty,
    saving,
    editingReady,
    allowExit,
    resourceFlow,
    formError,
    coaches,
    coachesLoading,
    coachError,
  ];
}
