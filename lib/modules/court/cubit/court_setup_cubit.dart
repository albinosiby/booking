import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../../core/state/configuration_setup_cubit.dart';
import '../../configuration_drafts/models/configuration_draft.dart';
import '../../configuration_drafts/repositories/configuration_draft_repository.dart';
import '../../workspace/models/workspace_state.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/court_configuration.dart';
import '../models/court_setup_state.dart';
import '../models/court_screen_models.dart';
import '../repositories/court_repository.dart';

class CourtSetupCubit extends ConfigurationSetupCubit<CourtSetupState> {
  CourtSetupCubit(
    WorkspaceSession session,
    this.repository,
    String id, {
    ConfigurationDraftRepository? drafts,
  }) : super(session, (s) => CourtSetupState.initial(s, id)) {
    initializeLocalDraft(drafts, id);
  }
  final CourtRepository repository;
  @override
  bool get hasDraftChanges => state.dirty;
  @override
  int get draftBaseVersion => state.version;
  @override
  ConfigurationDraft captureLocalDraft() => ConfigurationDraft(
    baseVersion: state.version,
    configuration: state.draft.toJson(localDraft: true),
    navigation: {
      'section': state.section.name,
      'selected': state.selectedId,
      'resource_flow': state.resourceFlow,
    },
  );
  @override
  void restoreLocalDraft(ConfigurationDraft draft) {
    if (draft.configuration['kind'] != 'court_v1') {
      throw const FormatException('Invalid draft kind');
    }
    final restored = CourtConfiguration.fromJson(
      draft.configuration,
    ).restrictPricingDays();
    emit(
      state.copyWith(
        draft: restored,
        version: draft.baseVersion,
        dirty: true,
        section:
            CourtSection.values
                .where((s) => s.name == draft.navigation['section'])
                .firstOrNull ??
            CourtSection.overview,
        selectedId: draft.navigation['selected'] as String?,
        resourceFlow: draft.navigation['resource_flow'] == true,
      ),
    );
  }

  @override
  void setLocalDraftStatus(LocalDraftStatus status, String? message) {
    if (!isClosed) {
      emit(
        state.copyWith(
          localDraftStatus: status,
          localDraftMessage: message,
          formError: state.formError,
        ),
      );
    }
  }

  @override
  CourtSetupState mapSnapshot(WorkspaceState snapshot) =>
      state.copyWith(snapshot: snapshot, formError: state.formError);
  void _edit(CourtConfiguration draft) {
    if (state.disabled || !state.data.isOwner) return;
    emit(
      state.copyWith(
        draft: draft.followOpeningTimes(state.draft).restrictPricingDays(),
        dirty: true,
      ),
    );
  }

  void open(CourtSection section, {String? id, bool resourceFlow = false}) {
    if (state.disabled) return;
    emit(
      state.copyWith(
        section: section,
        selectedId: id,
        clearSelection: id == null,
        allowExit: false,
        resourceFlow: resourceFlow,
      ),
    );
  }

  void back() {
    if (state.disabled) return;
    if (state.resourceFlow && state.section == CourtSection.pricing) {
      open(CourtSection.courts, id: state.selectedId, resourceFlow: true);
      return;
    }
    open(
      state.resourceFlow
          ? CourtSection.courts
          : state.selectedId != null
          ? state.section
          : CourtSection.overview,
    );
  }

  void allowExit() => emit(state.copyWith(allowExit: true));
  void addCourt() {
    if (state.disabled || state.draft.courts.length >= 50) return;
    var number = state.draft.courts.length + 1;
    while (state.draft.courts.any((p) => p.name == 'Court $number')) {
      number++;
    }
    final p = CourtResource(id: const Uuid().v4(), name: 'Court $number');
    _edit(state.draft.copyWith(courts: [...state.draft.courts, p]));
    open(CourtSection.courts, id: p.id, resourceFlow: true);
  }

  void continueResource() {
    if (state.disabled || !state.data.isOwner) return;
    final resource = state.selectedCourt;
    if (resource == null) return;
    final duplicate = state.draft.courts.any(
      (p) =>
          p.id != resource.id &&
          p.name.trim().toLowerCase() == resource.name.trim().toLowerCase(),
    );
    final error =
        resource.validateDetails(complete: true) ??
        (duplicate ? 'Give each court a unique name.' : null);
    if (error != null) {
      emit(state.copyWith(formError: error));
      return;
    }
    open(CourtSection.pricing, id: resource.id, resourceFlow: true);
  }

  Future<bool> finishResource({bool addAnother = false}) async {
    if (state.disabled || !state.data.isOwner) return false;
    final resource = state.selectedCourt;
    if (resource == null) return false;
    final error = CourtConfiguration(
      courts: [resource],
    ).validate(complete: resource.enabled);
    if (error != null) {
      emit(state.copyWith(formError: error));
      return false;
    }
    checkpointLocalDraft();
    open(CourtSection.courts);
    if (addAnother) addCourt();
    return true;
  }

  void updateCourt(String id, CourtResource Function(CourtResource) update) =>
      _edit(
        state.draft.copyWith(
          courts: state.draft.courts.map((p) => p.id == id ? update(p) : p),
        ),
      );
  void removeCourt(String id) {
    if (state.disabled) return;
    _edit(
      state.draft.copyWith(courts: state.draft.courts.where((p) => p.id != id)),
    );
    open(CourtSection.courts);
  }

