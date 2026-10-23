import '../repositories/workspace_preloader.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../repositories/workspace_repository_interface.dart';
import 'workspace_state.dart';
import '../repositories/refreshable_reads.dart';
import '../models/workspace.dart';
import '../repositories/workspace_session.dart';
export 'workspace_state.dart';

class WorkspaceCubit extends Cubit<WorkspaceState> implements WorkspaceSession {
  WorkspaceCubit(this.repository, {this.preloader})
    : super(const WorkspaceState()) {
    final source = repository;
    if (source is WorkspaceAccessRecovery) {
      (source as WorkspaceAccessRecovery).setAccessRecovery(refreshAccess);
    }
    if (source is WorkspaceLogoEvents) {
      _logoUpdates = (source as WorkspaceLogoEvents).logoChanges.listen((_) {
        if (!isClosed) _loadLogo(state.data, _generation);
      });
    }
  }
  StreamSubscription<void>? _logoUpdates;
  @override
  Future<void> close() async {
    _generation++;
    final source = repository;
    if (source is WorkspaceAccessRecovery) {
      (source as WorkspaceAccessRecovery).setAccessRecovery(null);
    }
    await _logoUpdates?.cancel();
    return super.close();
  }

  final WorkspaceRepository repository;
  final WorkspacePreloader? preloader;
  @override
  Stream<WorkspaceState> get snapshots => stream;
  @override
  Future<bool> change(Future<void> Function() action) =>
      perform((_) => action());
  int _generation = 0;
  DateTime? _lastRevalidation;
  void revalidateRetainedPages() {
    final now = DateTime.now();
    if (_lastRevalidation != null &&
        now.difference(_lastRevalidation!) < const Duration(seconds: 20)) {
      return;
    }
    _lastRevalidation = now;
    final source = repository;
    if (source is RetainedReadEvents) {
      (source as RetainedReadEvents).revalidateReads();
    }
  }

  Future<void>? _accessCheck;

  /// Silent foreground check: no loading state, logo fetch or preloading.
  Future<void> refreshAccess() {
    if (isClosed ||
        state.busy ||
        (state.status == LoadStatus.initial ||
            state.status == LoadStatus.loading) ||
        state.data.organization == null) {
      return Future.value();
    }
    return _accessCheck ??= _refreshAccess().whenComplete(
      () => _accessCheck = null,
    );
  }

  Future<void> _refreshAccess() async {
    final generation = _generation;
    try {
      final data = _retainLogo(await repository.load());
      if (!isClosed && generation == _generation && !state.busy) {
        emit(WorkspaceState(status: LoadStatus.ready, data: data));
      }
    } catch (e) {
      if (!isClosed && generation == _generation && accessFailure(e)) {
        preloader?.reset();
        emit(
          const WorkspaceState(
            status: LoadStatus.failure,
            error: 'Your workspace access has changed.',
          ),
        );
      }
      // Network failure does not erase the last authorized UI. Writes still
      // require current server authorization, even while offline.
    }
  }

  void clear() {
    preloader?.reset();
    _generation++;
    _lastRevalidation = null;
    emit(const WorkspaceState());
  }

  Workspace _retainLogo(Workspace data) =>
      data.organization?.id == state.data.organization?.id &&
          data.organization?.logoKey == state.data.organization?.logoKey &&
          data.organization?.logoKey != null
      ? data.withLogo(data.logo ?? state.data.logo)
      : data;

  void _loadLogo(Workspace data, int generation) {
    final source = repository;
    if (source is! WorkspaceLogoRepository ||
        data.organization?.logoKey == null) {
      return;
    }
    unawaited(() async {
      try {
        final logo = await (source as WorkspaceLogoRepository).loadLogo();
        if (!isClosed &&
            generation == _generation &&
            state.data.organization?.id == data.organization?.id &&
            state.data.organization?.logoKey == data.organization?.logoKey &&
            logo != null) {
          emit(
            WorkspaceState(
              status: state.status,
              data: state.data.withLogo(logo),
              busy: state.busy,
              error: state.error,
            ),
          );
        }
      } catch (_) {
        // Branding is optional; keep authorized content and any retained image.
      }
    }());
  }

  @override
  Future<void> load() async {
    final generation = ++_generation;
    emit(WorkspaceState(status: LoadStatus.loading, data: state.data));
    try {
      final data = _retainLogo(await repository.load());
      if (!isClosed && generation == _generation) {
        emit(WorkspaceState(status: LoadStatus.ready, data: data));
        _loadLogo(data, generation);
        unawaited(
          preloader?.warm(
            data,
            () =>
                !isClosed &&
                generation == _generation &&
                state.status == LoadStatus.ready,
          ),
        );
      }
    } catch (e) {
      if (!isClosed && generation == _generation) {
        emit(
          WorkspaceState(
            status: LoadStatus.failure,
            data: accessFailure(e) ? const Workspace() : state.data,
            error: _message(e),
          ),
        );
      }
    }
  }

  String _message(Object e) => e is AppException
      ? e.message
      : 'Could not save your changes. Please try again.';
  Future<bool> perform(
    Future<void> Function(WorkspaceRepository) action,
  ) async {
    if (state.busy) return false;
    final generation = _generation;
    emit(WorkspaceState(status: state.status, data: state.data, busy: true));
    try {
      await action(repository);
      final data = _retainLogo(await repository.load());
      if (isClosed || generation != _generation) return false;
      emit(WorkspaceState(status: LoadStatus.ready, data: data));
      _loadLogo(data, generation);
      return true;
    } catch (e) {
      if (isClosed || generation != _generation) return false;
      var data = state.data;
      var reloaded = false;
      try {
        data = _retainLogo(await repository.load());
        reloaded = true;
      } catch (_) {
        // Keep the last authorized snapshot when connectivity is unavailable.
      }
      if (!isClosed && generation == _generation) {
        emit(
          WorkspaceState(
            status: reloaded ? LoadStatus.ready : state.status,
            data: data,
            error: reloaded && e is AppException && e.code == 'NETWORK'
                ? 'Could not confirm the save. Your latest data has been reloaded; review it before retrying.'
                : _message(e),
          ),
        );
        if (reloaded) _loadLogo(data, generation);
      }
      return false;
    }
  }
}
