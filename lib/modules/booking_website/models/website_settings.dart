import 'dart:typed_data';
import 'package:equatable/equatable.dart';

/// A booking space and its website overrides. Null rules use the website defaults.
class WebsiteSpace extends Equatable {
  const WebsiteSpace({
    required this.id,
    required this.name,
    this.visible = true,
    this.noticeMinutes,
    this.advanceDays,
    this.rules = '',
  });
  final String id, name, rules;
  final bool visible;
  final int? noticeMinutes, advanceDays;
  bool get customised =>
      !visible || noticeMinutes != null || advanceDays != null || rules != '';
  WebsiteSpace copyWith({
    bool? visible,
    int? Function()? noticeMinutes,
    int? Function()? advanceDays,
    String? rules,
  }) => WebsiteSpace(
    id: id,
    name: name,
    visible: visible ?? this.visible,
    noticeMinutes: noticeMinutes == null ? this.noticeMinutes : noticeMinutes(),
    advanceDays: advanceDays == null ? this.advanceDays : advanceDays(),
    rules: rules ?? this.rules,
  );

  /// Copies only the booking rules, keeping identity and visibility.
  WebsiteSpace withRulesOf(WebsiteSpace source) => copyWith(
    noticeMinutes: () => source.noticeMinutes,
    advanceDays: () => source.advanceDays,
    rules: source.rules,
  );
  @override
  List<Object?> get props => [
    id,
    name,
    visible,
    noticeMinutes,
    advanceDays,
    rules,
  ];
}

class WebsiteImage extends Equatable {
  const WebsiteImage({
    required this.id,
    required this.kind,
    this.businessId,
    this.resourceId,
    this.bytes,
  });

  /// `hero`, `logo`, `card` (service card on the homepage) or `space` (booking page gallery).
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
    this.description = '',
    this.spaces = const [],
  });
  final String id, name, type, status, description;
  final bool enabled;
  final List<WebsiteSpace> spaces;
  WebsiteBusiness copyWith({String? description, List<WebsiteSpace>? spaces}) =>
      WebsiteBusiness(
        id: id,
        name: name,
        type: type,
        status: status,
        enabled: enabled,
        description: description ?? this.description,
        spaces: List.unmodifiable(spaces ?? this.spaces),
      );
  @override
  List<Object?> get props => [
    id,
    name,
    type,
    status,
    enabled,
    description,
    spaces,
  ];
}

const websiteSocialNetworks = {
  'instagram': 'Instagram',
  'facebook': 'Facebook',
  'x': 'X (Twitter)',
  'youtube': 'YouTube',
  'linkedin': 'LinkedIn',
  'whatsapp': 'WhatsApp',
};

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
    this.heroHeading = '',
    this.socialLinks = const {},
    this.domain,
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
      status,
      heroHeading;
  final bool publishLogo, addressLocked;

  /// Wildcard domain, e.g. `bookingos.online`; null when the API uses path links.
  final String? domain, url;
  final Map<String, String> socialLinks;
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
    String? heroHeading,
    Map<String, String>? socialLinks,
    bool? publishLogo,
    int? noticeMinutes,
    int? advanceDays,
    List<WebsiteBusiness>? businesses,
    List<String>? businessIds,
  }) => WebsiteSettings(
    version: version,
    slug: slug ?? this.slug,
    title: title ?? this.title,
    description: description ?? this.description,
    phone: phone ?? this.phone,
    instructions: instructions ?? this.instructions,
    cancellationPolicy: cancellationPolicy ?? this.cancellationPolicy,
    heroHeading: heroHeading ?? this.heroHeading,
    socialLinks: Map.unmodifiable(socialLinks ?? this.socialLinks),
    status: status,
    publishLogo: publishLogo ?? this.publishLogo,
    noticeMinutes: noticeMinutes ?? this.noticeMinutes,
    advanceDays: advanceDays ?? this.advanceDays,
    addressLocked: addressLocked,
    businesses: List.unmodifiable(businesses ?? this.businesses),
    businessIds: List.unmodifiable(businessIds ?? this.businessIds),
    domain: domain,
    url: url,
    images: images,
  );

  /// The address visitors will use once saved, e.g. `https://eden.bookingos.online`.
  String? get draftUrl => domain == null
      ? url
      : '${domain!.startsWith('localhost') ? 'http' : 'https'}://$slug.$domain';
  WebsiteImage? image(String kind, {String? businessId, String? resourceId}) =>
      images
          .where(
            (i) =>
                i.kind == kind &&
                i.businessId == businessId &&
                i.resourceId == resourceId,
          )
          .firstOrNull;
  @override
  List<Object?> get props => [
    version,
    slug,
    title,
    description,
    phone,
    instructions,
    cancellationPolicy,
    heroHeading,
    socialLinks,
    status,
    publishLogo,
    noticeMinutes,
    advanceDays,
    addressLocked,
    businesses,
    businessIds,
    images,
    domain,
    url,
  ];
}
