import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../workspace/models/workspace_access.dart';
import '../../bookings/models/booking_models.dart';
import '../models/admission_models.dart';
import '../models/admission_overview.dart';
import '../repositories/admission_repository.dart';
import 'admission_state.dart';

String admissionError(Object e) => e is AppException
    ? e.message
    : 'Could not complete this action. Please try again.';

class AdmissionCubit extends Cubit<AdmissionState> {
  AdmissionCubit(this.session, this.repository)
    : super(const AdmissionState()) {
    scope = workspaceAccessScope(session.state.data);
    readSubscription = repository.changes.listen((_) {
      if (!authorized || (!_listing && _detailView == null)) return;
      _readPending = true;
      _refreshRetainedRead();
    });
    subscription = session.snapshots.listen((_) {
      if (scope != workspaceAccessScope(session.state.data)) {
        generation++;
        pending = null;
        _overviewSelections.clear();
        emit(
          const AdmissionState(error: 'Your access changed. Reopen this page.'),
        );
      }
    });
  }
  final WorkspaceSession session;
  final AdmissionRepository repository;
  late final StreamSubscription readSubscription;
  bool _listing = false, _readPending = false, _overview = false;
  final Map<bool, (String?, String?)> _overviewSelections = {};
  String? _detailView;
  Timer? _readTimer;
  void _refreshRetainedRead() {
    if (!_readPending ||
        !authorized ||
        state.loading ||
        state.busy ||
        state.locked) {
      return;
    }
    _readPending = false;
    _readTimer?.cancel();
    _readTimer = Timer(const Duration(milliseconds: 30), () {
      if (!authorized) return;
      if (_detailView != null) {
        loadDetail(_detailView!);
      } else if (_overview) {
        loadOverview();
      } else if (_listing) {
        loadList();
      }
    });
  }

  late final String scope;
  late final StreamSubscription subscription;
  int generation = 0;
  int customerGeneration = 0;
  Timer? customerTimer;
  String key = const Uuid().v4();
  Future<void> Function()? pending;
  bool get authorized =>
      !isClosed &&
      scope == workspaceAccessScope(session.state.data) &&
      session.state.data.organization != null;
  bool valid(int g) => authorized && generation == g;

  AdmissionBusiness? get overviewBusiness => state.catalog.businesses
      .where((b) => b.id == state.overview.businessId)
      .firstOrNull;
  AdmissionPool? get overviewSpace => overviewBusiness?.pools
      .where((p) => p.id == state.overview.spaceId)
      .firstOrNull;
  String get overviewKind => state.overview.coaching
      ? 'coaching'
      : overviewBusiness?.court == true
      ? 'play'
      : 'swimming';

  Future<void> loadOverview({bool refreshCatalog = true}) async {
    if (!authorized || state.busy) return;
    _listing = true;
    _overview = true;
    _detailView = null;
    final g = ++generation;
    emit(state.copyWith(loading: true));
    try {
      final catalog = refreshCatalog
          ? await repository.catalog()
          : state.catalog;
      if (!valid(g)) return;
      final old = state.overview;
      final business =
          catalog.businesses.where((b) => b.id == old.businessId).firstOrNull ??
          catalog.businesses.firstOrNull;
      final space =
          business?.pools.where((p) => p.id == old.spaceId).firstOrNull ??
          business?.pools.firstOrNull;
      final plans =
          business?.plans
              .where(
                (p) =>
                    p.poolIds.contains(space?.id) &&
                    p.matchesKind(old.coaching ? 'coaching' : 'plans'),
              )
              .toList() ??
          [];
      final sameScope =
          old.businessId == business?.id && old.spaceId == space?.id;
      final groups = <String, AdmissionRoster>{
        for (final p in plans)
          p.id: AdmissionRoster(
            id: p.id,
            plan: p,
            items: sameScope ? old.rosters[p.id]?.items ?? [] : [],
            loading: true,
          ),
        if (space != null)
          'previous-plans': AdmissionRoster(
            id: 'previous-plans',
            items: sameScope ? old.rosters['previous-plans']?.items ?? [] : [],
            loading: true,
          ),
      };
      emit(
        state.copyWith(
          catalog: catalog,
          loading: false,
          overview: AdmissionOverview(
            coaching: old.coaching,
            businessId: business?.id,
            spaceId: space?.id,
            query: old.query,
            status: old.status,
            rosters: Map.unmodifiable(groups),
          ),
        ),
      );
      // Bound parallel requests for businesses with many plans.
      final ids = groups.keys.toList();
      for (var i = 0; i < ids.length && valid(g); i += 4) {
        await Future.wait(ids.skip(i).take(4).map((id) => _fetchRoster(id, g)));
      }
    } catch (e) {
      if (valid(g)) _overviewFailure(e);
    } finally {
      _refreshRetainedRead();
    }
  }

