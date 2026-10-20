import '../../organization/models/location_catalog.dart';
import '../../workspace/models/workspace.dart';
import '../models/organization_edit_model.dart';

abstract interface class OrganizationEditRepository {
  Future<OrganizationEditDraft> load();
  Future<OrganizationEditDraft> save(OrganizationEditDraft draft);
  Future<LocationCatalog> catalog();
  Future<List<CatalogOption>> states(String country);
}
