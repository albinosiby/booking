import 'package:uuid/uuid.dart';
import 'dart:convert';
import '../../../core/state/configuration_setup_cubit.dart';
import '../../configuration_drafts/models/configuration_draft.dart';
import '../../configuration_drafts/repositories/configuration_draft_repository.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../workspace/models/workspace_state.dart';
import '../models/turf_configuration.dart';
import '../models/turf_setup_state.dart';
import '../repositories/turf_repository.dart';

class TurfSetupCubit extends ConfigurationSetupCubit<TurfSetupState> {
  TurfSetupCubit(
    WorkspaceSession session,
    this.repository,
    String id, {
    ConfigurationDraftRepository? drafts,
  }) : super(session, (snapshot) => TurfSetupState.initial(snapshot, id)) {
    initializeLocalDraft(drafts, id);
  }
  final TurfRepository repository;
  @override
  bool get hasDraftChanges => state.dirty;
  @override
  int get draftBaseVersion => state.version;
  @override
  ConfigurationDraft captureLocalDraft() => ConfigurationDraft(
    baseVersion: state.version,
    configuration: state.draft.toJson(localDraft: true),
    navigation: {
      'step': state.step,
      'edit_mode': state.editMode,
      'settings_overview': state.settingsOverview,
      'sport': state.pricingSport?.name,
      'offering': state.pricingOfferingId,
    },
  );
  @override
  void restoreLocalDraft(ConfigurationDraft draft) {
    if (draft.configuration['kind'] != 'turf_v1') {
      throw const FormatException('Invalid draft kind');
    }
    final restored = TurfConfiguration.fromJson(
      draft.configuration,
    ).restrictPricingDays().synchronizeCricket();
    emit(
      state.copyWith(
        draft: restored,
        version: draft.baseVersion,
        dirty: true,
        settingsOverview: draft.navigation['edit_mode'] == state.editMode
            ? draft.navigation['settings_overview'] == true
            : state.settingsOverview,
        step: (draft.navigation['step'] as int? ?? 0).clamp(0, 5),
        pricingSport: TurfSport.values
            .where((s) => s.name == draft.navigation['sport'])
            .firstOrNull,
        pricingOfferingId: draft.navigation['offering'] as String?,
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

  bool _working = false;
  @override
  TurfSetupState mapSnapshot(WorkspaceState snapshot) =>
      state.copyWith(snapshot: snapshot, formError: state.formError);
  void _edit(TurfConfiguration draft) {
    if (state.disabled) return;
    emit(
      state.copyWith(
        draft: draft
            .followOpeningTimes(state.draft)
            .restrictPricingDays()
            .synchronizeCricket(),
        dirty: true,
      ),
    );
  }

  void beginEditing() {
    if (state.disabled) return;
    emit(
      state.copyWith(
        editMode: true,
        settingsOverview: true,
        editingReady: state.business?.ready ?? false,
      ),
    );
  }

  void openSettingsSection(int section) {
    if (!state.editMode || state.disabled || section < 0 || section > 5) return;
    emit(
      state.copyWith(
        step: section,
        settingsOverview: false,
        clearPricingOffering: true,
        allowExit: false,
      ),
    );
  }

  void showSettingsOverview() {
    if (!state.editMode || state.disabled) return;
    emit(
      state.copyWith(
        settingsOverview: true,
        clearPricingOffering: true,
        formError: state.formError,
      ),
    );
  }

  Future<bool> saveSettings() async {
    if (!state.editMode || state.disabled) return false;
    final pricingDetail = state.step == 4 && state.pricingOfferingId != null;
    if (state.business?.ready == true && !state.editingReady) {
      emit(state.copyWith(editingReady: true));
    }
    final ok = state.editingReady ? await activate() : await saveProgress();
    if (!ok || isClosed) return false;
    emit(
      state.copyWith(
        settingsOverview: !pricingDetail,
        clearPricingOffering: true,
      ),
    );
    return true;
  }

  void useFootballForCricket(bool value) {
    if (state.disabled) return;
    if (value && !state.draft.footballPricingComplete) {
      emit(
        state.copyWith(
          formError:
              'Complete Football timing and pricing for every matching space first.',
        ),
      );
      return;
    }
    _edit(state.draft.copyWith(cricketUsesFootball: value));
  }

  void sport(TurfSport sport, bool enabled) {
    final sports = {...state.draft.sports};
    enabled ? sports.add(sport) : sports.remove(sport);
    _edit(
      state.draft.copyWith(
        sports: TurfSport.values.where(sports.contains),
        offerings: state.draft.offerings.map(
          (o) => o.sport == sport ? o.copyWith(enabled: enabled) : o,
        ),
      ),
    );
  }

  void groundName(String id, String name) => _edit(
    state.draft.copyWith(
      grounds: state.draft.grounds.map(
        (g) => g.id == id ? g.withName(name) : g,
      ),
    ),
  );
  void addGround() {
    if (state.draft.grounds.length >= 10) return;
    var number = state.draft.grounds.length + 1;
    while (state.draft.grounds.any(
      (ground) => ground.name == 'Ground $number',
    )) {
      number++;
    }
    _edit(state.draft.addGround('Ground $number', TurfArrangement.single));
  }

  TurfConfiguration _removeGround(String id) {
    final layoutIds = state.draft.layouts
        .where((l) => l.groundId == id)
        .map((l) => l.id)
        .toSet();
    return state.draft.copyWith(
      grounds: state.draft.grounds.where((g) => g.id != id),
      layouts: state.draft.layouts.where((l) => l.groundId != id),
      offerings: state.draft.offerings.where(
        (o) => !layoutIds.contains(o.layoutId),
      ),
    );
  }

  void removeGround(String id) {
    if (state.draft.grounds.length == 1) return;
    _edit(_removeGround(id));
  }

  void arrangement(String id, TurfArrangement arrangement) {
    final ground = state.draft.grounds.firstWhere((g) => g.id == id);
    if (ground.arrangement == arrangement) return;
    _edit(_removeGround(id).addGround(ground.name, arrangement, groundId: id));
  }

  void spaceName(String id, String name) => _edit(
    state.draft.copyWith(
      layouts: state.draft.layouts.map(
        (l) => l.id == id ? l.withName(name) : l,
      ),
    ),
  );
  void offering(String id, {String? name, String? format, bool? enabled}) =>
      _edit(
        state.draft.copyWith(
          offerings: state.draft.offerings.map(
            (o) => o.id == id
                ? o.copyWith(name: name, format: format, enabled: enabled)
                : o,
          ),
        ),
      );
  void hours(TurfHours value) => _edit(state.draft.copyWith(operating: value));
  void _offer(String id, TurfOffering Function(TurfOffering) update) {
    final target = state.draft.offerings.firstWhere((o) => o.id == id);
    if (state.draft.cricketUsesFootball && target.sport == TurfSport.cricket) {
      return;
    }
    _edit(
      state.draft.copyWith(
        offerings: state.draft.offerings.map((o) => o.id == id ? update(o) : o),
      ),
    );
  }

  void overrideHours(String id, TurfHours? value) => _offer(
    id,
    (o) => o.copyWith(hoursOverride: value, clearOverride: value == null),
  );
  void offeringHours(String id, TurfHours value) {
    if (state.disabled || !state.data.isOwner) return;
    final target = state.draft.offerings.firstWhere((o) => o.id == id);
    if (state.draft.cricketUsesFootball && target.sport == TurfSport.cricket) {
      return;
    }
    final previous = state.draft.operating;
    final extendShared = value.allDay && !previous.allDay;
    final sharedDays = {...previous.days};
    if (extendShared) {
      for (final offer in state.draft.offerings) {
        final h = offer.hoursOverride ?? previous;
        if (!h.allDay &&
            turfMinute(h.closes) < turfMinute(h.opens) &&
            turfMinute(h.closes) > 0) {
          sharedDays.addAll(h.days.map((d) => d % 7 + 1));
        }
      }
    }
    _edit(
      state.draft.copyWith(
        operating: extendShared
            ? previous.copyWith(
                allDay: true,
                opens: '00:00',
                closes: '00:00',
                days: sharedDays,
              )
            : previous,
        offerings: state.draft.offerings.map((o) {
          if (o.id == id) return o.copyWith(hoursOverride: value);
          if (extendShared && o.hoursOverride == null) {
            return o.copyWith(hoursOverride: previous);
          }
          return o;
        }),
      ),
    );
  }

  void buffers(String id, {int? before, int? after}) =>
      _offer(id, (o) => o.copyWith(bufferBefore: before, bufferAfter: after));
  void price(String id, int minutes, String value) => _offer(id, (offer) {
    final hours = offer.hoursOverride ?? state.draft.operating;
    final bands = offer.pricingRules.isEmpty
        ? [
            TurfPriceBand(
              id: const Uuid().v4(),
              days: hours.days,
              opens: hours.opens,
              closes: hours.closes,
              allDay: hours.allDay,
              rates: offer.rates,
            ),
          ]
        : offer.pricingRules;
    return offer.copyWith(
      rates: offer.rates.map(
        (r) => r.minutes == minutes ? TurfRate(minutes, value) : r,
      ),
      pricingRules: bands.map(
        (b) => b.copyWith(
          rates: b.rates.map(
            (r) => r.minutes == minutes ? TurfRate(minutes, value) : r,
          ),
        ),
      ),
    );
  });
  void duration(String id, int minutes, bool enabled) => _offer(id, (offer) {
    final rates = [
      offer.rates.where((r) => r.minutes == minutes).firstOrNull ??
          TurfRate(minutes, ''),
    ];
    return offer.copyWith(
      rates: rates,
      defaultDuration: minutes,
      pricingRules: offer.pricingRules.map(
        (band) => band.copyWith(
          rates: rates.map(
            (rate) =>
                band.rates
                    .where((r) => r.minutes == rate.minutes)
                    .firstOrNull ??
                TurfRate(rate.minutes, ''),
          ),
        ),
      ),
    );
  });
  void defaultDuration(String id, int value) =>
      _offer(id, (offer) => offer.copyWith(defaultDuration: value));
  void selectPricingSport(TurfSport sport) {
    if (state.disabled) return;
    emit(state.copyWith(pricingSport: sport, clearPricingOffering: true));
  }

  void selectPricingOffering(String id) {
    if (state.disabled) return;
    final offer = state.draft.offerings.firstWhere((o) => o.id == id);
    if (state.draft.cricketUsesFootball && offer.sport == TurfSport.cricket) {
      return;
    }
    emit(state.copyWith(pricingSport: offer.sport, pricingOfferingId: id));
  }

  void pricingSpaces() {
    if (state.disabled) return;
    emit(state.copyWith(clearPricingOffering: true));
  }

  void addPriceBand(String id) => _offer(id, (offer) {
    if (offer.pricingRules.length >= 40) return offer;
    final hours = offer.hoursOverride ?? state.draft.operating;
    return offer.copyWith(
      pricingRules: [
        ...offer.pricingRules,
        TurfPriceBand(
          id: const Uuid().v4(),
          days: hours.days,
          opens: hours.opens,
          closes: hours.closes,
          allDay: hours.allDay,
          rates: offer.rates.map((r) => TurfRate(r.minutes, '')),
        ),
      ],
    );
  });
  void removePriceBand(String id, String bandId) => _offer(
    id,
    (offer) => offer.copyWith(
      pricingRules: offer.pricingRules.where((b) => b.id != bandId),
    ),
  );
  void priceBand(
    String id,
    String bandId, {
    Iterable<int>? days,
    String? opens,
    String? closes,
    bool? allDay,
  }) => _offer(
    id,
    (offer) => offer.copyWith(
      pricingRules: offer.pricingRules.map(
        (b) => b.id == bandId
            ? b.copyWith(
                days: days,
                opens: opens,
                closes: closes,
                allDay: allDay,
              )
            : b,
      ),
    ),
  );
  void extendClosingForBand(String offerId, String bandId) {
    if (state.disabled || !state.data.isOwner) return;
    final offer = state.draft.offerings
        .where((o) => o.id == offerId)
        .firstOrNull;
    if (offer == null ||
        (state.draft.cricketUsesFootball && offer.sport == TurfSport.cricket)) {
      return;
    }
    final band = offer.pricingRules.where((b) => b.id == bandId).firstOrNull;
    if (band == null) return;
    final operating = state.draft.operating;
    final change = turfClosingExtension(
      operating,
      offer.hoursOverride ?? operating,
      band.hours,
    );
    if (change == null) return;
    _edit(
      state.draft.copyWith(
        operating: change.operating,
        offerings: state.draft.offerings.map((other) {
          if (other.id == offerId) {
            return other.copyWith(hoursOverride: change.offering);
          }
          // Retain the existing hours of spaces that previously inherited shared hours.
          if (change.operating != operating && other.hoursOverride == null) {
            return other.copyWith(hoursOverride: operating);
          }
          return other;
        }),
      ),
    );
  }

  void bandPrice(String id, String bandId, int minutes, String value) => _offer(
    id,
    (offer) => offer.copyWith(
      pricingRules: offer.pricingRules.map(
        (b) => b.id == bandId
            ? b.copyWith(
                rates: b.rates.map(
                  (r) => r.minutes == minutes ? TurfRate(minutes, value) : r,
                ),
              )
            : b,
      ),
    ),
  );
  bool canCopyHalf(String id) {
    final offer = state.draft.offerings.firstWhere((o) => o.id == id);
    final layout = state.draft.layouts.firstWhere(
      (l) => l.id == offer.layoutId,
    );
    final ground = state.draft.grounds.firstWhere(
      (g) => g.id == layout.groundId,
    );
    return ground.arrangement == TurfArrangement.split &&
        layout.sectionIds.length == 1;
  }

  void copyToOtherHalf(String id) {
    if (!canCopyHalf(id)) return;
    if (state.draft.cricketUsesFootball &&
        state.draft.offerings.firstWhere((o) => o.id == id).sport ==
            TurfSport.cricket) {
      return;
    }
    final offer = state.draft.offerings.firstWhere((o) => o.id == id);
    final layout = state.draft.layouts.firstWhere(
      (l) => l.id == offer.layoutId,
    );
    final other = state.draft.layouts.firstWhere(
      (l) =>
          l.groundId == layout.groundId &&
          l.id != layout.id &&
          l.sectionIds.length == 1,
    );
    _edit(
      state.draft.copyWith(
        offerings: state.draft.offerings.map(
          (o) => o.layoutId == other.id && o.sport == offer.sport
              ? o.copyWith(
                  rates: offer.rates,
                  defaultDuration: offer.defaultDuration,
                  pricingRules: offer.pricingRules.map(
                    (band) => band.copyWith(id: const Uuid().v4()),
                  ),
                  bufferBefore: offer.bufferBefore,
                  bufferAfter: offer.bufferAfter,
                  hoursOverride: offer.hoursOverride,
                  clearOverride: offer.hoursOverride == null,
                )
              : o,
        ),
      ),
    );
  }

  void step(int value) {
    if (state.disabled || value < 0 || value > 5) return;
    if (value > state.step) {
      String? error;
      if (state.step == 0 && state.draft.sports.isEmpty) {
        error = 'Select at least one sport.';
      }
      if (state.step == 3 &&
          state.draft.layouts.any(
            (l) => !state.draft.offerings.any(
              (o) => o.layoutId == l.id && o.enabled,
            ),
          )) {
        error = 'Enable at least one sport for each space.';
      }
      error ??= state.draft.validate(complete: state.step == 4);
      if (error != null) {
        emit(state.copyWith(formError: error));
        return;
      }
    }
    emit(state.copyWith(step: value));
  }

  void allowExit() => emit(state.copyWith(allowExit: true));
  void restoreSaved() {
    if (state.disabled) return;
    final business = session.state.data.businesses
        .where((b) => b.id == state.businessId)
        .firstOrNull;
    if (business == null) return;
    emit(
      state.copyWith(
        snapshot: session.state,
        draft: TurfConfiguration.initial(business),
        version: business.version,
        dirty: false,
      ),
    );
  }

  Future<void> refreshSaved() async {
    if (state.disabled) return;
    await session.load();
    if (!isClosed && session.state.status == LoadStatus.ready) {
      await clearLocalDraft();
      restoreSaved();
    }
  }

  Future<bool> _persist() async {
    final draft = state.draft;
    final ok = await save(
      () => repository.save(state.businessId, state.version, draft),
    );
    if (isClosed) return false;
    final business = session.state.data.businesses
        .where((b) => b.id == state.businessId)
        .firstOrNull;
    // JSONB changes map-key ordering; compare canonical typed serialization.
    if (business?.configuration?['kind'] == 'turf_v1') {
      final persisted = TurfConfiguration.fromJson(business!.configuration!);
      if (ok || jsonEncode(persisted.toJson()) == jsonEncode(draft.toJson())) {
        emit(
          state.copyWith(
            snapshot: session.state,
            version: business.version,
            draft: persisted,
            dirty: false,
          ),
        );
      }
    }
    return ok;
  }

  Future<bool> _run(
    Future<bool> Function() action, {
    required bool complete,
  }) async {
    if (_working || state.disabled || !state.data.isOwner) return false;
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
    _working = true;
    emit(state.copyWith(saving: true));
    try {
      await flushLocalDraft(force: true);
      final ok = await action();
      if (ok) {
        await clearLocalDraft();
      } else {
        await flushLocalDraft(force: true);
      }
      return ok;
    } finally {
      _working = false;
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

  Future<bool> continueSetup() async {
    if (state.disabled) return false;
    if (state.step == 4 && state.pricingOfferingId != null) {
      final offer = state.draft.offerings.firstWhere(
        (o) => o.id == state.pricingOfferingId,
      );
      final error = validateTurfOffering(
        offer,
        state.draft.operating,
        complete: true,
      );
      if (error != null) {
        emit(state.copyWith(formError: error));
        return false;
      }
      emit(state.copyWith(clearPricingOffering: true));
      checkpointLocalDraft();
      return true;
    }
    final target = state.step + 1;
    step(target);
    if (state.step != target) return false;
    emit(state.copyWith(dirty: true));
    checkpointLocalDraft();
    return true;
  }

  Future<bool> saveProgress() => _run(_persist, complete: false);
  Future<bool> saveDraft() => saveProgress();
  Future<bool> activate() => _run(() async {
    if (state.dirty || state.business?.configuration?['kind'] != 'turf_v1') {
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
    // Session writes finish before the async screen snapshot reaches this Cubit.
    final business = session.state.data.businesses
        .where((b) => b.id == state.businessId)
        .firstOrNull;
    final recovered =
        business?.ready == true &&
        business?.configuration?['kind'] == 'turf_v1' &&
        jsonEncode(
              TurfConfiguration.fromJson(business!.configuration!).toJson(),
            ) ==
            jsonEncode(state.draft.toJson());
    final committed = ok || recovered;
    if (committed) {
      emit(
        state.copyWith(
          snapshot: session.state,
          version: business?.version ?? state.version,
          editingReady: state.editMode || state.editingReady,
        ),
      );
    }
    return committed;
  }, complete: true);
}
