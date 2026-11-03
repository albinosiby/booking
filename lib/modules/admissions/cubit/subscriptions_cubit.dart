import 'dart:async';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/admission_models.dart';
import '../repositories/admission_repository.dart';
import 'admission_cubit.dart' show admissionError;

class SubscriptionsState extends Equatable {
  const SubscriptionsState({
    this.items = const [],
    this.query = '',
    this.status,
    this.next,
    this.loading = false,
    this.error,
  });
  final List<Admission> items;
  final String query;

  /// Null lists every subscription.
  final String? status;
  final int? next;
  final bool loading;
  final String? error;
  @override
  List<Object?> get props => [items, query, status, next, loading, error];
}

/// Every subscription for Profile → Subscriptions.
class SubscriptionsCubit extends Cubit<SubscriptionsState> {
  SubscriptionsCubit(this.repository) : super(const SubscriptionsState()) {
    changes = repository.changes.listen((_) => load());
  }
  final AdmissionRepository repository;
  late final StreamSubscription<void> changes;
  int generation = 0;

  Future<void> load({
    String? query,
    String? status,
    bool clearStatus = false,
    bool more = false,
  }) async {
    if (isClosed || more && (state.loading || state.next == null)) return;
    final g = ++generation;
    final q = query ?? state.query,
        st = clearStatus ? null : status ?? state.status;
    emit(
      SubscriptionsState(
        items: more ? state.items : const [],
        query: q,
        status: st,
        next: state.next,
        loading: true,
      ),
    );
    try {
      final page = await repository.subscriptions(
        query: q,
        status: st,
        cursor: more ? state.next! : 0,
      );
      if (isClosed || g != generation) return;
      emit(
        SubscriptionsState(
          items: List.unmodifiable([if (more) ...state.items, ...page.items]),
          query: q,
          status: st,
          next: page.next,
        ),
      );
    } catch (e) {
      if (isClosed || g != generation) return;
      emit(
        SubscriptionsState(
          items: state.items,
          query: q,
          status: st,
          next: state.next,
          error: accessFailure(e)
              ? 'Access denied. Reopen this page.'
              : admissionError(e),
        ),
      );
    }
  }

  @override
  Future<void> close() async {
    generation++;
    await changes.cancel();
    return super.close();
  }
}
