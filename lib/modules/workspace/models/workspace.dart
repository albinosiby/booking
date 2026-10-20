import 'dart:typed_data';
import 'package:equatable/equatable.dart';

enum BusinessType {
  turf('turf', 'Turf'),
  pool('pool', 'Swimming Pool'),
  badminton('badminton', 'Badminton Court'),
  tennis('tennis', 'Tennis Court'),
  basketball('basketball', 'Basketball Court'),
  hall('hall', 'Party Hall');

  const BusinessType(this.code, this.label);
  final String code, label;
  static BusinessType fromCode(String code) =>
      values.firstWhere((v) => v.code == code);
}

class Resource extends Equatable {
  const Resource({
    required this.id,
    required this.name,
    required this.capacity,
  });
  final String id, name;
  final int capacity;
  factory Resource.fromJson(Map<String, dynamic> j) =>
      Resource(id: j['id'], name: j['name'], capacity: j['capacity']);
  @override
  List<Object?> get props => [id, name, capacity];
}

class Business extends Equatable {
  const Business({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.locationId,
    required this.version,
    required this.resources,
    this.configuration,
    this.displayOrder = 0,
  });
  final String id, name, status, locationId;
  final BusinessType type;
  final int version, displayOrder;
  final List<Resource> resources;
  final Map<String, dynamic>? configuration;
  bool get ready => status == 'ready';
  factory Business.fromJson(Map<String, dynamic> j) => Business(
    id: j['id'],
    name: j['name'],
    type: BusinessType.fromCode(j['type']),
    status: j['status'],
    locationId: j['location_id'],
    version: j['version'],
    displayOrder: j['display_order'] ?? 0,
    resources: List.unmodifiable(
      (j['resources'] as List).map(
        (r) => Resource.fromJson(Map<String, dynamic>.from(r)),
      ),
    ),
    configuration: j['configuration'] == null
        ? null
        : Map.unmodifiable(Map<String, dynamic>.from(j['configuration'])),
  );
  @override
  List<Object?> get props => [
    id,
    name,
    type,
    status,
    locationId,
    version,
    displayOrder,
    resources,
    configuration,
  ];
}

class Organization extends Equatable {
  const Organization({
    required this.id,
    required this.name,
    required this.phone,
    required this.currency,
    this.logoKey,
    this.businessOrderRevision = 0,
  });
  final String id, name, phone, currency;
  final String? logoKey;
  final int businessOrderRevision;
  factory Organization.fromJson(Map<String, dynamic> j) => Organization(
    id: j['id'],
    name: j['name'],
    phone: j['contact_phone'],
    currency: j['currency'],
    logoKey: j['logo_storage_key'],
    businessOrderRevision: j['business_order_revision'] ?? 0,
  );
  @override
  List<Object?> get props => [
    id,
    name,
    phone,
    currency,
    logoKey,
    businessOrderRevision,
  ];
}

class Workspace extends Equatable {
  const Workspace({
    this.organization,
    this.membership,
    this.businesses = const [],
    this.locations = const [],
    this.logo,
  });
  final Organization? organization;
  final Map<String, dynamic>? membership;
  final List<Business> businesses;
  final List<Map<String, dynamic>> locations;
  final Uint8List? logo;
  Workspace withLogo(Uint8List? bytes) => Workspace(
    organization: organization,
    membership: membership,
    businesses: businesses,
    locations: locations,
    logo: bytes,
  );
  bool get isOwner => membership?['role'] == 'owner';
  bool hasPermission(String permission) =>
      isOwner ||
      (membership?['permissions'] as List? ?? []).contains(permission);
  factory Workspace.fromJson(Map<String, dynamic> j, {Uint8List? logo}) =>
      Workspace(
        organization: j['organization'] == null
            ? null
            : Organization.fromJson(j['organization']),
        membership: j['membership'] == null
            ? null
            : Map.unmodifiable(Map<String, dynamic>.from(j['membership'])),
        businesses: List.unmodifiable(
          (j['businesses'] as List).map(
            (b) => Business.fromJson(Map<String, dynamic>.from(b)),
          ),
        ),
        locations: List.unmodifiable(
          (j['locations'] as List).map(
            (l) => Map<String, dynamic>.unmodifiable(l),
          ),
        ),
        logo: logo,
      );
  @override
  List<Object?> get props => [
    organization,
    membership,
    businesses,
    locations,
    logo,
  ];
}

class CatalogOption extends Equatable {
  const CatalogOption(this.code, this.name);
  final String code, name;
  factory CatalogOption.fromJson(Map<String, dynamic> j) =>
      CatalogOption(j['code'], j['name']);
  @override
  List<Object?> get props => [code, name];
}
