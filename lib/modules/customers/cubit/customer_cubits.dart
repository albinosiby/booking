import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/customer_models.dart';
import '../repositories/customer_repository.dart';

abstract class CustomerAccessCubit<S> extends Cubit<S> {
  CustomerAccessCubit(this.session, this.repository, super.initialState) {
    scope = workspaceAccessScope(session.state.data);
    access = session.snapshots.listen((_) {
      final current = workspaceAccessScope(session.state.data);
      if (current != scope) {
        scope = current;
        generation++;
        resetAccess();
      }
    });
    changes = repository.changes.listen((_) => refresh());
  }
  final WorkspaceSession session;
  final CustomerRepository repository;
  late final StreamSubscription access, changes;
  late String scope;
  int generation = 0;
  bool get allowed =>
      session.state.data.organization != null &&
      [
        'view_bookings',
        'manage_bookings',
        'collect_payments',
      ].any(session.state.data.hasPermission);
  bool valid(int g) =>
      !isClosed &&
      g == generation &&
      scope == workspaceAccessScope(session.state.data);
  String message(Object e) => e is AppException
      ? e.message
      : 'Could not load customers. Please try again.';
  void resetAccess();
  Future<void> refresh();
  @override
  Future<void> close() async {
    generation++;
    await access.cancel();
    await changes.cancel();
    return super.close();
  }
}

class CustomerListCubit extends CustomerAccessCubit<CustomerListModel> {
  CustomerListCubit(WorkspaceSession session, CustomerRepository repository)
    : super(session, repository, CustomerListModel());
  Timer? debounce;
  void search(String query) {
    debounce?.cancel();
    generation++;
    emit(CustomerListModel(query: query, loading: true));
    debounce = Timer(const Duration(milliseconds: 300), () => load());
  }

  Future<void> load({bool more = false}) async {
    if (more && (state.loadingMore || state.next == null || state.loading)) {
      return;
    }
    final g = ++generation, previous = state;
    if (!allowed) {
      emit(
        CustomerListModel(
          query: previous.query,
          loading: false,
          error: 'Booking access is required to view customers.',
        ),
      );
      return;
    }
    emit(
      CustomerListModel(
        query: previous.query,
        items: previous.items,
        next: previous.next,
        loading: !more,
        loadingMore: more,
      ),
    );
    try {
      final page = await repository.search(
        query: previous.query.trim(),
        after: more ? previous.next : null,
      );
      if (valid(g)) {
        emit(
          CustomerListModel(
            query: previous.query,
            items: more ? [...previous.items, ...page.items] : page.items,
            next: page.next,
            loading: false,
          ),
        );
      }
    } catch (e) {
      if (valid(g)) {
        emit(
          CustomerListModel(
            query: previous.query,
            items: accessFailure(e) ? const [] : previous.items,
            next: accessFailure(e) ? null : previous.next,
            loading: false,
            error: message(e),
          ),
        );
      }
    }
  }

  @override
  void resetAccess() {
    debounce?.cancel();
    emit(CustomerListModel());
    load();
  }

  @override
  Future<void> refresh() async {
    debounce?.cancel();
    repository.invalidate();
    await load();
  }

  @override
  Future<void> close() {
    debounce?.cancel();
    return super.close();
  }
}

class CustomerDetailCubit extends CustomerAccessCubit<CustomerDetailModel> {
  CustomerDetailCubit(
    WorkspaceSession session,
    CustomerRepository repository,
    this.id,
  ) : super(session, repository, CustomerDetailModel());
  final String id;
  Future<void> load({bool more = false}) async {
    if (more && (state.loading || state.loadingMore || state.next == null)) {
      return;
    }
    final g = ++generation, old = state;
    if (!allowed) {
      emit(
        CustomerDetailModel(
          loading: false,
          error: 'Booking access is required to view customer history.',
        ),
      );
      return;
    }
    emit(
      CustomerDetailModel(
        customer: old.customer,
        currency: old.currency,
        bookings: old.bookings,
        next: old.next,
        loading: !more,
        loadingMore: more,
      ),
    );
    try {
      final page = await repository.history(id, cursor: more ? old.next : null);
      if (valid(g)) {
        emit(
          CustomerDetailModel(
            customer: page.customer,
            currency: page.currency,
            bookings: more ? [...old.bookings, ...page.items] : page.items,
            next: page.next,
            loading: false,
          ),
        );
      }
    } catch (e) {
      if (valid(g)) {
        final clear =
            accessFailure(e) ||
            (e is AppException &&
                ['NOT_FOUND', 'REQUEST_ERROR'].contains(e.code));
        emit(
          CustomerDetailModel(
            customer: clear ? null : old.customer,
            currency: old.currency,
            bookings: clear ? const [] : old.bookings,
            next: clear ? null : old.next,
            loading: false,
            error: message(e),
          ),
        );
      }
    }
  }

  @override
  void resetAccess() {
    emit(CustomerDetailModel());
    load();
  }

  @override
  Future<void> refresh() async {
    repository.invalidate();
    await load();
  }
}
