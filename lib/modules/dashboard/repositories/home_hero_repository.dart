import 'dart:typed_data';
import '../../../utils/services/rest_api_service.dart';

abstract interface class HomeHeroRepository {
  Future<Uint8List?> load();
}

class RestHomeHeroRepository implements HomeHeroRepository {
  RestHomeHeroRepository(this.api);
  final RestApiService api;

  @override
  Future<Uint8List?> load() async {
    final bytes = await api.bytes(
      '/booking-website/home-hero',
      errorMessage: 'Could not load the website hero photo.',
    );
    return bytes.isEmpty
        ? null
        : Uint8List.fromList(bytes).asUnmodifiableView();
  }
}
