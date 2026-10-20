import '../../../constants/api_path.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/turf_configuration.dart';
import 'turf_repository.dart';

class RestTurfRepository implements TurfRepository {
  RestTurfRepository(this.api);
  final RestApiService api;
  @override
  Future<void> save(
    String id,
    int version,
    TurfConfiguration configuration,
  ) async {
    await api.request(
      '${ApiPath.businesses}/$id/turf-configuration',
      method: 'PATCH',
      data: {'version': version, 'configuration': configuration.toJson()},
    );
  }

  @override
  Future<void> activate(String id) async {
    await api.request('${ApiPath.businesses}/$id/activate', method: 'POST');
  }
}
