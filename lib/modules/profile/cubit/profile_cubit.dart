import '../../../utils/exceptions/app_exception.dart';
import '../models/organization_details_model.dart';
import '../../../core/state/workspace_screen_cubit.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../workspace/models/workspace_state.dart';
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

  @override
  ProfileScreenModel mapSnapshot(WorkspaceState snapshot) =>
      ProfileScreenModel.fromSnapshot(
        snapshot,
        organizationDetails: repository.details(snapshot.data),
        appVersion: state.appVersion,
        appVersionLoading: state.appVersionLoading,
      );

  Future<void> loadAppVersion() async {
    if (isClosed || state.appVersionLoading || state.appVersion != null) return;
    emit(
      ProfileScreenModel.fromSnapshot(
        state,
        organizationDetails: state.organizationDetails,
        appVersionLoading: true,
      ),
    );
    String? version;
    try {
      version = await repository.appVersion().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      // Metadata availability must not block account or workspace actions.
    }
    if (isClosed) return;
    emit(
      ProfileScreenModel.fromSnapshot(
        state,
        organizationDetails: state.organizationDetails,
        appVersion: version,
      ),
    );
  }

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
