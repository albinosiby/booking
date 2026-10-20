import '../../workspace/models/workspace_state.dart';

class StartupScreenModel extends WorkspaceState {
  StartupScreenModel.fromSnapshot(WorkspaceState snapshot)
    : super(
        status: snapshot.status,
        data: snapshot.data,
        busy: snapshot.busy,
        error: snapshot.error,
      );
}
