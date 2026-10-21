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
    emit(state.copy(date: v, review: false, clearRange: true));
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
        clearRange: true,
      ),
    );
  }

  /// Leaves exact times and returns to picking half hours on the grid.
  void useGrid() {
    if (!state.locked && state.custom) {
      emit(state.copy(custom: false, review: false));
    }
  }

  static bool _open(List<BlockSlot> slots, String from, String until) =>
      slots.any((s) => s.time == from) &&
      slots
          .where(
            (s) => s.time.compareTo(from) >= 0 && s.time.compareTo(until) <= 0,
          )
          .every((s) => s.open);

  /// First tap marks the start, a later tap the last half hour; tapping the
  /// start again clears the selection.
  void pick(BlockSlot slot) {
    final s = state, t = slot.time;
    if (s.locked || !slot.open) return;
    if (s.hasRange && t == s.from) {
      emit(s.copy(clearRange: true, review: false));
      return;
    }
    final extend =
        s.hasRange && t.compareTo(s.from!) > 0 && _open(s.slots, s.from!, t);
    final from = extend ? s.from! : t;
    emit(
      s.copy(
        from: from,
        until: t,
        start: from,
        end: blockSlotEnd(t, s.slotStep),
        custom: false,
        review: false,
      ),
    );
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
          clearRange: true,
          error: s.error,
        ),
      );
      return;
    }
    emit(s.copy(slotsLoading: true, clearSlotsError: true, error: s.error));
    try {
      final r = await repository.slots(b.id, s.date, s.spaces);
      if (isClosed || !authorized || g != slotGeneration) return;
      final keep = state.hasRange && _open(r.slots, state.from!, state.until!);
      emit(
        state.copy(
          slots: r.slots,
          slotStep: r.step,
          slotsLoading: false,
          clearRange: !keep,
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
    if (state.pending == null) {
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
    final request =
        state.pending ??
        BlockRequest(
          key: const Uuid().v4(),
          businessId: state.businessId!,
          spaces: state.spaces,
          date: state.date,
          allDay: state.allDay,
          start: state.start,
          end: state.end,
        );
    final g = generation;
    emit(state.copy(saving: true, pending: request));
    try {
      final id = await repository.create(request);
      if (current(g)) {
        emit(state.copy(saving: false, clearPending: true, savedId: id));
      }
    } catch (e) {
      if (current(g)) {
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
        emit(
          state.copy(
            saving: false,
            clearPending: !uncertain,
            error: uncertain
                ? 'Could not confirm the block. Retry to verify the same request.'
                : bookingError(e),
          ),
        );
        if (!uncertain) unawaited(loadSlots());
      }
    }
  }
}
