import 'dart:convert';
import 'package:uuid/uuid.dart';
import '../../../core/state/configuration_setup_cubit.dart';
import '../../configuration_drafts/models/configuration_draft.dart';
import '../../configuration_drafts/repositories/configuration_draft_repository.dart';
import '../../workspace/models/workspace_state.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/hall_configuration.dart';
import '../models/hall_setup_state.dart';
import '../models/hall_screen_models.dart';
import '../repositories/hall_repository.dart';

class HallSetupCubit extends ConfigurationSetupCubit<HallSetupState> {
  HallSetupCubit(
    WorkspaceSession session,
    this.repository,
    String id, {
    ConfigurationDraftRepository? drafts,
  }) : super(session, (s) => HallSetupState.initial(s, id)) {
    initializeLocalDraft(drafts, id);
  }
  final HallRepository repository;
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
      'option': state.selectedOption,
    },
  );
  @override
  void restoreLocalDraft(ConfigurationDraft draft) {
    if (draft.configuration['kind'] != 'hall_v1') {
      throw const FormatException('Invalid draft kind');
    }
    final restored = HallConfiguration.fromJson(
      draft.configuration,
    ).restrictPricingDays();
    emit(
      state.copyWith(
        draft: restored,
        version: draft.baseVersion,
        dirty: true,
        section:
            HallSection.values
                .where((s) => s.name == draft.navigation['section'])
                .firstOrNull ??
            HallSection.overview,
        selectedId: draft.navigation['selected'] as String?,
        selectedOption: draft.navigation['option'] as String?,
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
  HallSetupState mapSnapshot(WorkspaceState snapshot) =>
      state.copyWith(snapshot: snapshot, formError: state.formError);
  void _edit(HallConfiguration draft) {
    if (state.disabled || !state.data.isOwner) return;
    emit(
      state.copyWith(
        draft: draft.followOpeningTimes(state.draft).restrictPricingDays(),
        dirty: true,
      ),
    );
  }

  void open(HallSection section, {String? id}) {
    if (state.disabled) return;
    emit(
      state.copyWith(
        section: section,
        selectedId: id,
        clearSelection: id == null,
        allowExit: false,
        clearOption: true,
      ),
    );
  }

  void back() {
    if (state.disabled) return;
    if (state.selectedOption != null) {
      emit(state.copyWith(clearOption: true));
      return;
    }
    open(state.selectedId != null ? state.section : HallSection.overview);
  }

  void continueSection() {
    if (state.disabled) return;
    open(state.selectedId != null ? state.section : HallSection.overview);
    checkpointLocalDraft();
  }

  void allowExit() => emit(state.copyWith(allowExit: true));
  void addHall() {
    if (state.disabled || state.draft.halls.length >= 50) return;
    var number = state.draft.halls.length + 1;
    while (state.draft.halls.any((p) => p.name == 'Hall $number')) {
      number++;
    }
    final p = HallResource(id: const Uuid().v4(), name: 'Hall $number');
    _edit(state.draft.copyWith(halls: [...state.draft.halls, p]));
    open(HallSection.halls, id: p.id);
  }

  void updateHall(String id, HallResource Function(HallResource) update) =>
      _edit(
        state.draft.copyWith(
          halls: state.draft.halls.map((p) => p.id == id ? update(p) : p),
        ),
      );
  void removeHall(String id) {
    if (state.disabled) return;
    _edit(
      state.draft.copyWith(halls: state.draft.halls.where((p) => p.id != id)),
    );
    open(HallSection.halls);
  }

  void duration(String id, int minutes, bool selected) => updateHall(id, (p) {
    final sorted = [minutes];
    return p.copyWith(
      durations: sorted,
      defaultDuration: minutes,
      tariffs: p.tariffs.map(
        (t) => t.copyWith(
          rates: sorted.map(
            (d) =>
                t.rates.where((r) => r.minutes == d).firstOrNull ??
                HallRate(d, ''),
          ),
        ),
      ),
    );
  });
  void addTariff(String id) => updateHall(
    id,
    (p) => p.tariffs.length >= 40
        ? p
        : p.copyWith(
            tariffs: [
              ...p.tariffs,
              HallTariff(
                id: const Uuid().v4(),
                hours: p.hours,
                rates: p.durations.map((d) => HallRate(d, '')),
              ),
            ],
          ),
  );
  void removeTariff(String hallId, String tariffId) => updateHall(
    hallId,
    (p) => p.copyWith(tariffs: p.tariffs.where((t) => t.id != tariffId)),
  );
  void tariffHours(String hallId, String tariffId, HallHours hours) =>
      updateHall(
        hallId,
        (p) => p.copyWith(
          tariffs: p.tariffs.map(
            (t) => t.id == tariffId ? t.copyWith(hours: hours) : t,
          ),
        ),
      );
  void tariffPrice(String hallId, String tariffId, int minutes, String value) =>
      updateHall(
        hallId,
        (p) => p.copyWith(
          tariffs: p.tariffs.map(
            (t) => t.id == tariffId
                ? t.copyWith(
                    rates: t.rates.map(
                      (r) =>
                          r.minutes == minutes ? HallRate(minutes, value) : r,
                    ),
                  )
                : t,
          ),
        ),
      );
  void copyPricing(String id, Iterable<String> targetIds) {
    final source = state.draft.halls.firstWhere((p) => p.id == id);
    _edit(
      state.draft.copyWith(
        halls: state.draft.halls.map(
          (p) => p.id != id && targetIds.contains(p.id)
              ? p.copyWith(
                  hourlyEnabled: source.hourlyEnabled,
                  sessions: source.sessions.map(_clonePackage),
                  fullDay: _clonePackage(source.fullDay),
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

  HallPackage _clonePackage(HallPackage o) => o.copyWith(
    id: const Uuid().v4(),
    prices: o.prices.map((r) => r.copyWith(id: const Uuid().v4())),
  );
  void selectOption(String option) {
    if (!state.disabled) emit(state.copyWith(selectedOption: option));
  }

  void updatePackage(
    String hallId,
    String optionId,
    HallPackage Function(HallPackage) change,
  ) => updateHall(
    hallId,
    (p) => p.copyWith(
      sessions: p.sessions.map((s) => s.id == optionId ? change(s) : s),
      fullDay: p.fullDay.id == optionId ? change(p.fullDay) : p.fullDay,
    ),
  );
  void enablePackage(String hallId, String optionId, bool enabled) =>
      updatePackage(
        hallId,
        optionId,
        (o) => o.copyWith(
          enabled: enabled,
          prices: enabled && o.prices.isEmpty
              ? [HallPackagePrice(id: const Uuid().v4(), days: o.hours.days)]
              : o.prices,
        ),
      );
  void addSession(String hallId) {
    final p = state.draft.halls.firstWhere((p) => p.id == hallId);
    if (p.sessions.length >= 12) return;
    var n = p.sessions.length + 1;
    while (p.sessions.any((s) => s.name.toLowerCase() == 'session $n')) {
      n++;
    }
    final o = HallPackage(
      id: const Uuid().v4(),
      name: 'Session $n',
      hours: p.hours,
    );
    updateHall(hallId, (p) => p.copyWith(sessions: [...p.sessions, o]));
    selectOption(o.id);
  }

  void removeSession(String hallId, String optionId) {
    updateHall(
      hallId,
      (p) => p.copyWith(sessions: p.sessions.where((s) => s.id != optionId)),
    );
    if (!state.disabled) emit(state.copyWith(clearOption: true));
  }

  void addPackagePrice(String hallId, String optionId) => updatePackage(
    hallId,
    optionId,
    (o) => o.prices.length >= 40
        ? o
        : o.copyWith(
            prices: [
              ...o.prices,
              HallPackagePrice(id: const Uuid().v4(), days: o.hours.days),
            ],
          ),
  );
  void updatePackagePrice(
    String hallId,
    String optionId,
    String priceId,
    HallPackagePrice Function(HallPackagePrice) change,
  ) => updatePackage(
    hallId,
    optionId,
    (o) => o.copyWith(
      prices: o.prices.map((r) => r.id == priceId ? change(r) : r),
    ),
  );
  void removePackagePrice(String hallId, String optionId, String priceId) =>
      updatePackage(
        hallId,
        optionId,
        (o) => o.copyWith(prices: o.prices.where((r) => r.id != priceId)),
      );
  bool _same(Map<String, dynamic>? config, HallConfiguration draft) =>
      config?['kind'] == 'hall_v1' &&
      jsonEncode(HallConfiguration.fromJson(config!).toJson()) ==
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
    if (committed && b?.configuration?['kind'] == 'hall_v1') {
      emit(
        state.copyWith(
          snapshot: session.state,
          version: b!.version,
          draft: HallConfiguration.fromJson(b.configuration!),
          dirty: false,
        ),
      );
    }
    return committed;
  }

  Future<bool> _activate() async {
    if (state.dirty || state.business?.configuration?['kind'] != 'hall_v1') {
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
          draft: HallConfiguration.fromJson(b.configuration!),
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
    if (ok && !isClosed) emit(state.copyWith(clearSelection: true));
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
          draft: HallConfiguration.initial(b),
          version: b.version,
          dirty: false,
          clearSelection: true,
          editingReady: b.ready,
        ),
      );
    }
  }
}
