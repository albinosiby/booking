import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../bookings/cubit/booking_form_cubit.dart'
    show bookingScope, bookingError;
import '../../workspace/repositories/workspace_session.dart';
import '../models/slot_block_models.dart';
import '../repositories/slot_block_repository.dart';

abstract class BlockCubit<S> extends Cubit<S> {
  BlockCubit(this.session, this.repository, S initialState)
    : super(initialState) {
    scope = bookingScope(session);
    subscription = session.snapshots.listen((_) {
      if (scope != bookingScope(session)) {
        generation++;
        resetAccess();
      }
    });
  }
  final WorkspaceSession session;
  final SlotBlockRepository repository;
  late String scope;
  late StreamSubscription subscription;
  int generation = 0;
  bool get authorized => scope == bookingScope(session);
  bool current(int g) => !isClosed && authorized && g == generation;
  void resetAccess();
  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}

class BlockListCubit extends BlockCubit<BlockListModel> {
  BlockListCubit(
    WorkspaceSession session,
    SlotBlockRepository repository,
    this.launch,
  ) : super(session, repository, BlockListModel()) {
    changes = repository.changes.listen((_) {
      if (!isClosed && !state.loading && !state.locked) unawaited(load());
    });
  }
  final BlockLaunch launch;
  late StreamSubscription changes;
  @override
  void resetAccess() =>
      emit(BlockListModel(error: 'Your access changed. Reopen this page.'));
  Future<void> load({bool more = false}) async {
    if (!authorized || state.locked || more && state.next == null) return;
    final g = ++generation, previous = state;
    emit(state.copy(loading: true));
    try {
      final catalog = await repository.catalog();
      if (!catalog.canManage) {
        throw const AppException(
          'Booking management permission is required.',
          code: 'FORBIDDEN',
        );
      }
      final id = state.businessId ?? launch.businessId;
      final b =
          catalog.businesses.where((b) => b.id == id).firstOrNull ??
          catalog.businesses.firstOrNull;
      if (b == null) {
        if (current(g)) emit(BlockListModel(catalog: catalog));
        return;
      }
      final date = state.date.isNotEmpty ? state.date : launch.date ?? b.today;
      final page = await repository.list(
        b.id,
        date,
        cursor: more ? previous.next! : 0,
      );
      if (current(g)) {
        emit(
          BlockListModel(
            catalog: catalog,
            businessId: b.id,
            date: date,
            blocks: [if (more) ...previous.blocks, ...page.items],
            next: page.next,
          ),
        );
      }
    } catch (e) {
      if (current(g)) {
        emit(
          accessFailure(e)
              ? BlockListModel(error: bookingError(e))
              : state.copy(loading: false, error: bookingError(e)),
        );
      }
    }
  }

  void business(String id) {
    if (state.locked || state.businessId == id) return;
    emit(state.copy(businessId: id, blocks: [], clearNext: true));
    load();
  }

  void date(String value) {
    if (state.locked || state.date == value) return;
    emit(state.copy(date: value, blocks: [], clearNext: true));
    load();
  }