  void selectOverview({
    bool? coaching,
    String? businessId,
    String? spaceId,
    String? query,
    String? status,
    bool clearStatus = false,
  }) {
    if (!authorized || state.busy) return;
    final old = state.overview;
    if (coaching != null && coaching != old.coaching) {
      _overviewSelections[old.coaching] = (old.businessId, old.spaceId);
      final selection = _overviewSelections[coaching];
      businessId = selection?.$1 ?? old.businessId;
      spaceId = selection?.$2 ?? old.spaceId;
    }
    final changedBusiness = businessId != null && businessId != old.businessId;
    emit(
      state.copyWith(
        overview: old.copyWith(
          coaching: coaching,
          businessId: businessId,
          spaceId: spaceId,
          clearSpace: changedBusiness && spaceId == null,
          query: query,
          status: status,
          clearStatus: clearStatus,
          rosters: const {},
        ),
      ),
    );
    loadOverview(refreshCatalog: state.catalog.businesses.isEmpty);
  }

  Future<void> loadRoster(String id, {bool more = false}) async {
    final roster = state.overview.rosters[id];
    if (!authorized ||
        state.loading ||
        roster == null ||
        roster.loading ||
        (more && roster.next == null)) {
      return;
    }
    _putRoster(roster.copyWith(loading: true));
    await _fetchRoster(id, generation, more: more);
  }

  Future<void> loadMoreStudents() async {
    if (!authorized ||
        state.loading ||
        state.overview.rosters.values.any((r) => r.loading)) {
      return;
    }
    final g = generation;
    final ids = state.overview.rosters.values
        .where((r) => r.next != null)
        .map((r) => r.id)
        .toList();
    for (var i = 0; i < ids.length && valid(g); i += 4) {
      await Future.wait(
        ids.skip(i).take(4).map((id) => loadRoster(id, more: true)),
      );
    }
  }

  void _putRoster(AdmissionRoster roster) => emit(
    state.copyWith(
      overview: state.overview.copyWith(
        rosters: {...state.overview.rosters, roster.id: roster},
      ),
    ),
  );

  Future<void> _fetchRoster(String id, int g, {bool more = false}) async {
    final roster = state.overview.rosters[id];
    if (!valid(g) || roster == null) return;
    final selection = state.overview;
    try {
      final page = await repository.list(
        kind: overviewKind,
        query: selection.query,
        status: selection.status,
        businessId: selection.businessId,
        spaceId: selection.spaceId,
        planId: roster.plan?.id,
        previousPlans: roster.plan == null,
        cursor: more ? roster.next ?? 0 : 0,
      );
      if (!valid(g)) return;
      final byId = {
        for (final a in [
          ...(more ? roster.items : <Admission>[]),
          ...page.items,
        ])
          a.id: a,
      };
      _putRoster(
        roster.copyWith(
          items: List.unmodifiable(byId.values),
          next: page.next,
          clearNext: page.next == null,
          loading: false,
        ),
      );
    } catch (e) {
      if (!valid(g)) return;
      if (accessFailure(e)) {
        _overviewFailure(e);
      } else {
        _putRoster(roster.copyWith(loading: false, error: admissionError(e)));
      }
    }
  }

  void _overviewFailure(Object e) {
    if (accessFailure(e)) {
      generation++;
      _overviewSelections.clear();
      emit(const AdmissionState(error: 'Access denied. Reopen this page.'));
    } else {
      emit(state.copyWith(loading: false, error: admissionError(e)));
    }
  }

  Future<void> loadList({bool more = false}) async {
    if (!authorized || state.loading || state.busy) return;
    _listing = true;
    _overview = false;
    _detailView = null;
    final g = ++generation, old = state;
    emit(state.copyWith(loading: true));
    try {
      final results = await Future.wait<Object>([
        repository.catalog(),
        repository.list(
          query: old.query,
          kind: old.kind,
          status: old.status,
          cursor: more ? old.next ?? 0 : 0,
        ),
      ]);
      final catalog = results[0] as AdmissionCatalog,
          page = results[1] as AdmissionPage;
      if (valid(g)) {
        emit(
          state.copyWith(
            catalog: catalog,
            items: List.unmodifiable(
              more ? [...old.items, ...page.items] : page.items,
            ),
            next: page.next,
            clearNext: page.next == null,
            loading: false,
          ),
        );
      }
    } catch (e) {
      if (valid(g)) {
        emit(
          accessFailure(e)
              ? const AdmissionState(error: 'Access denied. Reopen this page.')
              : state.copyWith(loading: false, error: admissionError(e)),
        );
      }
    } finally {
      _refreshRetainedRead();
    }
  }

