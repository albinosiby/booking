import '../../workspace/models/workspace.dart';

class BusinessDraft {
  const BusinessDraft({
    required this.name,
    required this.type,
    required this.locationId,
  });
  final String name, locationId;
  final BusinessType type;
  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type.code,
    'location_id': locationId,
  };
}

class ResourceDraft {
  const ResourceDraft({required this.name, required this.capacity});
  final String name;
  final int capacity;
}

class BusinessConfiguration {
  BusinessConfiguration({
    required this.version,
    required this.opensAt,
    required this.closesAt,
    required List<int> days,
    required this.durationMinutes,
    required this.priceMinor,
    required this.bufferMinutes,
    this.planName,
    this.validityDays,
    this.entitlement,
    this.visitLimit,
  }) : days = List.unmodifiable(days);
  final int version, durationMinutes, priceMinor, bufferMinutes;
  final String opensAt, closesAt;
  final List<int> days;
  final String? planName, entitlement;
  final int? validityDays, visitLimit;
  Map<String, dynamic> toJson() => {
    'version': version,
    'opens_at': opensAt,
    'closes_at': closesAt,
    'days': days,
    'duration_minutes': durationMinutes,
    'price_minor': priceMinor,
    'buffer_minutes': bufferMinutes,
    'plan_name': planName,
    'validity_days': validityDays,
    'entitlement': entitlement,
    'visit_limit': visitLimit,
  };
}