  Future<void> unblock(SlotBlock block) async {
    if (!authorized || state.locked || !block.canUnblock) return;
    final g = ++generation;
    emit(state.copy(busyId: block.id));
    try {
      await repository.unblock(block.id);
      if (current(g)) {
        emit(state.copy(clearBusy: true));
        await load();
      }
    } catch (e) {
      if (current(g)) {
        emit(
          accessFailure(e)
              ? BlockListModel(error: bookingError(e))
              : state.copy(clearBusy: true, error: bookingError(e)),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    await changes.cancel();
    return super.close();
  }
}

class BlockFormCubit extends BlockCubit<BlockFormModel> {
  BlockFormCubit(
    WorkspaceSession session,
    SlotBlockRepository repository,
    this.launch,
  ) : super(session, repository, BlockFormModel());
  final BlockLaunch launch;
  @override
  void resetAccess() =>
      emit(BlockFormModel(error: 'Your access changed. Reopen this page.'));
  Future<void> load() async {
    final g = ++generation;
    if (!authorized) return;
    emit(state.copy(loading: true));
    try {
      final catalog = await repository.catalog();
      if (!catalog.canManage) {
        throw const AppException(
          'Booking management permission is required.',
          code: 'FORBIDDEN',
        );
      }
      final b =
          catalog.businesses
              .where((b) => b.id == launch.businessId)
              .firstOrNull ??
          catalog.businesses.firstOrNull;
      final date = b == null
          ? ''
          : launch.date != null && launch.date!.compareTo(b.today) >= 0
          ? launch.date!
          : b.today;
      if (current(g)) {
        emit(
          BlockFormModel(
            catalog: catalog,
            businessId: b?.id,
            date: date,
            spaces: [
              if (b?.spaces.any((s) => s.id == launch.spaceId) == true)
                launch.spaceId!,
            ],
          ),
        );
        await loadSlots();
      }
    } catch (e) {
      if (current(g)) {
        emit(
          accessFailure(e)
              ? BlockFormModel(error: bookingError(e))
              : state.copy(loading: false, error: bookingError(e)),
        );
      }
    }
  }

  void business(String id) {
    if (state.locked) return;
    final b = state.catalog.businesses.where((b) => b.id == id).firstOrNull;
    if (b != null) {
      emit(
        state.copy(
          businessId: id,
          spaces: [],
          review: false,
          date: state.date.compareTo(b.today) < 0 ? b.today : state.date,
        ),
      );
      loadSlots();
    }
  }

  void space(String id) {
    if (state.locked || state.business?.spaces.any((s) => s.id == id) != true) {
      return;
    }
    final ids = {...state.spaces};
    if (!ids.add(id)) ids.remove(id);
    emit(state.copy(spaces: ids, review: false));
    loadSlots();
  }

  void allSpaces() {
    if (state.locked) return;
    emit(
      state.copy(
        spaces: state.business?.spaces.map((s) => s.id) ?? [],
        review: false,
      ),
    );
    loadSlots();
  }

  void clearSpaces() {
    if (state.locked) return;
    emit(state.copy(spaces: [], review: false));
    loadSlots();
  }

  void date(String v) {
    if (state.locked || state.date == v) return;
    emit(
      state.copy(date: v, review: false, ranges: const [], clearAnchor: true),
    );
    loadSlots();
  }

  void allDay(bool v) {
    if (!state.locked) emit(state.copy(allDay: v, review: false));
  }

  void time(String v, {required bool start}) {
    if (state.locked || !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(v)) {
      return;
    }
    emit(
      state.copy(
        start: start ? v : null,
        end: start ? null : v,
        review: false,
        custom: true,
        ranges: const [],
        clearAnchor: true,
      ),
    );
  }

  /// Leaves exact times and returns to picking half hours on the grid.
  void useGrid() {
    if (!state.locked && state.custom) {
      emit(state.copy(custom: false, review: false));
    }
  }

  /// Tiles are clock times, as on New booking: tap where a block starts,
  /// then where it ends (09:00 then 10:00 blocks 9 to 10). Tapping a chosen
  /// range's start or a time inside it removes that range; tapping the
  /// pending start again cancels it. Several ranges become separate blocks.
  void pick(BlockSlot slot) {
    final s = state, t = slot.time;
    if (s.locked) return;
    BlockFormModel next;
    if (s.anchor != null) {
      if (t == s.anchor) {
        next = s.copy(clearAnchor: true);
      } else if (s.canEnd(t)) {
        next = s.copy(
          ranges: [...s.ranges, BlockPeriod(s.anchor!, t)],
          clearAnchor: true,
        );
      } else if (slot.open && s.rangeAt(t) == null) {
        next = s.copy(anchor: t);
      } else {
        return;
      }
    } else {
      final hit = s.rangeAt(t);
      if (hit != null) {
        next = s.copy(ranges: s.ranges.where((r) => r != hit));
      } else if (slot.open) {
        next = s.copy(anchor: t);
      } else {
        return;
      }
    }
    final periods = next.periods;
    emit(
      next.copy(
        custom: false,
        review: false,
        start: periods.firstOrNull?.start,
        end: periods.lastOrNull?.end,
      ),
    );
  }

  void clearPicked() {
    if (!state.locked) {
      emit(state.copy(ranges: const [], clearAnchor: true, review: false));
    }
  }

  int slotGeneration = 0;
  Future<void> loadSlots() async {
    final s = state, b = s.business;
    final g = ++slotGeneration;
    if (!authorized || b == null || s.spaces.isEmpty || s.date.isEmpty) {
      emit(
        s.copy(
          slots: [],
          slotsLoading: false,
          clearSlotsError: true,
          ranges: const [],
          clearAnchor: true,
          error: s.error,
        ),
      );
      return;
    }
    emit(s.copy(slotsLoading: true, clearSlotsError: true, error: s.error));
    try {
      final r = await repository.slots(b.id, s.date, s.spaces);
      if (isClosed || !authorized || g != slotGeneration) return;
      final fresh = state.copy(slots: r.slots, slotStep: r.step);
      bool free(BlockPeriod p) =>
          fresh.copy(anchor: p.start, ranges: const []).canEnd(p.end);
      final anchor = fresh.anchor;
      emit(
        fresh.copy(
          slotsLoading: false,
          ranges: fresh.ranges.where(free),
          clearAnchor:
              anchor != null &&
              r.slots.where((x) => x.time == anchor).firstOrNull?.open != true,
          error: state.error,
        ),
      );
    } catch (e) {
      if (isClosed || !authorized || g != slotGeneration) return;
      emit(
        state.copy(
          slotsLoading: false,
          slotsError: bookingError(e),
          error: state.error,
        ),
      );
    }
  }

  void edit() {
    if (!state.locked) emit(state.copy(review: false));
  }

  Future<void> submit() async {
    if (!authorized || state.saving || state.savedId != null) return;
    if (state.pending.isEmpty) {
      final error = state.validation;
      if (error != null) {
        emit(state.copy(error: error));
        return;
      }
      if (!state.review) {
        emit(state.copy(review: true));
        return;
      }
    }
    final requests = state.pending.isNotEmpty
        ? state.pending
        : [
            for (final p in state.periods)
              BlockRequest(
                key: const Uuid().v4(),
                businessId: state.businessId!,
                spaces: state.spaces,
                date: state.date,
                allDay: state.allDay,
                start: p.start,
                end: p.end,
              ),
          ];
    final g = generation;
    emit(state.copy(saving: true, pending: requests));
    final saved = <BlockRequest>[], failed = <(BlockRequest, Object)>[];
    String? id;
    for (var i = 0; i < requests.length; i++) {
      final request = requests[i];
      try {
        id = await repository.create(request);
        saved.add(request);
      } catch (e) {
        if (!current(g)) return;
        if (accessFailure(e)) {
          emit(BlockFormModel(error: bookingError(e)));
          return;
        }
        final uncertain =
            e is! AppException ||
            ![
              'VALIDATION_ERROR',
              'CONFLICT',
              'FORBIDDEN',
              'UNAUTHENTICATED',
              'REQUEST_ERROR',
            ].contains(e.code);
        if (uncertain) {
          emit(
            state.copy(
              saving: false,
              pending: requests.sublist(i),
              error: saved.isEmpty
                  ? 'Could not confirm the block. Retry to verify the same request.'
                  : '${_hours(saved)} blocked. Could not confirm the rest. Retry to verify the same request.',
            ),
          );
          return;
        }
        failed.add((request, e));
      }
    }
    if (!current(g)) return;
    if (failed.isEmpty) {
      emit(state.copy(saving: false, clearPending: true, savedId: id));
      return;
    }
    final done = {for (final r in saved) (r.start, r.end)};
    final keep = state.ranges.where(
      (p) => !done.contains((p.start, p.end == '24:00' ? '00:00' : p.end)),
    );
    emit(
      state.copy(
        saving: false,
        clearPending: true,
        review: saved.isEmpty && state.review,
        ranges: keep,
        error: [
          if (saved.isNotEmpty) '${_hours(saved)} blocked.',
          for (final (r, e) in failed)
            '${requests.length > 1 && !r.allDay ? '${_hours([r])}: ' : ''}${bookingError(e)}',
        ].join(' '),
      ),
    );
    unawaited(loadSlots());
  }

  static String _hours(List<BlockRequest> requests) => requests
      .map((r) => r.allDay ? 'Entire day' : BlockPeriod(r.start, r.end).label)
      .join(', ');
}