  void duration(String id, int minutes, bool selected) => updateCourt(id, (p) {
    final sorted = [minutes];
    return p.copyWith(
      durations: sorted,
      defaultDuration: minutes,
      tariffs: p.tariffs.map(
        (t) => t.copyWith(
          rates: sorted.map(
            (d) =>
                t.rates.where((r) => r.minutes == d).firstOrNull ??
                CourtRate(d, ''),
          ),
        ),
      ),
    );
  });
  void addTariff(String id) => updateCourt(
    id,
    (p) => p.tariffs.length >= 40
        ? p
        : p.copyWith(
            tariffs: [
              ...p.tariffs,
              CourtTariff(
                id: const Uuid().v4(),
                hours: p.hours,
                rates: p.durations.map((d) => CourtRate(d, '')),
              ),
            ],
          ),
  );
  void removeTariff(String courtId, String tariffId) => updateCourt(
    courtId,
    (p) => p.copyWith(tariffs: p.tariffs.where((t) => t.id != tariffId)),
  );
  void tariffHours(String courtId, String tariffId, CourtHours hours) =>
      updateCourt(
        courtId,
        (p) => p.copyWith(
          tariffs: p.tariffs.map(
            (t) => t.id == tariffId ? t.copyWith(hours: hours) : t,
          ),
        ),
      );
  void tariffPrice(
    String courtId,
    String tariffId,
    int minutes,
    String value,
  ) => updateCourt(
    courtId,
    (p) => p.copyWith(
      tariffs: p.tariffs.map(
        (t) => t.id == tariffId
            ? t.copyWith(
                rates: t.rates.map(
                  (r) => r.minutes == minutes ? CourtRate(minutes, value) : r,
                ),
              )
            : t,
      ),
    ),
  );
  void copyPricing(String id, Iterable<String> targetIds) {
    final source = state.draft.courts.firstWhere((p) => p.id == id);
    _edit(
      state.draft.copyWith(
        courts: state.draft.courts.map(
          (p) => p.id != id && targetIds.contains(p.id)
              ? p.copyWith(
                  hours: source.hours,
                  durations: source.durations,
                  defaultDuration: source.defaultDuration,
                  before: source.before,
                  after: source.after,
                  tariffs: source.tariffs.map(
                    (t) => t.copyWith(id: const Uuid().v4()),
                  ),
                )
              : p,
        ),
      ),
    );
  }

  bool _same(Map<String, dynamic>? config, CourtConfiguration draft) =>
      config?['kind'] == 'court_v1' &&
      jsonEncode(CourtConfiguration.fromJson(config!).toJson()) ==
          jsonEncode(draft.toJson());
  Future<bool> _persist() async {
    final draft = state.draft;
    final ok = await save(
      () => repository.save(state.businessId, state.version, draft),
    );
    if (isClosed) return false;
    final b = session.state.data.businesses
        .where((b) => b.id == state.businessId)
        .firstOrNull;
    final committed = ok || _same(b?.configuration, draft);
    if (committed && b?.configuration?['kind'] == 'court_v1') {
      emit(
        state.copyWith(
          snapshot: session.state,
          version: b!.version,
          draft: CourtConfiguration.fromJson(b.configuration!),
          dirty: false,
        ),
      );
    }
    return committed;
  }

  Future<bool> _activate() async {
    if (state.dirty || state.business?.configuration?['kind'] != 'court_v1') {
      if (!await _persist() || isClosed) return false;
    }
    final alreadyReady =
        session.state.data.businesses
            .where((b) => b.id == state.businessId)
            .firstOrNull
            ?.ready ==
        true;
    final ok =
        alreadyReady || await save(() => repository.activate(state.businessId));
    if (isClosed) return false;
    final b = session.state.data.businesses
        .where((b) => b.id == state.businessId)
        .firstOrNull;
    final committed =
        ok || (b?.ready == true && _same(b?.configuration, state.draft));
    if (committed && b != null) {
      emit(
        state.copyWith(
          snapshot: session.state,
          version: b.version,
          draft: CourtConfiguration.fromJson(b.configuration!),
          editingReady: true,
          dirty: false,
        ),
      );
    }
    return committed;
  }

  Future<bool> _run(
    Future<bool> Function() operation, {
    required bool complete,
  }) async {
    if (state.disabled || !state.data.isOwner) return false;
    if (localDraftConflict) {
      emit(
        state.copyWith(
          formError:
              'Newer settings exist online. Reload saved settings before saving this draft.',
        ),
      );
      return false;
    }
    final error = state.draft.validate(complete: complete);
    if (error != null) {
      emit(state.copyWith(formError: error));
      return false;
    }
    emit(state.copyWith(saving: true));
    try {
      await flushLocalDraft(force: true);
      final ok = await operation();
      if (ok) {
        await clearLocalDraft();
      } else {
        await flushLocalDraft(force: true);
      }
      return ok;
    } finally {
      if (!isClosed) {
        emit(
          state.copyWith(
            snapshot: session.state,
            saving: false,
            formError: state.formError,
          ),
        );
      }
    }
  }

  Future<bool> saveChanges() async {
    final active = state.editingReady || state.business?.ready == true;
    if (active && !state.editingReady) emit(state.copyWith(editingReady: true));
    final ok = await _run(active ? _activate : _persist, complete: active);
    if (ok && !isClosed) {
      emit(state.copyWith(clearSelection: true, resourceFlow: false));
    }
    return ok;
  }

  Future<bool> activate() => _run(_activate, complete: true);
  Future<void> reloadSaved() async {
    if (state.disabled) return;
    await session.load();
    if (isClosed || session.state.status != LoadStatus.ready) return;
    final b = session.state.data.businesses
        .where((b) => b.id == state.businessId)
        .firstOrNull;
    if (b != null) {
      await clearLocalDraft();
      emit(
        state.copyWith(
          snapshot: session.state,
          draft: CourtConfiguration.initial(b),
          version: b.version,
          dirty: false,
          clearSelection: true,
          resourceFlow: false,
          editingReady: b.ready,
        ),
      );
    }
  }
}
