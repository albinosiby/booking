import '../models/hall_configuration.dart';

abstract interface class HallRepository {
  Future<void> save(
    String businessId,
    int version,
    HallConfiguration configuration,
  );
  Future<void> activate(String businessId);
}
