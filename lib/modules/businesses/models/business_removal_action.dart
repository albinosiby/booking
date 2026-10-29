import '../../workspace/models/workspace.dart';

/// Captures the version shown when the owner opens the confirmation.
class BusinessRemovalAction {
  BusinessRemovalAction.fromBusiness(Business business)
    : id = business.id,
      name = business.name,
      version = business.version;
  final String id, name;
  final int version;
}
