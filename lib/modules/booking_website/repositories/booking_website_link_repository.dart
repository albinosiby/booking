import '../../../utils/services/rest_api_service.dart';
import '../models/booking_website_link.dart';
import 'website_link_actions.dart';

abstract interface class BookingWebsiteLinkRepository {
  Future<BookingWebsiteLink> load();
  Future<void> open(String url);
  Future<void> copy(String url);
}

class RestBookingWebsiteLinkRepository implements BookingWebsiteLinkRepository {
  RestBookingWebsiteLinkRepository(this.api);
  final RestApiService api;
  @override
  Future<BookingWebsiteLink> load() async => BookingWebsiteLink.fromJson(
    Map<String, dynamic>.from(await api.request('/booking-website/link')),
  );
  @override
  Future<void> open(String url) => openWebsiteLink(url);
  @override
  Future<void> copy(String url) => copyWebsiteLink(url);
}
