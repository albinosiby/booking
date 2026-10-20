import '../../../constants/api_path.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/pool_configuration.dart';
import 'pool_repository.dart';

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
  Future<List<PoolCoach>> loadCoaches(String businessId) async {
    final json = await api.request('/team');
    final coaches = <PoolCoach>[];
    for (final member in json['members'] as List) {
      if (member['active'] != true) continue;
      final owner = member['role'] == 'owner';
      final assignments = member['assignments'] as List;
      final assignment = assignments
          .where((a) => a['business_id'] == businessId)
          .firstOrNull;
      if (!owner && assignment == null) continue;
      coaches.add(
        PoolCoach(
          id: member['id'],
          name: member['display_name'],
          owner: owner,
          poolIds: owner ? [] : List<String>.from(assignment['resource_ids']),
        ),
      );
    }
    return List.unmodifiable(coaches);
  }
}
