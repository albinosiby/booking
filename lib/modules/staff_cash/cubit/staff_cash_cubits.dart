import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/staff_cash_models.dart';
import '../repositories/staff_cash_repository.dart';

String staffCashError(Object e) => e is AppException
    ? e.message
    : 'Could not load staff cash. Please try again.';

class StaffCashState extends Equatable {
  const StaffCashState({this.day, this.loading = false, this.error});
  final StaffCashDay? day;
  final bool loading;
  final String? error;
  @override
  List<Object?> get props => [day, loading, error];
}

/// Staff view: today's collections, cash still to hand over, and settlements.
class StaffCashCubit extends Cubit<StaffCashState> {
  StaffCashCubit(this.repository) : super(const StaffCashState()) {
    changes = repository.changes.listen((_) => load(date: state.day?.date));
  }
  final IStaffCashRepository repository;
  late final StreamSubscription<void> changes;
  int _generation = 0;
  Future<void> load({String? date}) async {
    final g = ++_generation;
    emit(StaffCashState(day: state.day, loading: true));
    try {
      final day = await repository.me(date: date);
      if (!isClosed && g == _generation) emit(StaffCashState(day: day));
    } catch (e) {
      if (!isClosed && g == _generation) {
        emit(StaffCashState(day: state.day, error: staffCashError(e)));
      }
    }
  }

  @override
  Future<void> close() {
    changes.cancel();
    return super.close();
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
