import 'package:package_info_plus/package_info_plus.dart';
import '../../../utils/services/logo_picker_service.dart';
import '../../workspace/models/workspace.dart';
import '../models/organization_details_model.dart';
import 'organization_details_mapper.dart';
import 'dart:typed_data';
import '../../organization/repositories/organization_repository.dart';
import '../../businesses/repositories/business_repository.dart';

abstract interface class ProfileRepository {
  OrganizationDetailsModel details(Workspace snapshot);
  Future<String> appVersion();
  Future<OrganizationLogoSelection?> selectLogo();
  Future<void> uploadLogo(Uint8List bytes, String contentType);
  Future<void> renameBusiness(String id, String name);
}

class OrganizationProfileRepository implements ProfileRepository {
  OrganizationProfileRepository(
    this.organization,
    this.businesses, {
    LogoPickerService? logoPicker,
  }) : logoPicker = logoPicker ?? LogoPickerService();
  final LogoPickerService logoPicker;
  @override
  Future<String> appVersion() async {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim(), build = info.buildNumber.trim();
    if (version.isEmpty) {
      throw StateError('App version metadata is unavailable.');
    }
    return build.isEmpty ? version : '$version (build $build)';
  }

  @override
  Future<OrganizationLogoSelection?> selectLogo() async {
    final selected = await logoPicker.pick();
    return selected == null
        ? null
        : OrganizationLogoSelection(selected.bytes, selected.contentType);
  }

  final OrganizationRepository organization;
  final BusinessRepository businesses;
  @override
  OrganizationDetailsModel details(Workspace snapshot) =>
      mapOrganizationDetails(snapshot);
  @override
  Future<void> uploadLogo(Uint8List bytes, String contentType) =>
      organization.uploadLogo(bytes, contentType);
  @override
  Future<void> renameBusiness(String id, String name) =>
      businesses.rename(id, name);
}