  void filter({
    String? kind,
    String? query,
    String? status,
    bool clearStatus = false,
  }) {
    if (state.busy) return;
    generation++;
    emit(
      state.copyWith(
        kind: kind,
        query: query,
        status: status,
        clearStatus: clearStatus,
        items: const [],
        clearNext: true,
        loading: false,
      ),
    );
    loadList();
  }

  Future<void> loadDetail(String id) async {
    if (!authorized || state.busy || state.locked) return;
    _listing = false;
    _detailView = id;
    final g = ++generation;
    emit(state.copyWith(loading: true));
    try {
      final results = await Future.wait<Object>([
        repository.catalog(),
        repository.detail(id),
      ]);
      final c = results[0] as AdmissionCatalog, a = results[1] as Admission;
      if (valid(g)) emit(state.copyWith(catalog: c, detail: a, loading: false));
    } catch (e) {
      if (valid(g)) {
        emit(
          accessFailure(e)
              ? const AdmissionState(error: 'Access denied. Reopen this page.')
              : state.copyWith(loading: false, error: admissionError(e)),
        );
      }
    } finally {
      _refreshRetainedRead();
    }
  }

  DateTime? catalogLoadedAt;
  AdmissionCatalog? get reusableCatalog =>
      authorized &&
          state.catalog.canManage &&
          catalogLoadedAt != null &&
          DateTime.now().difference(catalogLoadedAt!) <
              const Duration(seconds: 20)
      ? state.catalog
      : null;

  Future<void> loadForm({
    AdmissionCatalog? cachedCatalog,
    DateTime? cachedAt,
    String? renewalId,
    String? formKind,
    BookingCustomer? customer,
    bool strictLocation = false,
    String? businessId,
    String? poolId,
    String? planId,
    String? date,
  }) async {
    _listing = false;
    _detailView = null;
    _readPending = false;
    _readTimer?.cancel();
    final g = ++generation;
    emit(AdmissionState(loading: true, formKind: formKind));
    try {
      final c = cachedCatalog ?? await repository.catalog();
      catalogLoadedAt = cachedCatalog == null ? DateTime.now() : cachedAt;
      final a = renewalId == null ? null : await repository.detail(renewalId);
      if (!valid(g)) return;
      if (!c.canManage) {
        throw const AppException('Booking management permission is required.');
      }
      final b =
          c.businesses
              .where((b) => b.id == (a?.businessId ?? businessId))
              .firstOrNull ??
          (strictLocation ? null : c.businesses.firstOrNull);
      final chosen = b?.plans.where((p) => p.id == planId).firstOrNull;
      final p =
          b?.pools.where((p) => p.id == (a?.poolId ?? poolId)).firstOrNull ??
          b?.pools
              .where((p) => chosen?.poolIds.contains(p.id) == true)
              .firstOrNull ??
          (strictLocation ? null : b?.pools.firstOrNull);
      final plan = b?.plans
          .where(
            (plan) =>
                (a != null
                    ? plan.id == a.planId
                    : chosen != null
                    ? plan.id == chosen.id && plan.matchesKind(formKind)
                    : formKind != null && plan.matchesKind(formKind)) &&
                plan.poolIds.contains(p?.id),
          )
          .firstOrNull;
      final today = b?.today ?? '';
      final draft = AdmissionDraft(
        businessId: b?.id,
        poolId: p?.id,
        planId: plan?.id,
        customer: a?.customer ?? customer ?? const BookingCustomer(),
        mode: a?.mode ?? 'flexible',
        start: date != null && date.compareTo(today) >= 0 ? date : today,
        time: a?.time ?? '06:00',
        duration: plan?.duration ?? p?.defaultDuration ?? 60,
        weekdays: a?.weekdays ?? const [],
        renewedFrom: a?.id,
      );
      emit(state.copyWith(catalog: c, draft: draft, loading: false, detail: a));
    } catch (e) {
      if (valid(g)) {
        emit(
          accessFailure(e)
              ? const AdmissionState(error: 'Access denied. Reopen this page.')
              : state.copyWith(loading: false, error: admissionError(e)),
        );
      }
    }
  }

