import '../../../constants/api_path.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/hall_configuration.dart';
import 'hall_repository.dart';

class RestHallRepository implements HallRepository {
  RestHallRepository(this.api);
  final RestApiService api;
  @override
  Future<void> save(
    String id,
    int version,
    HallConfiguration configuration,
  ) async {
    await api.request(
      '${ApiPath.businesses}/$id/hall-configuration',
      method: 'PATCH',
      data: {'version': version, 'configuration': configuration.toJson()},
    );
  }

  @override
  Future<void> activate(String id) async {
    await api.request('${ApiPath.businesses}/$id/activate', method: 'POST');
  }
}
