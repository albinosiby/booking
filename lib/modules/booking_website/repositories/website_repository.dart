import '../models/website_settings.dart';
import '../../../utils/services/logo_picker_service.dart';

abstract interface class WebsiteRepository {
  Future<WebsiteSettings> settings();
  Future<WebsiteSettings> save(WebsiteSettings draft);
  Future<WebsiteSettings> publication(String action, int version);
  Future<String> preview();
  Future<LogoSelection?> pickImage();
  Future<WebsiteSettings> uploadImage(
    LogoSelection image,
    int version, {
    String? businessId,
    String? resourceId,
  });
  Future<WebsiteSettings> removeImage(String id, int version);
  Future<void> open(String url);
  Future<void> copy(String url);
}
