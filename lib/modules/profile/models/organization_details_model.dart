import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// Backend-neutral, read-only organization details presented by ProfileCubit.
class OrganizationDetailsModel extends Equatable {
  OrganizationDetailsModel({
    required this.name,
    required this.phone,
    required this.currency,
    required this.ownerName,
    required this.ownerEmail,
    this.logo,
    Iterable<OrganizationLocationDetails> locations = const [],
  }) : locations = List.unmodifiable(locations);

  final String name, phone, currency, ownerName, ownerEmail;
  final Uint8List? logo;
  final List<OrganizationLocationDetails> locations;

  @override
  List<Object?> get props => [
    name,
    phone,
    currency,
    ownerName,
    ownerEmail,
    logo,
    locations,
  ];
}

class OrganizationLocationDetails extends Equatable {
  const OrganizationLocationDetails({
    required this.id,
    required this.name,
    required this.addressLine1,
    required this.addressLine2,
    required this.city,
    required this.state,
    required this.country,
    required this.pincode,
    required this.timezone,
  });

  final String id,
      name,
      addressLine1,
      addressLine2,
      city,
      state,
      country,
      pincode,
      timezone;

  @override
  List<Object?> get props => [
    id,
    name,
    addressLine1,
    addressLine2,
    city,
    state,
    country,
    pincode,
    timezone,
  ];
}

class OrganizationLogoSelection {
  const OrganizationLogoSelection(this.bytes, this.contentType);
  final Uint8List bytes;
  final String contentType;
}
