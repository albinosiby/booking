import '../../../utils/services/rest_api_service.dart';
import '../../organization/models/location_catalog.dart';
import '../../organization/repositories/organization_repository.dart';
import '../../workspace/models/workspace.dart';
import '../models/organization_edit_model.dart';
import 'organization_edit_repository.dart';

class RestOrganizationEditRepository implements OrganizationEditRepository {
  RestOrganizationEditRepository(this.api, this.organization);
  final RestApiService api;
  final OrganizationRepository organization;
  OrganizationEditDraft decode(dynamic j) => OrganizationEditDraft(
    revision: j['revision'],
    name: j['name'],
    phone: j['contact_phone'],
    currency: j['currency'],
    locations: [
      for (final l in j['locations'])
        OrganizationEditLocation(
          id: l['id'],
          name: l['name'],
          line1: l['address_line_1'],
          line2: l['address_line_2'] ?? '',
          city: l['city'],
          stateCode: l['state_code'] ?? '',
          countryCode: l['country_code'],
          pincode: l['postal_code'],
          timezone: l['timezone'],
        ),
    ],
  );
  Map<String, Object?> encode(OrganizationEditDraft d) => {
    'revision': d.revision,
    'name': d.name.trim(),
    'contact_phone': d.phone.trim(),
    'locations': [
      for (final l in d.locations)
        {
          'id': l.id,
          'name': l.name.trim(),
          'address_line_1': l.line1.trim(),
          'address_line_2': l.line2.trim().isEmpty ? null : l.line2.trim(),
          'city': l.city.trim(),
          'state_code': l.stateCode.isEmpty ? null : l.stateCode,
          'country_code': l.countryCode,
          'postal_code': l.pincode.trim(),
        },
    ],
  };
  @override
  Future<OrganizationEditDraft> load() async =>
      decode(await api.request('/organization/details'));
  @override
  Future<OrganizationEditDraft> save(OrganizationEditDraft d) async => decode(
    await api.request(
      '/organization/details',
      method: 'PATCH',
      data: encode(d),
    ),
  );
  @override
  Future<LocationCatalog> catalog() => organization.catalog();
  @override
  Future<List<CatalogOption>> states(String country) =>
      organization.states(country);
}
