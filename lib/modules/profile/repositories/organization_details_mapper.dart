import '../../workspace/models/workspace.dart';
import '../models/organization_details_model.dart';

/// Projects the repository's authorized workspace snapshot without fetching it again.
OrganizationDetailsModel mapOrganizationDetails(Workspace workspace) {
  String text(Object? value) => value?.toString().trim() ?? '';
  final owner = workspace.isOwner;
  return OrganizationDetailsModel(
    name: text(workspace.organization?.name),
    phone: text(workspace.organization?.phone),
    currency: text(workspace.organization?.currency),
    ownerName: owner ? text(workspace.membership?['display_name']) : '',
    ownerEmail: owner ? text(workspace.membership?['email']) : '',
    logo: owner ? workspace.logo : null,
    locations: !owner
        ? const []
        : workspace.locations.map(
            (location) => OrganizationLocationDetails(
              id: text(location['id']),
              name: text(location['name']),
              addressLine1: text(location['address_line_1']),
              addressLine2: text(location['address_line_2']),
              city: text(location['city']),
              state: text(location['state_name'] ?? location['state_code']),
              country: text(
                location['country_name'] ?? location['country_code'],
              ),
              pincode: text(location['postal_code']),
              timezone: text(location['timezone']),
            ),
          ),
  );
}
