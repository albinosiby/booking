import 'dart:typed_data';
import '../models/organization_draft.dart';
import '../models/location_catalog.dart';
import '../../workspace/models/workspace.dart';
import '../../workspace/repositories/workspace_repository_interface.dart';

abstract interface class OrganizationRepository {
  Future<void> create(OrganizationDraft draft);
  Future<void> uploadLogo(Uint8List bytes, String contentType);
  Future<LocationCatalog> catalog();
  Future<List<CatalogOption>> states(String country);
}

class LocalApiOrganizationRepository implements OrganizationRepository {
  LocalApiOrganizationRepository(this.source);
  final WorkspaceRepository source;
  @override
  Future<void> create(OrganizationDraft draft) =>
      source.createOrganization(draft.toJson());
  @override
  Future<void> uploadLogo(Uint8List bytes, String contentType) =>
      source.uploadLogo(bytes, contentType);
  @override
  Future<LocationCatalog> catalog() async =>
      LocationCatalog.fromJson(await source.catalog());
  @override
  Future<List<CatalogOption>> states(String country) => source.states(country);
}
