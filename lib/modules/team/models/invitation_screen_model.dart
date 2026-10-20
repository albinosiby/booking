import '../../workspace/models/workspace_state.dart';

/// Immutable data rendered by the invitation screen.
class InvitationScreenModel extends WorkspaceState {
  InvitationScreenModel.fromSnapshot(WorkspaceState snapshot)
    : super(
        status: snapshot.status,
        data: snapshot.data,
        busy: snapshot.busy,
        error: snapshot.error,
      );
}
