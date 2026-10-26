import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/admission_models.dart';
import '../repositories/admission_repository.dart';
import 'admission_cubit.dart' show admissionError;

class ExpiredMembersState {
  const ExpiredMembersState({
    this.items = const [],
    this.next,
    this.loading = false,
    this.error,
  });
  final List<Admission> items;
  final int? next;
  final bool loading;
  final String? error;
}

class ExpiredMembersCubit extends Cubit<ExpiredMembersState> {
  ExpiredMembersCubit(this.repository) : super(const ExpiredMembersState()) {
    subscription = repository.changes.listen((_) => load());
  }
  final MembershipActions repository;
  late final StreamSubscription<void> subscription;
  int generation = 0;
  Future<void> load({bool more = false}) async {
    if (isClosed || more && (state.loading || state.next == null)) return;
    final request = ++generation;
    final previous = more ? state.items : <Admission>[];
    emit(
      ExpiredMembersState(items: state.items, next: state.next, loading: true),
    );
    try {
      final page = await repository.expiredMembers(
        cursor: more ? state.next! : 0,
      );
      if (isClosed || request != generation) return;
      final items = {
        for (final admission in [...previous, ...page.items])
          admission.id: admission,
      };
      emit(
        ExpiredMembersState(
          items: List.unmodifiable(items.values),
          next: page.next,
        ),
      );
    } catch (error) {
      if (!isClosed && request == generation) {
        emit(
          accessFailure(error)
              ? const ExpiredMembersState(
                  error: 'Access denied. Reopen this page.',
                )
              : ExpiredMembersState(
                  items: state.items,
                  next: state.next,
                  error: admissionError(error),
                ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    await super.close();
  }
}
