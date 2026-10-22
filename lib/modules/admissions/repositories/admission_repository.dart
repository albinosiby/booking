import '../models/admission_models.dart';
import '../../bookings/models/booking_models.dart';

abstract class AdmissionRepository {
  Stream<void> get changes;
  Future<AdmissionCatalog> catalog();
  Future<void> warmPlans();
  Future<List<BookingCustomer>> customers(String query);
  Future<AdmissionPage> list({
    String query = '',
    String kind = 'swimming',
    String? status,
    String? businessId,
    String? spaceId,
    String? planId,
    bool previousPlans = false,
    int cursor = 0,
  });
  Future<Admission> detail(String id);
  Future<AdmissionPreview> preview(AdmissionDraft draft);
  Future<String> create(
    AdmissionDraft draft,
    AdmissionPreview preview,
    String key,
  );
  Future<void> checkIn(Admission a, String time, int duration, String key);
  Future<void> attendance(
    Admission a,
    AdmissionVisit v,
    String attendance,
    String reason,
    String key,
  );
  Future<void> sessionChange(
    Admission a,
    AdmissionVisit v,
    String action,
    String reason,
    String key, {
    String? date,
    String? time,
  });
  Future<void> payments(
    Admission a,
    List<BookingPaymentDraft> payments,
    String kind,
    String reason,
    String key,
  );
  Future<void> cancel(Admission a, String reason, String key);
}
