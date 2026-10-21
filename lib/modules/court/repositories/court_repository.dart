import '../../pool/models/pool_configuration.dart' show PoolCoach;
import '../models/court_configuration.dart';

abstract interface class CourtRepository {
  Future<void> save(
    String businessId,
    int version,
    CourtConfiguration configuration,
  );
  Future<void> activate(String businessId);

  /// Team members who coach in [businessId].
  Future<List<PoolCoach>> loadCoaches(String businessId);
}
