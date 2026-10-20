import '../../workspace/cubit/workspace_state.dart';
import '../../workspace/repositories/workspace_session.dart';

abstract interface class DashboardRepository {
  WorkspaceState get current;
  Stream<WorkspaceState> get changes;
  Future<void> refresh();
}

class SessionDashboardRepository implements DashboardRepository {
  SessionDashboardRepository(this.session);
  final WorkspaceSession session;
  @override
  WorkspaceState get current => session.state;
  @override
  Stream<WorkspaceState> get changes => session.snapshots;
  @override
  Future<void> refresh() => session.load();
}
