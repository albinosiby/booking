import '../../../constants/api_path.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/pool_configuration.dart';
import 'pool_repository.dart';
import '../../team/models/staff_coaches.dart';

class RestPoolRepository implements PoolRepository {
  RestPoolRepository(this.api);
  final RestApiService api;
  @override
  Future<void> save(
    String id,
    int version,
    PoolConfiguration configuration,
  ) async {
    await api.request(
      '${ApiPath.businesses}/$id/pool-configuration',
      method: 'PATCH',
      data: {'version': version, 'configuration': configuration.toJson()},
    );
  }

  @override
  Future<void> activate(String id) async {
    await api.request('${ApiPath.businesses}/$id/activate', method: 'POST');
  }

  @override
  Future<List<PoolCoach>> loadCoaches(String businessId) async =>
      staffCoaches(await api.request(ApiPath.team), businessId);
}
