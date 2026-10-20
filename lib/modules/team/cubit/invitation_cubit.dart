import '../../../core/state/workspace_screen_cubit.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../repositories/team_repository.dart';
import '../models/invitation_screen_model.dart';

class InvitationCubit extends WorkspaceScreenCubit<InvitationScreenModel> {
  InvitationCubit(WorkspaceSession session, this.repository)
    : super(session, InvitationScreenModel.fromSnapshot);
  final TeamRepository repository;
  Future<bool> accept(String token) => save(() => repository.accept(token));
}
