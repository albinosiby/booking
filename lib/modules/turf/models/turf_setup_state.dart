import '../../configuration_drafts/models/configuration_draft.dart';
import '../../workspace/models/workspace_state.dart';
import '../../workspace/models/workspace.dart';
import 'turf_configuration.dart';
import 'turf_step_models.dart';

class TurfSetupState extends WorkspaceState {
  TurfSetupState.fromSnapshot(
    WorkspaceState snapshot, {
    required this.businessId,
    required this.draft,
    required this.version,
    this.step = 0,
    this.editMode = false,
    this.settingsOverview = false,
    this.editingReady = false,
    this.dirty = false,
    this.saving = false,
    this.formError,
    this.localDraftStatus = LocalDraftStatus.idle,
    this.localDraftMessage,
    this.allowExit = false,
    this.pricingSport,
    this.pricingOfferingId,
  }) : super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  factory TurfSetupState.initial(WorkspaceState snapshot, String id) {
    final business = snapshot.data.businesses
        .where((b) => b.id == id)
        .firstOrNull;
    return TurfSetupState.fromSnapshot(
      snapshot,
      businessId: id,
      draft: TurfConfiguration.initial(business),
      version: business?.version ?? 1,
    );
  }
  final String businessId;
  final TurfConfiguration draft;
  final int version, step;
  final bool dirty, saving, allowExit;
  final bool editMode, settingsOverview, editingReady;
  final String? formError;
  final TurfSport? pricingSport;
  final String? pricingOfferingId;
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
  TurfSportsScreenModel get sportsModel => TurfSportsScreenModel(draft.sports);
  TurfGroundsScreenModel get groundsModel =>
      TurfGroundsScreenModel(draft.grounds, draft.sports);
  TurfSpacesScreenModel get spacesModel =>
      TurfSpacesScreenModel(draft.grounds, draft.layouts, draft.sports);
  TurfOfferingsScreenModel get offeringsModel =>
      TurfOfferingsScreenModel(draft.layouts, draft.offerings, draft.sports);
  TurfRulesScreenModel get rulesModel => TurfRulesScreenModel(
    draft.operating,
    List.unmodifiable(draft.offerings.where((o) => o.enabled)),
    currency,
    draft.layouts,
    draft.grounds,
    pricingSport,
    pricingOfferingId,
    draft.cricketUsesFootball,
    draft.footballPricingComplete,
  );
  TurfSettingsOverviewModel get settingsModel => TurfSettingsOverviewModel(
    name: business?.name ?? 'Turf',
    configuration: draft,
    ready: business?.ready ?? false,
    dirty: dirty,
  );
  TurfReviewScreenModel get reviewModel => TurfReviewScreenModel(draft);
  TurfSetupState copyWith({
    WorkspaceState? snapshot,
    TurfConfiguration? draft,
    int? version,
    int? step,
    bool? editMode,
    bool? settingsOverview,
    bool? editingReady,
    bool? dirty,
    bool? saving,
    String? formError,
    LocalDraftStatus? localDraftStatus,
    String? localDraftMessage,
    bool? allowExit,
    TurfSport? pricingSport,
    String? pricingOfferingId,
    bool clearPricingOffering = false,
  }) => TurfSetupState.fromSnapshot(
    snapshot ?? this,
    businessId: businessId,
    draft: draft ?? this.draft,
    version: version ?? this.version,
    step: step ?? this.step,
    editMode: editMode ?? this.editMode,
    settingsOverview: settingsOverview ?? this.settingsOverview,
    editingReady: editingReady ?? this.editingReady,
    dirty: dirty ?? this.dirty,
    saving: saving ?? this.saving,
    formError: formError,
    localDraftStatus: localDraftStatus ?? this.localDraftStatus,
    localDraftMessage: localDraftStatus == null
        ? this.localDraftMessage
        : localDraftMessage,
    allowExit: allowExit ?? this.allowExit,
    pricingSport: pricingSport ?? this.pricingSport,
    pricingOfferingId: clearPricingOffering
        ? null
        : pricingOfferingId ?? this.pricingOfferingId,
  );
  @override
  List<Object?> get props => [
    ...super.props,
    localDraftStatus,
    localDraftMessage,
    businessId,
    draft,
    version,
    step,
    editMode,
    settingsOverview,
    editingReady,
    dirty,
    saving,
    formError,
    allowExit,
    pricingSport,
    pricingOfferingId,
  ];
}
