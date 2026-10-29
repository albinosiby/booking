import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/staff_cash_models.dart';
import '../repositories/staff_cash_repository.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/models/workspace_navigation.dart';

String staffCashError(Object e) => e is AppException
    ? e.message
    : 'Could not load staff cash. Please try again.';

class StaffCashState extends Equatable {
  const StaffCashState({
    this.day,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });
  final StaffCashDay? day;
  final bool loading, loadingMore;
  final String? error;
  @override
  List<Object?> get props => [day, loading, loadingMore, error];
}

/// Staff view: today's collections, cash still to hand over, and settlements.
class StaffCashCubit extends Cubit<StaffCashState> {
  StaffCashCubit(this.repository, {required this.session})
    : super(const StaffCashState()) {
    scope = workspaceAccessScope(session.state.data);
    access = session.snapshots.listen((_) {
      if (isClosed) return;
      final next = workspaceAccessScope(session.state.data);
      if (next != scope) {
        _generation++;
        scope = next;
        emit(const StaffCashState());
        if (authorized) unawaited(load());
      }
    });
    changes = repository.changes.listen((_) {
      if (authorized) unawaited(load(date: state.day?.date));
    });
  }
  final IStaffCashRepository repository;
  final WorkspaceSession session;
  late String scope;
  late final StreamSubscription changes, access;
  int _generation = 0;
  bool get authorized =>
      !isClosed &&
      scope == workspaceAccessScope(session.state.data) &&
      WorkspaceNavigation(session.state.data).staffCash;

  Future<void> load({String? date}) async {
    if (!authorized) return;
    final g = ++_generation;
    emit(StaffCashState(day: state.day, loading: true));
    try {
      final day = await repository.me(date: date);
      if (authorized && g == _generation) emit(StaffCashState(day: day));
    } catch (e) {
      if (authorized && g == _generation) {
        emit(
          StaffCashState(
            day: accessFailure(e) ? null : state.day,
            error: staffCashError(e),
          ),
        );
      }
    }
  }

  Future<void> loadMore({bool settlements = false}) async {
    final old = state.day;
    if (!authorized || state.loading || state.loadingMore || old == null) {
      return;
    }
    final cursor = settlements ? old.nextSettlementCursor : old.nextCursor;
    if (cursor == null) return;
    final g = _generation;
    emit(StaffCashState(day: old, loadingMore: true));
    try {
      final page = await repository.me(
        date: old.date,
        cursor: settlements ? 0 : cursor,
        settlementCursor: settlements ? cursor : 0,
      );
      if (!authorized || g != _generation) return;
      final transactions = settlements
          ? old.transactions
          : {
              for (final t in [...old.transactions, ...page.transactions])
                t.id: t,
            }.values.toList();
      final handovers = settlements
          ? {
              for (final t in [...old.settlements, ...page.settlements])
                t.id: t,
            }.values.toList()
          : old.settlements;
      emit(
        StaffCashState(
          day: page.withHistory(
            transactions: transactions,
            settlements: handovers,
            nextCursor: settlements ? old.nextCursor : page.nextCursor,
            nextSettlementCursor: settlements
                ? page.nextSettlementCursor
                : old.nextSettlementCursor,
          ),
        ),
      );
    } catch (e) {
      if (authorized && g == _generation) {
        emit(
          StaffCashState(
            day: accessFailure(e) ? null : old,
            error: staffCashError(e),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    _generation++;
    await changes.cancel();
    await access.cancel();
    await super.close();
  }
}

class OwnerStaffCashState extends Equatable {
  const OwnerStaffCashState({
    this.staff = const [],
    this.loading = false,
    this.settling = false,
    this.error,
    this.loaded = false,
  });
  final List<StaffCashMember> staff;
  final bool loading, settling, loaded;
  final String? error;
  @override
  List<Object?> get props => [staff, loading, settling, error, loaded];
}

/// Owner view: cash each staff member holds, and collect/give settlement.
class OwnerStaffCashCubit extends Cubit<OwnerStaffCashState> {
  OwnerStaffCashCubit(this.repository) : super(const OwnerStaffCashState()) {
    changes = repository.changes.listen((_) => load());
  }
  final IStaffCashRepository repository;
  late final StreamSubscription<void> changes;
  int _generation = 0;
  Future<void> load({String? keepError}) async {
    final g = ++_generation;
    emit(
      OwnerStaffCashState(
        staff: state.staff,
        loading: true,
        loaded: state.loaded,
        error: keepError,
      ),
    );
    try {
      final staff = await repository.overview();
      if (!isClosed && g == _generation) {
        emit(OwnerStaffCashState(staff: staff, loaded: true, error: keepError));
      }
    } catch (e) {
      if (!isClosed && g == _generation) {
        emit(
          OwnerStaffCashState(
            staff: state.staff,
            loaded: state.loaded,
            error: staffCashError(e),
          ),
        );
      }
    }
  }

  /// Returns the remaining balance, or null when settling failed ([state.error] says why).
  Future<int?> settle(
    StaffCashMember member,
    int amountMinor, {
    String note = '',
    String? commandKey,
  }) async {
    if (state.settling || amountMinor <= 0) return null;
    emit(OwnerStaffCashState(staff: state.staff, settling: true, loaded: true));
    try {
      final after = await repository.settle(
        member.id,
        StaffCashSettleRequest(
          commandKey: commandKey ?? const Uuid().v4(),
          direction: member.holdingMinor > 0 ? 'collect' : 'give',
          amountMinor: amountMinor,
          expectedBalanceMinor: member.holdingMinor,
          note: note,
        ),
      );
      if (!isClosed) {
        emit(
          OwnerStaffCashState(
            staff: [
              for (final s in state.staff)
                s.id == member.id
                    ? StaffCashMember(
                        id: s.id,
                        name: s.name,
                        spaces: s.spaces,
                        holdingMinor: after,
                      )
                    : s,
            ],
            loaded: true,
          ),
        );
      }
      return after;
    } catch (e) {
      if (!isClosed) {
        emit(
          OwnerStaffCashState(
            staff: state.staff,
            loaded: true,
            error: staffCashError(e),
          ),
        );
        unawaited(load(keepError: staffCashError(e)));
      }
      return null;
    }
  }

  @override
  Future<void> close() {
    changes.cancel();
    return super.close();
  }
}

class StaffCashHistoryState extends Equatable {
  const StaffCashHistoryState({this.items = const [], this.error});
  final List<StaffCashSettlement> items;
  final String? error;
  @override
  List<Object?> get props => [items, error];
}

class StaffCashHistoryCubit extends Cubit<StaffCashHistoryState> {
  StaffCashHistoryCubit(this.repository) : super(const StaffCashHistoryState());
  final IStaffCashRepository repository;
  Future<void> load(String from, String until) async {
    try {
      final items = await repository.history(from, until);
      if (!isClosed) emit(StaffCashHistoryState(items: items));
    } catch (e) {
      if (!isClosed) emit(StaffCashHistoryState(error: staffCashError(e)));
    }
  }
}
