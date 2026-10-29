import 'dart:convert';
import 'dart:typed_data';
import '../../../constants/api_path.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/workspace.dart';
import 'workspace_repository_interface.dart';
import 'refreshable_reads.dart';

class RestWorkspaceRepository
    implements
        WorkspaceRepository,
        WorkspaceAccessRecovery,
        WorkspaceLogoRepository,
        WorkspaceLogoEvents,
        RefreshableReads,
        RetainedReadEvents {
  RestWorkspaceRepository(this.api);
  final RestApiService api;
  @override
  void setAccessRecovery(Future<void> Function()? recover) =>
      api.recoverAccess = recover;
  @override
  Stream<void> get logoChanges =>
      api.readUpdates.where((key) => key == ApiPath.logo).map((_) {});
  @override
  Stream<void> get readChanges => api.readUpdates
      .where((key) => key == '*' || key == ApiPath.team)
      .map((_) {});
  @override
  void revalidateReads() => api.revalidateReads();
  @override
  void invalidateReads() => api.invalidateReads();
  @override
  Future<Workspace> load() async {
    final json = Map<String, dynamic>.from(
      await api.request(
        '${ApiPath.workspace}/session',
        method: 'POST',
        readOnly: true,
      ),
    );
    await api.authorizeReads(json);
    return Workspace.fromJson(json);
  }

  @override
  Future<Uint8List?> loadLogo() async =>
      Uint8List.fromList(await api.retainedBytes(ApiPath.logo));

  @override
  Future<Map<String, dynamic>> catalog() async => Map<String, dynamic>.from(
    await api.retainedRead(
      ApiPath.catalog,
      freshFor: const Duration(hours: 24),
      retainFor: const Duration(days: 7),
    ),
  );
  @override
  Future<List<CatalogOption>> states(String country) async => List.unmodifiable(
    (await api.retainedRead(
              '${ApiPath.catalog}/states/$country',
              freshFor: const Duration(hours: 24),
              retainFor: const Duration(days: 7),
            )
            as List)
        .map((v) => CatalogOption.fromJson(Map<String, dynamic>.from(v))),
  );
  @override
  Future<void> createOrganization(Map<String, dynamic> data) async {
    await api.request(ApiPath.organizations, method: 'POST', data: data);
  }

  @override
  Future<void> uploadLogo(Uint8List bytes, String contentType) async {
    await api.request(
      ApiPath.logo,
      method: 'POST',
      data: {'base64': base64Encode(bytes), 'content_type': contentType},
    );
  }

  @override
  Future<void> addBusiness(Map<String, dynamic> data) async {
    await api.request(ApiPath.businesses, method: 'POST', data: data);
  }

  @override
  Future<void> reorderBusinesses(List<String> ids, int revision) async {
    await api.request(
      '${ApiPath.businesses}/order',
      method: 'PUT',
      data: {'business_ids': ids, 'revision': revision},
    );
  }

  @override
  Future<void> renameBusiness(String id, String name) async {
    await api.request(
      '${ApiPath.businesses}/$id',
      method: 'PATCH',
      data: {'name': name},
    );
  }

  @override
  Future<void> removeBusiness(String id, int version) async {
    await api.request(
      '${ApiPath.businesses}/$id',
      method: 'DELETE',
      data: {'version': version},
    );
  }

  @override
  Future<void> addResource(String id, String name, int capacity) async {
    await api.request(
      '${ApiPath.businesses}/$id/resources',
      method: 'POST',
      data: {'name': name, 'capacity': capacity},
    );
  }

  @override
  Future<void> removeResource(String b, String r) async {
    await api.request(
      '${ApiPath.businesses}/$b/resources/$r',
      method: 'DELETE',
    );
  }

  @override
  Future<void> configure(String id, Map<String, dynamic> data) async {
    await api.request(
      '${ApiPath.businesses}/$id/configuration',
      method: 'PATCH',
      data: data,
    );
  }

  @override
  Future<void> activate(String id) async {
    await api.request('${ApiPath.businesses}/$id/activate', method: 'POST');
  }

  @override
  Future<void> setBusinessBookingEnabled(
    String id,
    bool enabled,
    int version,
  ) async {
    await api.request(
      '${ApiPath.businesses}/$id/booking-status',
      method: 'PATCH',
      data: {'enabled': enabled, 'version': version},
    );
  }

  @override
  Future<Map<String, dynamic>> team() async =>
      Map<String, dynamic>.from(await api.request(ApiPath.team));
  @override
  Future<String> invite(Map<String, dynamic> data) async => (await api.request(
    ApiPath.invitations,
    method: 'POST',
    data: data,
  ))['invitation_url'];
  @override
  Future<Map<String, dynamic>> addTeamMember(Map<String, dynamic> data) async =>
      Map<String, dynamic>.from(
        await api.request(ApiPath.team, method: 'POST', data: data),
      );
  @override
  Future<Map<String, dynamic>> updatePendingTeamAccess(
    String id,
    Map<String, dynamic> data,
  ) async => Map<String, dynamic>.from(
    await api.request(
      '${ApiPath.invitations}/$id/access',
      method: 'PATCH',
      data: data,
    ),
  );
  @override
  Future<Map<String, dynamic>> resendTeamEmail(String id) async =>
      Map<String, dynamic>.from(
        await api.request('${ApiPath.invitations}/$id/email', method: 'POST'),
      );
  @override
  Future<void> accept(String token) async {
    await api.request(
      '${ApiPath.invitations}/accept',
      method: 'POST',
      data: {'token': token},
    );
  }

  @override
  Future<void> revoke(String id, {bool invitation = false}) async {
    await api.request(
      '${invitation ? ApiPath.invitations : ApiPath.team}/$id',
      method: 'DELETE',
    );
  }

  @override
  Future<void> deleteTeamRecord(String id, {bool invitation = false}) async {
    await api.request(
      '${invitation ? ApiPath.invitations : ApiPath.team}/$id/permanent',
      method: 'DELETE',
    );
  }

  @override
  Future<void> updateMember(String id, Map<String, dynamic> data) async {
    await api.request('${ApiPath.team}/$id', method: 'PATCH', data: data);
  }
}
