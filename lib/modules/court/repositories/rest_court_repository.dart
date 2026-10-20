import '../../../constants/api_path.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/court_configuration.dart';
import 'court_repository.dart';

class RestCourtRepository implements CourtRepository {
  RestCourtRepository(this.api);
  final RestApiService api;
  @override
  Future<void> save(
    String id,
    int version,
    CourtConfiguration configuration,
  ) async {
    await api.request(
      '${ApiPath.businesses}/$id/court-configuration',
      method: 'PATCH',
      data: {'version': version, 'configuration': configuration.toJson()},
    );
  }

  @override
  Future<void> activate(String id) async {
    await api.request('${ApiPath.businesses}/$id/activate', method: 'POST');
  }
}
