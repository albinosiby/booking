import 'dart:convert';
import 'dart:math' as math;
import 'package:uuid/uuid.dart';
import '../../../core/state/configuration_setup_cubit.dart';
import '../../configuration_drafts/models/configuration_draft.dart';
import '../../configuration_drafts/repositories/configuration_draft_repository.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/models/workspace_state.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/pool_configuration.dart';
import '../models/pool_setup_state.dart';
import '../models/pool_screen_models.dart';
import '../repositories/pool_repository.dart';

class PoolSetupCubit extends ConfigurationSetupCubit<PoolSetupState> {
  PoolSetupCubit(
    WorkspaceSession session,
    this.repository,
    String id, {
    ConfigurationDraftRepository? drafts,
  }) : super(session, (s) => PoolSetupState.initial(s, id)) {
    initializeLocalDraft(drafts, id);
  }
  final PoolRepository repository;
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
    if (draft.configuration['kind'] != 'pool_v1') {
      throw const FormatException('Invalid draft kind');
    }
    final restored = PoolConfiguration.fromJson(
      draft.configuration,
    ).restrictPricingDays();
    emit(
      state.copyWith(
        draft: restored,
        version: draft.baseVersion,
        dirty: true,
        section:
            PoolSection.values
                .where((s) => s.name == draft.navigation['section'])
                .firstOrNull ??
            PoolSection.overview,
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
  PoolSetupState mapSnapshot(WorkspaceState snapshot) =>
      state.copyWith(snapshot: snapshot, formError: state.formError);
  void _edit(PoolConfiguration draft) {
    if (state.disabled || !state.data.isOwner) return;
    emit(
      state.copyWith(
        draft: draft.followOpeningTimes(state.draft).restrictPricingDays(),
        dirty: true,
      ),
    );
  }

  void open(PoolSection section, {String? id, bool resourceFlow = false}) {
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
    if (state.resourceFlow && state.section == PoolSection.pricing) {
      open(PoolSection.pools, id: state.selectedId, resourceFlow: true);
      return;
    }
    open(
      state.resourceFlow
          ? PoolSection.pools
          : state.selectedId != null
          ? state.section
          : PoolSection.overview,
    );
  }

  void allowExit() => emit(state.copyWith(allowExit: true));
  Future<void> loadCoaches() async {
    if (state.coachesLoading || !state.data.isOwner) return;
    emit(state.copyWith(coachesLoading: true, clearCoachError: true));
    try {
      final coaches = await repository.loadCoaches(state.businessId);
      if (!isClosed) {
        emit(state.copyWith(coaches: coaches, coachesLoading: false));
      }
    } catch (e) {
      if (!isClosed) {
        emit(
          state.copyWith(
            coachesLoading: false,
            coachError: e is AppException
                ? e.message
                : 'Could not load coaches. Retry or assign later.',
          ),
        );
      }
    }
  }

  void addPool() {
    if (state.disabled || state.draft.pools.length >= 30) return;
    var number = state.draft.pools.length + 1;
    while (state.draft.pools.any((p) => p.name == 'Pool $number')) {
      number++;
    }
    final p = PoolResource(id: const Uuid().v4(), name: 'Pool $number');
    _edit(state.draft.copyWith(pools: [...state.draft.pools, p]));
    open(PoolSection.pools, id: p.id, resourceFlow: true);
  }

  void continueResource() {
    if (state.disabled || !state.data.isOwner) return;
    final resource = state.selectedPool;
    if (resource == null) return;
    final duplicate = state.draft.pools.any(
      (p) =>
          p.id != resource.id &&
          p.name.trim().toLowerCase() == resource.name.trim().toLowerCase(),
    );
    final error =
        resource.validateDetails(complete: true) ??
        (duplicate ? 'Give each pool a unique name.' : null);
    if (error != null) {
      emit(state.copyWith(formError: error));
      return;
    }
    open(PoolSection.pricing, id: resource.id, resourceFlow: true);
  }

  Future<bool> finishResource({bool addAnother = false}) async {
    if (state.disabled || !state.data.isOwner) return false;
    final resource = state.selectedPool;
    if (resource == null) return false;
    final error = PoolConfiguration(
      pools: [resource],
    ).validate(complete: resource.enabled, requireProducts: false);
    if (error != null) {
      emit(state.copyWith(formError: error));
      return false;
    }
    checkpointLocalDraft();
    open(PoolSection.pools);
    if (addAnother) addPool();
    return true;
  }

  void updatePool(String id, PoolResource Function(PoolResource) update) =>
      _edit(
        state.draft.copyWith(
          pools: state.draft.pools.map((p) => p.id == id ? update(p) : p),
        ),
      );
  void removePool(String id) {
    if (state.disabled) return;
    _edit(
      state.draft.copyWith(
        pools: state.draft.pools.where((p) => p.id != id),
        coaches: state.draft.coaches.map(
          (c) => c.withPools(c.poolIds.where((p) => p != id)),
        ),
        offers: state.draft.offers.map(
          (o) => o.copyWith(
            poolIds: o.poolIds.where((p) => p != id),
            enabled: o.enabled && o.poolIds.any((p) => p != id),
          ),
        ),
        // A plan left without pools also loses its coach.
        plans: state.draft.plans.map(
          (p) => p.copyWith(
            poolIds: p.poolIds.where((x) => x != id),
            enabled: p.enabled && p.poolIds.any((x) => x != id),
            clearCoach: !p.poolIds.any((x) => x != id),
          ),
        ),
      ),
    );
    open(PoolSection.pools);
  }

  void duration(String id, int minutes, bool selected) => updatePool(id, (p) {
    final sorted = [minutes];
    return p.copyWith(
      durations: sorted,
      defaultDuration: minutes,
      tariffs: p.tariffs.map(
        (t) => t.copyWith(
          rates: sorted.map(
            (d) =>
                t.rates.where((r) => r.minutes == d).firstOrNull ??
                PoolRate(d, ''),
          ),
        ),
      ),
    );
  });
  void addTariff(String id) => updatePool(
    id,
    (p) => p.tariffs.length >= 40
        ? p
        : p.copyWith(
            tariffs: [
              ...p.tariffs,
              PoolTariff(
                id: const Uuid().v4(),
                hours: p.hours,
                rates: p.durations.map((d) => PoolRate(d, '')),
              ),
            ],
          ),
  );
  void removeTariff(String poolId, String tariffId) => updatePool(
    poolId,
    (p) => p.copyWith(tariffs: p.tariffs.where((t) => t.id != tariffId)),
  );
  void tariffHours(String poolId, String tariffId, PoolHours hours) =>
      updatePool(
        poolId,
        (p) => p.copyWith(
          tariffs: p.tariffs.map(
            (t) => t.id == tariffId ? t.copyWith(hours: hours) : t,
          ),
        ),
      );
  void tariffPrice(String poolId, String tariffId, int minutes, String value) =>
      updatePool(
        poolId,
        (p) => p.copyWith(
          tariffs: p.tariffs.map(
            (t) => t.id == tariffId
                ? t.copyWith(
                    rates: t.rates.map(
                      (r) =>
                          r.minutes == minutes ? PoolRate(minutes, value) : r,
                    ),
                  )
                : t,
          ),
        ),
      );
  void copyPricing(String id, Iterable<String> targetIds) {
    final source = state.draft.pools.firstWhere((p) => p.id == id);
    _edit(
      state.draft.copyWith(
        pools: state.draft.pools.map(
          (p) => p.id != id && targetIds.contains(p.id)
              ? p.copyWith(
                  hours: source.hours,
                  durations: source.durations,
                  defaultDuration: source.defaultDuration,
                  before: source.before,
                  after: source.after,
                  regularSwimming: source.regularSwimming,
                  tariffs: source.tariffs.map(
                    (t) => t.copyWith(id: const Uuid().v4()),
                  ),
                )
              : p,
        ),
      ),
    );
  }

  PoolResource? get _first =>
      state.draft.pools.where((p) => p.enabled).firstOrNull;
  void addOffer() {
    if (state.disabled || _first == null || state.draft.offers.length >= 50) {
      return;
    }
    final p = _first!;
    final offer = PoolGroupOffer(
      id: const Uuid().v4(),
      poolIds: [p.id],
      people: '${math.min(15, int.tryParse(p.capacity) ?? 15)}',
      hours: p.hours,
    );
    _edit(state.draft.copyWith(offers: [...state.draft.offers, offer]));
    open(PoolSection.groups, id: offer.id);
  }

  void updateOffer(String id, PoolGroupOffer Function(PoolGroupOffer) update) =>
      _edit(
        state.draft.copyWith(
          offers: state.draft.offers.map((o) => o.id == id ? update(o) : o),
        ),
      );
  void removeOffer(String id) {
    _edit(
      state.draft.copyWith(offers: state.draft.offers.where((o) => o.id != id)),
    );
    open(PoolSection.groups);
  }

  void addPlan(bool coaching) {
    if (state.disabled || _first == null || state.draft.plans.length >= 50) {
      return;
    }
    final p = _first!;
    final plan = PoolPlan(
      id: const Uuid().v4(),
      kind: coaching ? 'coaching' : 'swimming',
      name: coaching ? 'Coaching plan' : 'Swimming plan',
      poolIds: [p.id],
      hours: p.hours,
      seats: '${math.min(10, int.tryParse(p.capacity) ?? 10)}',
    );
    _edit(state.draft.copyWith(plans: [...state.draft.plans, plan]));
    open(coaching ? PoolSection.coaching : PoolSection.plans, id: plan.id);
  }

  void updatePlan(String id, PoolPlan Function(PoolPlan) update) => _edit(
    state.draft.copyWith(
      plans: state.draft.plans.map((p) => p.id == id ? update(p) : p),
    ),
  );
  void removePlan(String id) {
    final coaching = state.draft.plans.firstWhere((p) => p.id == id).coaching;
    _edit(
      state.draft.copyWith(plans: state.draft.plans.where((p) => p.id != id)),
    );
    open(coaching ? PoolSection.coaching : PoolSection.plans);
  }

  bool _same(Map<String, dynamic>? config, PoolConfiguration draft) =>
      config?['kind'] == 'pool_v1' &&
      jsonEncode(PoolConfiguration.fromJson(config!).toJson()) ==
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
    if (committed && b?.configuration?['kind'] == 'pool_v1') {
      emit(
        state.copyWith(
          snapshot: session.state,
          version: b!.version,
          draft: PoolConfiguration.fromJson(b.configuration!),
          dirty: false,
        ),
      );
    }
    return committed;
  }

  Future<bool> _activate() async {
    if (state.dirty || state.business?.configuration?['kind'] != 'pool_v1') {
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
          draft: PoolConfiguration.fromJson(b.configuration!),
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
          draft: PoolConfiguration.initial(b),
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
