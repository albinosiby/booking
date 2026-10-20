import '../models/turf_configuration.dart';

abstract interface class TurfRepository {
  Future<void> save(
    String businessId,
    int version,
    TurfConfiguration configuration,
  );
  Future<void> activate(String businessId);
}
