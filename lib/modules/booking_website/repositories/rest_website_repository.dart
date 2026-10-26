import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'website_photo_encoder.dart';
import '../../../utils/services/logo_picker_service.dart';
import 'website_link_actions.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/website_settings.dart';
import 'website_repository.dart';

/// Owners often paste `instagram.com/venue`; the API only accepts full https links.
String normaliseSocialLink(String value) {
  final v = value.trim();
  if (v.isEmpty || v.contains('://')) return v;
  return 'https://$v';
}

class RestWebsiteRepository implements WebsiteRepository {
  RestWebsiteRepository(this.api);
  final RestApiService api;
  final _imageBytes = <String, Uint8List>{};
  String? _imageScope;
  Future<WebsiteSettings> _map(dynamic value) async {
    final v = Map<String, dynamic>.from(value as Map);
    final businesses = (v['businesses'] as List)
        .map((raw) {
          final b = Map<String, dynamic>.from(raw as Map);
          return WebsiteBusiness(
            id: b['id'] as String,
            name: b['name'] as String,
            type: b['type'] as String,
            status: b['status'] as String,
            enabled: b['enabled'] == true,
            description: b['card_description'] as String? ?? '',
            spaces: List.unmodifiable(
              (b['resources'] as List? ?? []).map(
                (r) => WebsiteSpace(
                  id: r['id'] as String,
                  name: r['name'] as String,
                  visible: r['visible'] != false,
                  noticeMinutes: r['notice_minutes'] as int?,
                  advanceDays: r['advance_days'] as int?,
                  rules: r['rules'] as String? ?? '',
                  paymentRequired: r['payment_required'] == true,
                  paymentPercentages: List<int>.unmodifiable(
                    (r['payment_percentages'] as List? ?? []).cast<int>(),
                  ),
                ),
              ),
            ),
          );
        })
        .toList(growable: false);
    if (_imageScope != v['id']) {
      _imageBytes.clear();
      _imageScope = v['id'] as String?;
    }
    final images = await Future.wait(
      (v['images'] as List? ?? []).map((raw) async {
        final id = raw['id'] as String;
        final bytes =
            _imageBytes[id] ??
            Uint8List.fromList(
              await api.bytes(
                '/booking-website/images/$id',
                errorMessage: 'Could not load the website photo.',
              ),
            ).asUnmodifiableView();
        _imageBytes[id] = bytes;
        return WebsiteImage(
          id: id,
          kind: raw['kind'] as String,
          businessId: raw['business_id'] as String?,
          resourceId: raw['resource_id'] as String?,
          bytes: bytes,
        );
      }),
    );
    _imageBytes.removeWhere((id, _) => !images.any((i) => i.id == id));
    return WebsiteSettings(
      version: v['version'] as int,
      slug: v['slug'] as String,
      title: v['title'] as String,
      description: v['description'] as String,
      phone: v['contact_phone'] as String,
      instructions: v['instructions'] as String,
      cancellationPolicy: v['cancellation_policy'] as String,
      status: v['status'] as String,
      publishLogo: v['publish_logo'] == true,
      noticeMinutes: v['notice_minutes'] as int,
      advanceDays: v['advance_days'] as int,
      heroHeading: v['hero_heading'] as String? ?? '',
      socialLinks: Map.unmodifiable({
        for (final e in Map<String, dynamic>.from(
          v['social_links'] as Map? ?? {},
        ).entries)
          if (websiteSocialNetworks.containsKey(e.key) && e.value is String)
            e.key: e.value as String,
      }),
      domain: v['domain'] as String?,
      businesses: List.unmodifiable(businesses),
      businessIds: List.unmodifiable(
        businesses.where((b) => b.enabled).map((b) => b.id),
      ),
      url: v['url'] as String?,
      images: List.unmodifiable(images),
    );
  }

  @override
  Future<WebsiteSettings> settings() async =>
      _map(await api.request('/booking-website'));
  @override
  Future<WebsiteSettings> save(WebsiteSettings d) async => _map(
    await api.request(
      '/booking-website',
      method: 'PUT',
      data: {
        'version': d.version,
        'slug': d.slug.trim(),
        'title': d.title.trim(),
        'description': d.description.trim(),
        'contact_phone': d.phone.trim(),
        'instructions': d.instructions.trim(),
        'cancellation_policy': d.cancellationPolicy.trim(),
        'publish_logo': d.publishLogo,
        'notice_minutes': d.noticeMinutes,
        'advance_days': d.advanceDays,
        'hero_heading': d.heroHeading.trim(),
        'social_links': {
          for (final key in websiteSocialNetworks.keys)
            key: normaliseSocialLink(d.socialLinks[key] ?? ''),
        },
        'card_descriptions': {
          for (final b in d.businesses)
            if (d.businessIds.contains(b.id)) b.id: b.description.trim(),
        },
        'spaces': [
          for (final b in d.businesses)
            for (final s in b.spaces)
              {
                'business_id': b.id,
                'resource_id': s.id,
                'visible': s.visible,
                'notice_minutes': s.noticeMinutes,
                'advance_days': s.advanceDays,
                'rules': s.rules.trim(),
                'payment_required': s.paymentRequired,
                'payment_percentages': s.paymentPercentages,
              },
        ],
        'business_ids': d.businessIds,
      },
    ),
  );
  @override
  Future<WebsiteSettings> publication(String action, int version) async {
    if (!const ['publish', 'pause', 'unpublish'].contains(action)) {
      throw const AppException('Unknown website action.');
    }
    return _map(
      await api.request(
        '/booking-website/$action',
        method: 'POST',
        data: {'version': version},
      ),
    );
  }

  @override
  Future<LogoSelection?> pickImage() async {
    final selected = await LogoPickerService().pick(
      maxBytes: websitePhotoSourceMaxBytes,
    );
    if (selected == null) return null;
    final bytes = await compute(encodeWebsitePhoto, selected);
    return LogoSelection(bytes, 'image/jpeg');
  }

  @override
  Future<WebsiteSettings> uploadImage(
    LogoSelection image,
    int version, {
    required String kind,
    String? businessId,
    String? resourceId,
  }) async => _map(
    await api.request(
      '/booking-website/images',
      method: 'POST',
      data: {
        'version': version,
        'kind': kind,
        'business_id': ?businessId,
        'resource_id': ?resourceId,
        'content_type': image.contentType,
        'base64': base64Encode(image.bytes),
      },
    ),
  );
  @override
  Future<WebsiteSettings> removeImage(String id, int version) async => _map(
    await api.request(
      '/booking-website/images/$id/remove',
      method: 'POST',
      data: {'version': version},
    ),
  );
  @override
  Future<String> preview() async =>
      (await api.request('/booking-website/preview', method: 'POST'))['url']
          as String;
  @override
  Future<void> open(String url) async {
    await openWebsiteLink(url);
  }

  @override
  Future<void> copy(String url) => copyWebsiteLink(url);
}
