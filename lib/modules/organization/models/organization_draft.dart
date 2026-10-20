class LocationDraft {
  const LocationDraft({
    required this.name,
    required this.line1,
    this.line2,
    required this.city,
    this.stateCode,
    required this.countryCode,
    required this.postalCode,
    required this.timezone,
  });
  final String name, line1, city, countryCode, postalCode, timezone;
  final String? line2, stateCode;
  Map<String, dynamic> toJson() => {
    'name': name,
    'address_line_1': line1,
    'address_line_2': line2,
    'city': city,
    'state_code': stateCode,
    'country_code': countryCode,
    'postal_code': postalCode,
    'timezone': timezone,
  };
}

class OrganizationDraft {
  const OrganizationDraft({
    required this.name,
    required this.phone,
    required this.currency,
    required this.location,
  });
  final String name, phone, currency;
  final LocationDraft location;
  Map<String, dynamic> toJson() => {
    'name': name,
    'contact_phone': phone,
    'currency': currency,
    'location': location.toJson(),
  };
}
