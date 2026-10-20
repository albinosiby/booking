import '../models/pool_configuration.dart';

abstract interface class PoolRepository {
  Future<void> save(
    String businessId,
    int version,
    PoolConfiguration configuration,
  );
  Future<void> activate(String businessId);
  Future<List<PoolCoach>> loadCoaches(String businessId);
}
