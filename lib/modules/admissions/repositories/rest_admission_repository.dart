import '../../bookings/repositories/booking_repository.dart';
import '../../../utils/services/rest_api_service.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../bookings/models/booking_models.dart';
import '../models/admission_models.dart';
import 'admission_repository.dart';

class RestAdmissionRepository
    implements AdmissionRepository, MembershipActions {
  RestAdmissionRepository(this.api, this.bookings);
  final BookingRepository bookings;
  final RestApiService api;
  @override
  Future<AdmissionPage> expiredMembers({int cursor = 0}) async {
    final response = await api.request('/admissions/expired?cursor=$cursor');
    return AdmissionPage(
      List<Admission>.unmodifiable((response['items'] as List).map(decode)),
      response['next_cursor'],
    );
  }

  @override
  Future<void> deleteMembership(
    Admission admission,
    String reason,
    String key,
  ) async {
    await api.request(
      '/admissions/${admission.id}/delete',
      method: 'POST',
      data: {
        'command_key': key,
        'version': admission.version,
        'reason': reason,
      },
    );
  }

  @override
  Stream<void> get changes => api.readUpdates
      .where((p) => p == '*' || p.startsWith('/admissions'))
      .map((_) {});
  @override
  Future<void> warmPlans() async {
    await api.retainedRead('/admissions/catalog');
  }

  @override
  Future<AdmissionCatalog> catalog() async {
    final results = await Future.wait<dynamic>([
      api.retainedRead('/admissions/catalog'),
      bookings.catalog(),
    ]);
    final j = results[0];
    return AdmissionCatalog(
      paymentCatalog: results[1] as BookingCatalog,
      currency: j['currency'],
      canManage: j['can_manage'],
      canAttend: j['can_attend'],
      canCollect: j['can_collect'],
      owner: j['is_owner'],
      businesses: List.unmodifiable(
        (j['businesses'] as List).map(
          (b) => AdmissionBusiness(
            b['id'],
            b['name'],
            b['today'],
            b['timezone'],
            List.unmodifiable(
              (b['pools'] as List).map(
                (p) => AdmissionPool(
                  p['id'],
                  p['name'],
                  List<int>.unmodifiable(p['durations']),
                  p['default_duration_minutes'],
                ),
              ),
            ),
            List.unmodifiable(
              (b['plans'] as List).map(
                (p) => AdmissionPlan(
                  p['id'],
                  p['name'],
                  p['kind'],
                  List<String>.unmodifiable(p['pool_ids']),
                  p['allowance'],
                  p['price_minor'] ?? 0,
                  p['class_duration_minutes'],
                  p['coach_name'],
                  expiryMode: p['expiry_mode'],
                  expiryDays: p['expiry_days'],
                  expiryMonths: p['expiry_months'],
                  expiryYears: p['expiry_years'],
                  expiryDate: p['expiry_date'],
                  seats: p['class_seats'],
                  activeCount: p['active_count'],
                  trackAttendance: p['track_attendance'] != false,
                ),
              ),
            ),
            spaceKind: b['space_kind'] ?? 'pool',
          ),
        ),
      ),
    );
  }

  @override
  Future<List<BookingCustomer>> customers(String query) async {
    final j = await api.request(
      Uri(
        path: '/admissions/customers',
        queryParameters: {'q': query},
      ).toString(),
    );
    return List.unmodifiable(
      (j['items'] as List).map(
        (v) => BookingCustomer.fromJson(Map<String, dynamic>.from(v)),
      ),
    );
  }

  @override
  Future<void> sessionChange(
    Admission a,
    AdmissionVisit v,
    String action,
    String reason,
    String key, {
    String? date,
    String? time,
  }) async {
    await api.request(
      '/admissions/${a.id}/sessions/${v.id}/change',
      method: 'POST',
      data: {
        'command_key': key,
        'version': v.version,
        'action': action,
        'reason': reason,
        'date': ?date,
        'time': ?time,
      },
    );
  }

  Admission decode(dynamic j) => Admission(
    deletedAt: j['deleted_at'],
    deletedBy: j['deleted_by'],
    deletionReason: j['deletion_reason'] ?? '',
    id: j['id'],
    reference: j['reference'],
    businessId: j['business_id'],
    poolId: j['resource_id'],
    planId: j['plan_id'],
    customer: BookingCustomer.fromJson({
      ...Map<String, dynamic>.from(j['customer_snapshot']),
      'id': j['customer_id'],
    }),
    planName: j['plan_snapshot']['name'],
    kind: j['plan_snapshot']['kind'],
    coach: j['plan_snapshot']['coach_name'] ?? 'Unassigned',
    mode: j['mode'],
    status: j['status'],
    start: j['starts_on'].toString().substring(0, 10),
    expiry: j['expires_on'].toString().substring(0, 10),
    allowance: j['allowance'],
    used: j['used'],
    remaining: j['remaining'],
    total: j['total_minor'],
    paid: j['net_paid_minor'],
    balance: j['balance_minor'],
    version: j['version'],
    duration: j['schedule']['duration_minutes'],
    time: j['schedule']['time'],
    weekdays: List<int>.unmodifiable(j['schedule']['weekdays']),
    businessName: j['business_name'] ?? '',
    poolName: j['space_name'] ?? '',
    today: j['today'] ?? '',
    localNow: j['local_now'] ?? '',
    canMarkAttendance: j['can_attend'] == true,
    renewalId: j['renewal_id'],
    visits: List.unmodifiable(
      (j['sessions'] as List? ?? []).map(
        (s) => AdmissionVisit(
          id: s['id'],
          start: s['local_start'],
          end: s['local_end'],
          startsAt: s['starts_at'],
          endsAt: s['ends_at'],
          status: s['status'],
          attendance: s['admission_attendance'],
          version: s['version'],
          waived: s['admission_waived'],
          replacementId: s['replacement_id'],
        ),
      ),
    ),
    payments: List.unmodifiable(
      (j['payments'] as List? ?? []).map(
        (p) => BookingPayment.fromJson(Map<String, dynamic>.from(p)),
      ),
    ),
    history: List.unmodifiable(
      (j['history'] as List? ?? []).map(
        (h) => AdmissionEvent(
          h['action'],
          h['created_at'],
          h['actor_name'] ?? h['actor_id'],
          h['details']['reason'] ?? '',
        ),
      ),
    ),
  );
  @override
  Future<AdmissionPage> list({
    String query = '',
    String kind = 'swimming',
    String? status,
    String? businessId,
    String? spaceId,
    String? planId,
    bool previousPlans = false,
    int cursor = 0,
  }) async {
    final uri = Uri(
      path: '/admissions',
      queryParameters: {
        'q': query,
        'kind': kind,
        'status': ?status,
        'business_id': ?businessId,
        'resource_id': ?spaceId,
        'plan_id': ?planId,
        if (previousPlans) 'previous_plans': 'true',
        'cursor': '$cursor',
      },
    );
    final j = await api.retainedRead(uri.toString());
    return AdmissionPage(
      List.unmodifiable((j['items'] as List).map(decode)),
      j['next_cursor'],
    );
  }

  @override
  Future<Admission> detail(String id) async =>
      decode(await api.retainedRead('/admissions/$id'));
  Map<String, dynamic> body(AdmissionDraft d) {
    if (d.amount != null && d.amountMinor == null) {
      throw const AppException('Enter a valid plan amount.');
    }
    return {
      'business_id': d.businessId,
      'resource_id': d.poolId,
      'plan_id': d.planId,
      'starts_on': d.start,
      'mode': d.mode,
      'weekdays': d.mode == 'fixed' ? d.weekdays : <int>[],
      'time': d.time,
      'duration_minutes': d.duration,
      'customer': d.customer.toJson(),
      'payments': d.payments
          .where((p) => !p.isBlank)
          .map((p) => p.toJson())
          .toList(),
      'renewed_from': d.renewedFrom,
      if (d.amount != null) 'plan_amount_minor': d.amountMinor,
    };
  }

  @override
  Future<AdmissionPreview> preview(AdmissionDraft d) async {
    final j = await api.request(
      '/admissions/preview',
      method: 'POST',
      readOnly: true,
      data: body(d),
    );
    return AdmissionPreview(
      j['preview_token'],
      j['expires_on'],
      j['total_minor'],
      List<String>.unmodifiable(
        (j['sessions'] as List).map(
          (s) => '${s['local_start']} – ${s['local_end']}',
        ),
      ),
    );
  }

  @override
  Future<String> create(
    AdmissionDraft d,
    AdmissionPreview p,
    String key,
  ) async => (await api.request(
    '/admissions',
    method: 'POST',
    data: {...body(d), 'preview_token': p.token, 'command_key': key},
  ))['id'];
  @override
  Future<void> checkIn(Admission a, String key) async {
    await api.request(
      '/admissions/${a.id}/check-ins',
      method: 'POST',
      data: {'command_key': key, 'version': a.version},
    );
  }

  @override
  Future<void> attendance(
    Admission a,
    AdmissionVisit v,
    String attendance,
    String reason,
    String key,
  ) async {
    await api.request(
      '/admissions/${a.id}/sessions/${v.id}/attendance',
      method: 'POST',
      data: {
        'command_key': key,
        'version': v.version,
        'attendance': attendance,
        'reason': reason,
      },
    );
  }

  @override
  Future<void> payments(
    Admission a,
    List<BookingPaymentDraft> payments,
    String kind,
    String reason,
    String key,
  ) async {
    await api.request(
      '/admissions/${a.id}/payments',
      method: 'POST',
      data: {
        'command_key': key,
        'version': a.version,
        'kind': kind,
        'reason': reason,
        'payments': payments.map((p) => p.toJson()).toList(),
      },
    );
  }

  @override
  Future<void> cancel(Admission a, String reason, String key) async {
    await api.request(
      '/admissions/${a.id}/cancel',
      method: 'POST',
      data: {'command_key': key, 'version': a.version, 'reason': reason},
    );
  }
}
