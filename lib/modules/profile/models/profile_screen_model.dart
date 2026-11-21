import 'organization_details_model.dart';
import '../../workspace/models/workspace_state.dart';

/// Immutable data rendered by the profile screen.
class ProfileScreenModel extends WorkspaceState {
  ProfileScreenModel.fromSnapshot(
    WorkspaceState snapshot, {
    required this.organizationDetails,
    this.appVersion,
    this.appVersionLoading = false,
  }) : super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  String get roleLabel => switch (data.membership?['role']) {
    'owner' => 'Owner',
    'manager' => 'Manager',
    _ => 'Staff',
  };
  String get ownerName =>
      data.isOwner ? (data.membership?['display_name'] as String? ?? '') : '';
  String get ownerEmail =>
      data.isOwner ? (data.membership?['email'] as String? ?? '') : '';
  final OrganizationDetailsModel organizationDetails;
  final String? appVersion;
  final bool appVersionLoading;
  @override
  List<Object?> get props => [...super.props, appVersion, appVersionLoading];
}
