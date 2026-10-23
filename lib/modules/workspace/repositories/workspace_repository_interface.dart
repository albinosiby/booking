import 'dart:typed_data';
import '../models/workspace.dart';

abstract interface class WorkspaceRepository {
  Future<Workspace> load();
  Future<Map<String, dynamic>> catalog();
  Future<List<CatalogOption>> states(String country);
  Future<void> createOrganization(Map<String, dynamic> data);
  Future<void> uploadLogo(Uint8List bytes, String contentType);
  Future<void> addBusiness(Map<String, dynamic> data);
  Future<void> reorderBusinesses(List<String> ids, int revision);
  Future<void> renameBusiness(String id, String name);
  Future<void> addResource(String id, String name, int capacity);
  Future<void> removeResource(String business, String resource);
  Future<void> configure(String id, Map<String, dynamic> data);
  Future<void> activate(String id);
  Future<Map<String, dynamic>> team();
  Future<String> invite(Map<String, dynamic> data);
  Future<Map<String, dynamic>> addTeamMember(Map<String, dynamic> data);
  Future<Map<String, dynamic>> updatePendingTeamAccess(
    String id,
    Map<String, dynamic> data,
  );
  Future<Map<String, dynamic>> resendTeamEmail(String id);
  Future<void> accept(String token);
  Future<void> revoke(String id, {bool invitation = false});
  Future<void> updateMember(String id, Map<String, dynamic> data);
}

/// Optional non-blocking branding capability; access is verified by load().
abstract interface class WorkspaceLogoRepository {
  Future<Uint8List?> loadLogo();
}

abstract interface class WorkspaceLogoEvents {
  Stream<void> get logoChanges;
}

/// Transport access failures are reconciled before feature errors are delivered.
abstract interface class WorkspaceAccessRecovery {
  void setAccessRecovery(Future<void> Function()? recover);
}
