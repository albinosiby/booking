import '../../../utils/exceptions/app_exception.dart';
import '../models/organization_details_model.dart';
import '../../../core/state/workspace_screen_cubit.dart';
import '../../workspace/repositories/workspace_session.dart';
import 'dart:typed_data';
import '../repositories/profile_repository.dart';
import '../models/profile_screen_model.dart';

class ProfileCubit extends WorkspaceScreenCubit<ProfileScreenModel> {
  ProfileCubit(WorkspaceSession session, this.repository)
    : super(
        session,
        (snapshot) => ProfileScreenModel.fromSnapshot(
          snapshot,
          organizationDetails: repository.details(snapshot.data),
        ),
      );
  final ProfileRepository repository;
  Future<OrganizationLogoSelection?> selectLogo() async {
    if (!state.data.isOwner) return null;
    final org = state.data.organization?.id,
        member = state.data.membership?['id'];
    final selected = await repository.selectLogo();
    if (isClosed ||
        !state.data.isOwner ||
        org != state.data.organization?.id ||
        member != state.data.membership?['id']) {
      throw const AppException(
        'Your workspace changed. Reopen organization details.',
      );
    }
    return selected;
  }

  Future<bool> uploadLogo(Uint8List bytes, String contentType) =>
      save(() => repository.uploadLogo(bytes, contentType));
  Future<bool> renameBusiness(String id, String name) =>
      save(() => repository.renameBusiness(id, name));
}
