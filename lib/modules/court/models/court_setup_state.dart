import '../../configuration_drafts/models/configuration_draft.dart';
import '../../workspace/models/workspace_state.dart';
import '../../workspace/models/workspace.dart';
import 'court_configuration.dart';
import 'court_screen_models.dart';

class CourtSetupState extends WorkspaceState {
  CourtSetupState.fromSnapshot(
    WorkspaceState snapshot, {
    required this.businessId,
    required this.draft,
    required this.version,
    this.section = CourtSection.overview,
    this.selectedId,
    this.dirty = false,
    this.saving = false,
    this.editingReady = false,
    this.allowExit = false,
    this.resourceFlow = false,
    this.formError,
    this.localDraftStatus = LocalDraftStatus.idle,
    this.localDraftMessage,
  }) : super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  factory CourtSetupState.initial(WorkspaceState snapshot, String id) {
    final b = snapshot.data.businesses.where((b) => b.id == id).firstOrNull;
    return CourtSetupState.fromSnapshot(
      snapshot,
      businessId: id,
      draft: CourtConfiguration.initial(b),
      version: b?.version ?? 1,
      editingReady: b?.ready ?? false,
    );
  }
  final String businessId;
  final CourtConfiguration draft;
  final int version;
  final CourtSection section;
  final String? selectedId, formError;
  final bool resourceFlow;
  final bool dirty, saving, editingReady, allowExit;
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
  CourtResource? get selectedCourt =>
      draft.courts.where((p) => p.id == selectedId).firstOrNull;
  CourtOverviewModel get overviewModel =>
      CourtOverviewModel(draft, business?.ready ?? false);
  CourtResourcesModel get resourcesModel =>
      CourtResourcesModel(draft.courts, selectedCourt);
  CourtPricingModel get pricingModel =>
      CourtPricingModel(draft.courts, selectedCourt, currency);
  CourtReviewModel get reviewModel => CourtReviewModel(draft, currency);
  CourtSetupState copyWith({
    WorkspaceState? snapshot,
    CourtConfiguration? draft,
    int? version,
    CourtSection? section,
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
  }) => CourtSetupState.fromSnapshot(
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
  ];
}
