import '../../workspace/models/workspace.dart';

/// Versioned intent; an old confirmation must not overwrite newer settings.
class BusinessAvailabilityAction {
  const BusinessAvailabilityAction({
    required this.id,
    required this.name,
    required this.version,
    required this.enabled,
  });
  static BusinessAvailabilityAction? forBusiness(Business business) =>
      business.status == 'ready' || business.status == 'paused'
      ? BusinessAvailabilityAction(
          id: business.id,
          name: business.name,
          version: business.version,
          enabled: business.status == 'paused',
        )
      : null;
  final String id, name;
  final int version;
  final bool enabled;
  String get label => enabled ? 'Turn on business' : 'Turn off business';
  String get confirmation => enabled
      ? 'Allow new bookings and admissions for $name using its saved configuration?'
      : 'Stop accepting new bookings and admissions for $name? Existing bookings, payment collections, attendance and history will stay available.';
}
