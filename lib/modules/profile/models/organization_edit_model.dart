import 'package:equatable/equatable.dart';

class OrganizationEditDraft extends Equatable {
  OrganizationEditDraft({
    required this.revision,
    required this.name,
    required this.phone,
    required this.currency,
    required Iterable<OrganizationEditLocation> locations,
  }) : locations = List.unmodifiable(locations);
  final String revision, name, phone, currency;
  final List<OrganizationEditLocation> locations;
  OrganizationEditDraft copy({
    String? name,
    String? phone,
    List<OrganizationEditLocation>? locations,
  }) => OrganizationEditDraft(
    revision: revision,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    currency: currency,
    locations: locations ?? this.locations,
  );
  @override
  List<Object?> get props => [revision, name, phone, currency, locations];
}

class OrganizationEditLocation extends Equatable {
  const OrganizationEditLocation({
    required this.id,
    required this.name,
    required this.line1,
    required this.line2,
    required this.city,
    required this.stateCode,
    required this.countryCode,
    required this.pincode,
    required this.timezone,
  });
  final String id,
      name,
      line1,
      line2,
      city,
      stateCode,
      countryCode,
      pincode,
      timezone;
  OrganizationEditLocation copy({
    String? name,
    String? line1,
    String? line2,
    String? city,
    String? stateCode,
    String? countryCode,
    String? pincode,
  }) => OrganizationEditLocation(
    id: id,
    name: name ?? this.name,
    line1: line1 ?? this.line1,
    line2: line2 ?? this.line2,
    city: city ?? this.city,
    stateCode: stateCode ?? this.stateCode,
    countryCode: countryCode ?? this.countryCode,
    pincode: pincode ?? this.pincode,
    timezone: timezone,
  );
  @override
  List<Object?> get props => [
    id,
    name,
    line1,
    line2,
    city,
    stateCode,
    countryCode,
    pincode,
    timezone,
  ];
}
