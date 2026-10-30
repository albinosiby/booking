import 'dart:typed_data';
import '../models/website_settings.dart';
import '../../../utils/services/logo_picker_service.dart';

abstract interface class WebsiteRepository {
  Future<WebsiteSettings> settings();
  Future<WebsiteSettings> save(WebsiteSettings draft);
  Future<WebsiteSettings> publication(String action, int version);
  Future<String> preview();

  /// Loads one saved photo on demand, independently of settings and mutations.
  Future<Uint8List> photoBytes(String id, {bool refresh = false});
  void clearPhotoCache();

  /// Selects and prepares a bounded JPEG locally; does not persist anything.
  Future<LogoSelection?> pickImage();

  /// [kind] is `hero`, `logo`, `card` (needs [businessId]) or `space` (needs both ids).
  Future<WebsiteSettings> uploadImage(
    LogoSelection image,
    int version, {
    required String kind,
    String? businessId,
    String? resourceId,
  });
  Future<WebsiteSettings> removeImage(String id, int version);
  Future<void> open(String url);
  Future<void> copy(String url);
}
