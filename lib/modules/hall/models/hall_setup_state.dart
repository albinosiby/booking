import '../../configuration_drafts/models/configuration_draft.dart';
import '../../workspace/models/workspace_state.dart';
import '../../workspace/models/workspace.dart';
import 'hall_configuration.dart';
import 'hall_screen_models.dart';

class HallSetupState extends WorkspaceState {
  HallSetupState.fromSnapshot(
    WorkspaceState snapshot, {
    required this.businessId,
    required this.draft,
    required this.version,
    this.section = HallSection.overview,
    this.selectedId,
    this.selectedOption,
    this.dirty = false,
    this.saving = false,
    this.editingReady = false,
    this.allowExit = false,
    this.formError,
    this.localDraftStatus = LocalDraftStatus.idle,
    this.localDraftMessage,
  }) : super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  factory HallSetupState.initial(WorkspaceState snapshot, String id) {
    final b = snapshot.data.businesses.where((b) => b.id == id).firstOrNull;
    return HallSetupState.fromSnapshot(
      snapshot,
      businessId: id,
      draft: HallConfiguration.initial(b),
      version: b?.version ?? 1,
      editingReady: b?.ready ?? false,
    );
  }
  final String businessId;
  final HallConfiguration draft;
  final int version;
  final HallSection section;
  final String? selectedId, selectedOption, formError;
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
  HallResource? get selectedHall =>
      draft.halls.where((p) => p.id == selectedId).firstOrNull;
  HallOverviewModel get overviewModel =>
      HallOverviewModel(draft, business?.ready ?? false);
  HallResourcesModel get resourcesModel =>
      HallResourcesModel(draft.halls, selectedHall);
  HallPricingModel get pricingModel =>
      HallPricingModel(draft.halls, selectedHall, currency, selectedOption);
  HallReviewModel get reviewModel => HallReviewModel(draft, currency);
  HallSetupState copyWith({
    WorkspaceState? snapshot,
    HallConfiguration? draft,
    int? version,
    HallSection? section,
    String? selectedId,
    String? selectedOption,
    bool clearOption = false,
    bool clearSelection = false,
    bool? dirty,
    bool? saving,
    bool? editingReady,
    bool? allowExit,
    String? formError,
    LocalDraftStatus? localDraftStatus,
    String? localDraftMessage,
  }) => HallSetupState.fromSnapshot(
    snapshot ?? this,
    businessId: businessId,
    draft: draft ?? this.draft,
    version: version ?? this.version,
    section: section ?? this.section,
    selectedId: clearSelection ? null : selectedId ?? this.selectedId,
    selectedOption: (clearOption || clearSelection)
        ? null
        : selectedOption ?? this.selectedOption,
    dirty: dirty ?? this.dirty,
    saving: saving ?? this.saving,
    editingReady: editingReady ?? this.editingReady,
    allowExit: allowExit ?? this.allowExit,
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
    selectedOption,
    dirty,
    saving,
    editingReady,
    allowExit,
    formError,
  ];
}
