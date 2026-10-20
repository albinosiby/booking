import '../cubit/workspace_state.dart';

/// Authorized session snapshot and refresh coordinator shared by feature Cubits.
abstract interface class WorkspaceSession {
  WorkspaceState get state;
  Stream<WorkspaceState> get snapshots;
  Future<void> load();
  Future<bool> change(Future<void> Function() action);
}