  void update(AdmissionDraft d) {
    if (authorized && !state.busy && !state.locked) {
      emit(state.copyWith(draft: d, clearPreview: true));
    }
  }

  void customerPhone(String value) {
    update(
      state.draft.copyWith(
        customer: state.draft.customer.copyWith(phone: value, clearId: true),
      ),
    );
    customerTimer?.cancel();
    final g = ++customerGeneration;
    emit(state.copyWith(customers: const []));
    if (value.replaceAll(RegExp(r'[^0-9]'), '').length < 3) return;
    customerTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final matches = await repository.customers(value);
        if (authorized && g == customerGeneration) {
          emit(state.copyWith(customers: matches));
        }
      } catch (e) {
        if (authorized && g == customerGeneration && accessFailure(e)) {
          emit(const AdmissionState(error: 'Access denied. Reopen this page.'));
        }
      }
    });
  }

  void chooseCustomer(BookingCustomer customer) {
    customerGeneration++;
    customerTimer?.cancel();
    update(state.draft.copyWith(customer: customer));
    emit(state.copyWith(customers: const []));
  }

  Future<void> sessionChange(
    AdmissionVisit visit,
    String action,
    String reason, {
    String? date,
    String? time,
  }) {
    final a = state.detail!, k = key;
    return mutate(
      () => repository.sessionChange(
        a,
        visit,
        action,
        reason,
        k,
        date: date,
        time: time,
      ),
    );
  }

  void business(String id) {
    final b = state.catalog.businesses.firstWhere((b) => b.id == id);
    final p = b.pools.firstOrNull;
    update(
      state.draft.copyWith(
        businessId: id,
        poolId: p?.id,
        start: b.today,
        resetPlan: true,
        duration: p?.defaultDuration,
      ),
    );
  }

  void pool(String id) {
    final p = state.business!.pools.firstWhere((p) => p.id == id);
    update(
      state.draft.copyWith(
        poolId: id,
        resetPlan: true,
        duration: p.defaultDuration,
      ),
    );
  }

  void plan(String id) {
    final p = state.availablePlans.where((p) => p.id == id).firstOrNull;
    if (p == null) return;
    update(
      state.draft.copyWith(
        planId: id,
        duration: p.duration ?? state.pool?.defaultDuration,
      ),
    );
  }

  void adjustVisitDuration(int steps) {
    if (state.loading ||
        state.busy ||
        state.locked ||
        !state.adjustableVisitDuration) {
      return;
    }
    final value = state.draft.duration + steps * 30;
    if (value < state.minimumVisitDuration || value > 1440) return;
    update(state.draft.copyWith(duration: value));
  }

  void addPayment() {
    if (!state.catalog.canCollect || state.draft.payments.length >= 20) return;
    update(
      state.draft.copyWith(
        payments: [...state.draft.payments, BookingPaymentDraft()],
      ),
    );
  }

  /// Starts an optional collection; [minor] prefills the amount when known.
  void startCollection([int? minor]) {
    if (!state.catalog.canCollect || state.draft.payments.isNotEmpty) return;
    update(
      state.draft.copyWith(
        payments: [
          BookingPaymentDraft(
            amount: minor == null ? '' : (minor / 100).toStringAsFixed(2),
          ),
        ],
      ),
    );
  }

  void payBalance(String id) {
    final amount = state.paymentEntry.balanceFor(id);
    if (amount != null && amount > 0) {
      paymentUpdate(
        id,
        (p) => p.copyWith(amount: (amount / 100).toStringAsFixed(2)),
      );
    }
  }

  void paymentUpdate(
    String id,
    BookingPaymentDraft Function(BookingPaymentDraft) change,
  ) => update(
    state.draft.copyWith(
      payments: List.unmodifiable(
        state.draft.payments.map((p) => p.id == id ? change(p) : p),
      ),
    ),
  );
  Future<void> review() async {
    if (state.busy || state.locked || !authorized) return;
    final d = state.draft;
    String? error = d.customer.validate();
    if (d.planId == null ||
        d.poolId == null ||
        !state.availablePlans.any((p) => p.id == d.planId)) {
      error = 'Choose a space and plan.';
    }
    if (!state.validVisitDuration) {
      error =
          'Use the configured minimum duration, then extend in 30-minute steps.';
    }
    if (d.mode == 'fixed' && d.weekdays.isEmpty) {
      error = 'Choose at least one weekday.';
    }
    for (final p in d.payments.where((p) => !p.isBlank)) {
      error ??= state.paymentEntry.errorFor(p);
    }
    if (!state.catalog.canCollect && state.paymentEntry.recorded.isNotEmpty) {
      error = 'Payment collection permission is required.';
    }
    if (d.payments.length > 20) error = 'Add at most 20 payment entries.';
    if (error != null) {
      emit(state.copyWith(error: error));
      return;
    }
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      final p = await repository.preview(d);
      if (valid(g)) {
        if (state.paymentEntry.received > p.total) {
          emit(
            state.copyWith(
              busy: false,
              clearPreview: true,
              error:
                  'Payments exceed the current plan amount. Adjust the payments and review again.',
            ),
          );
        } else {
          emit(state.copyWith(preview: p, busy: false));
        }
      }
    } catch (e) {
      if (valid(g)) {
        emit(
          accessFailure(e)
              ? const AdmissionState(error: 'Access denied. Reopen this page.')
              : state.copyWith(busy: false, error: admissionError(e)),
        );
      }
    }
  }

  void edit() {
    if (!state.busy && !state.locked) emit(state.copyWith(clearPreview: true));
  }

  Future<void> create() async {
    if (state.busy ||
        state.locked ||
        state.savedId != null ||
        state.preview == null ||
        !authorized) {
      return;
    }
    final d = state.draft, p = state.preview!;
    await mutate(() async {
      final id = await repository.create(d, p, key);
      if (authorized) emit(state.copyWith(savedId: id));
    }, reload: false);
  }

  Future<void> mutate(
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    if (state.busy || !authorized) return;
    pending ??= action;
    final g = ++generation;
    emit(state.copyWith(busy: true, locked: true));
    try {
      await pending!();
      if (!valid(g)) return;
      pending = null;
      key = const Uuid().v4();
      emit(state.copyWith(busy: false, locked: false));
      if (reload && state.detail != null) await loadDetail(state.detail!.id);
    } catch (e) {
      if (valid(g)) {
        if (accessFailure(e)) {
          pending = null;
          emit(const AdmissionState(error: 'Access denied. Reopen this page.'));
          return;
        }
        final definitive =
            e is AppException &&
            [
              'VALIDATION_ERROR',
              'REQUEST_ERROR',
              'CONFLICT',
              'FORBIDDEN',
              'UNAUTHENTICATED',
            ].contains(e.code);
        if (definitive) {
          pending = null;
          key = const Uuid().v4();
        }
        emit(
          state.copyWith(
            busy: false,
            locked: !definitive,
            clearPreview: definitive,
            error: admissionError(e),
          ),
        );
      }
    }
  }

  Future<void> retry() =>
      mutate(pending ?? () async {}, reload: state.savedId == null);
  Future<void> checkIn() async {
    if (!authorized || state.loading || state.busy || state.locked) return;
    final id = state.detail?.id;
    if (id == null) return;
    // Refresh permissions and the optimistic version before recording attendance.
    await loadDetail(id);
    if (!authorized || state.error != null || state.busy || state.locked) {
      return;
    }
    final a = state.detail;
    if (a == null ||
        a.id != id ||
        !a.canCheckIn ||
        !a.canMarkAttendance ||
        !state.catalog.canAttend) {
      return;
    }
    final k = key;
    // Keep this exact command for retries; the server owns time selection.
    await mutate(() => repository.checkIn(a, k));
  }

  Future<void> attendance(AdmissionVisit v, String value, String reason) {
    final a = state.detail!, k = key;
    return mutate(() => repository.attendance(a, v, value, reason, k));
  }

  Future<void> collect(
    List<BookingPaymentDraft> payments,
    String kind,
    String reason,
  ) {
    final a = state.detail!, k = key;
    return mutate(() => repository.payments(a, payments, kind, reason, k));
  }

  Future<void> cancel(String reason) {
    final a = state.detail!, k = key;
    return mutate(() => repository.cancel(a, reason, k));
  }

  @override
  Future<void> close() async {
    generation++;
    customerGeneration++;
    customerTimer?.cancel();
    _readTimer?.cancel();
    final readCancellation = readSubscription.cancel();
    final cancellation = subscription.cancel();
    final closing = super.close();
    await Future.wait([cancellation, readCancellation, closing]);
  }
}
