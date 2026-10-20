import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../modules/workspace/cubit/workspace_state.dart';
import '../../modules/workspace/repositories/workspace_session.dart';

/// Observes session changes without putting database calls in widgets.
abstract class WorkspaceScreenCubit<M extends WorkspaceState> extends Cubit<M> {
  WorkspaceScreenCubit(this.session, M Function(WorkspaceState) model)
    : _model = model,
      super(model(session.state)) {
    _subscription = session.snapshots.listen((snapshot) {
      if (!isClosed) emit(mapSnapshot(snapshot));
    });
  }
  final M Function(WorkspaceState) _model;
  M mapSnapshot(WorkspaceState snapshot) => _model(snapshot);
  final WorkspaceSession session;
  late final StreamSubscription<WorkspaceState> _subscription;
  Future<bool> save(Future<void> Function() action) => session.change(action);
  Future<void> reload() => session.load();
  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
