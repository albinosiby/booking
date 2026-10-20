import '../models/court_configuration.dart';

abstract interface class CourtRepository {
  Future<void> save(
    String businessId,
    int version,
    CourtConfiguration configuration,
  );
  Future<void> activate(String businessId);
}
