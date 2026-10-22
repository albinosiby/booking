import 'dart:typed_data';
import 'package:equatable/equatable.dart';

class WebsiteSpace extends Equatable {
  const WebsiteSpace({required this.id, required this.name});
  final String id, name;
  @override
  List<Object?> get props => [id, name];
}

class WebsiteImage extends Equatable {
  const WebsiteImage({
    required this.id,
    required this.kind,
    this.businessId,
    this.resourceId,
    this.bytes,
  });
  final String id, kind;
  final String? businessId, resourceId;
  final Uint8List? bytes;
  @override
  List<Object?> get props => [id, kind, businessId, resourceId, bytes];
}

class WebsiteBusiness extends Equatable {
  const WebsiteBusiness({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.enabled,
    this.spaces = const [],
  });
  final String id, name, type, status;
  final bool enabled;
  final List<WebsiteSpace> spaces;
  @override
  List<Object?> get props => [id, name, type, status, enabled, spaces];
}

class WebsiteSettings extends Equatable {
  const WebsiteSettings({
    required this.version,
    required this.slug,
    required this.title,
    required this.description,
    required this.phone,
    required this.instructions,
    required this.cancellationPolicy,
    required this.status,
    required this.publishLogo,
    required this.noticeMinutes,
    required this.advanceDays,
    required this.addressLocked,
    required this.businesses,
    required this.businessIds,
    this.url,
    this.images = const [],
  });
  final int version, noticeMinutes, advanceDays;
  final String slug,
      title,
      description,
      phone,
      instructions,
      cancellationPolicy,
      status;
  final bool publishLogo, addressLocked;
  final String? url;
  final List<WebsiteImage> images;
  final List<WebsiteBusiness> businesses;
  final List<String> businessIds;
  WebsiteSettings copyWith({
    String? slug,
    String? title,
    String? description,
    String? phone,
    String? instructions,
    String? cancellationPolicy,
    bool? publishLogo,
    int? noticeMinutes,
    int? advanceDays,
    List<String>? businessIds,
  }) => WebsiteSettings(
    version: version,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    description: description ?? this.description,
    phone: phone ?? this.phone,
    instructions: instructions ?? this.instructions,
    cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
    status: status,
    publishLogo: publishLogo ?? this.publishLogo,
    noticeMinutes: noticeMinutes ?? this.noticeMinutes,
    advanceDays: advanceDays ?? this.advanceDays,
    addressLocked: addressLocked,
    businesses: businesses,
    businessIds: List.unmodifiable(businessIds ?? this.businessIds),
    url: url,
    images: images,
  );
  @override
  List<Object?> get props => [
    version,
    slug,
    title,
    description,
    phone,
    instructions,
    cancellationPolicy,
    status,
    publishLogo,
    noticeMinutes,
    advanceDays,
    addressLocked,
    businesses,
    businessIds,
    images,
    url,
  ];
}
