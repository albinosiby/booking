import 'package:equatable/equatable.dart';
import '../../bookings/models/booking_models.dart';

class AdmissionPool extends Equatable {
  const AdmissionPool(this.id, this.name, this.durations, this.defaultDuration);
  final String id, name;
  final List<int> durations;
  final int defaultDuration;
  @override
  List<Object?> get props => [id, name, durations, defaultDuration];
}

class AdmissionPlan extends Equatable {
  const AdmissionPlan(
    this.id,
    this.name,
    this.kind,
    this.poolIds,
    this.allowance,
    this.total,
    this.duration,
    this.coach, {
    this.expiryMode,
    this.expiryDays,
    this.expiryMonths,
    this.expiryYears,
    this.expiryDate,
    this.seats,
    this.activeCount,
  });
  final String id, name, kind, coach;

  /// Class size for coaching plans; null for swimming and court plans.
  final int? seats;

  /// Active and upcoming admissions; null when the API predates the count.
  final int? activeCount;
  String get validityLabel => switch (expiryMode) {
    'fixed_date' => 'Until ${expiryDate ?? '—'}',
    'after_months' => '$expiryMonths ${expiryMonths == 1 ? 'month' : 'months'}',
    'after_years' => '$expiryYears ${expiryYears == 1 ? 'year' : 'years'}',
    _ => '$expiryDays days',
  };
  final List<String> poolIds;
  final int allowance, total;
  final int? duration;
  final String? expiryMode, expiryDate;
  final int? expiryDays, expiryMonths, expiryYears;
  String? expiryFor(String start) {
    final date = DateTime.tryParse('${start}T00:00:00Z');
    if (date == null) return null;
    if (expiryMode == 'fixed_date') return expiryDate;
    if (expiryMode == 'after_start' && expiryDays != null) {
      return bookingDate(date.add(Duration(days: expiryDays!)));
    }
    final months = expiryMode == 'after_months'
        ? expiryMonths
        : expiryMode == 'after_years' && expiryYears != null
        ? expiryYears! * 12
        : null;
    if (months == null) return null;
    final target = DateTime.utc(date.year, date.month + months, 1);
    final last = DateTime.utc(target.year, target.month + 1, 0).day;
    return bookingDate(
      DateTime.utc(
        target.year,
        target.month,
        date.day > last ? last : date.day,
      ),
    );
  }

  @override
  List<Object?> get props => [
    id,
    name,
    kind,
    poolIds,
    allowance,
    total,
    duration,
    coach,
    expiryMode,
    expiryDays,
    expiryMonths,
    expiryYears,
    expiryDate,
    seats,
    activeCount,
  ];
}

class AdmissionBusiness extends Equatable {
  const AdmissionBusiness(
    this.id,
    this.name,
    this.today,
    this.timezone,
    this.pools,
    this.plans, {
    this.spaceKind = 'pool',
  });
  final String id, name, today, timezone;

  /// `pool` or `court`; [pools] holds that business's bookable spaces.
  final String spaceKind;
  final List<AdmissionPool> pools;
  final List<AdmissionPlan> plans;
  bool get court => spaceKind == 'court';
  String get spaceLabel => court ? 'Court' : 'Pool';
  @override
  List<Object?> get props => [
    id,
    name,
    today,
    timezone,
    pools,
    plans,
    spaceKind,
  ];
}

class AdmissionCatalog extends Equatable {
  const AdmissionCatalog({
    this.businesses = const [],
    this.currency = 'INR',
    this.canManage = false,
    this.canAttend = false,
    this.canCollect = false,
    this.owner = false,
    this.paymentCatalog = const BookingCatalog(),
  });
  final List<AdmissionBusiness> businesses;
  final String currency;
  final bool canManage, canAttend, canCollect, owner;
  final BookingCatalog paymentCatalog;
  @override
  List<Object?> get props => [
    businesses,
    currency,
    canManage,
    canAttend,
    canCollect,
    owner,
    paymentCatalog,
  ];
}

class AdmissionVisit extends Equatable {
  const AdmissionVisit({
    required this.id,
    required this.start,
    required this.end,
    required this.startsAt,
    required this.endsAt,
    required this.status,
    required this.attendance,
    required this.version,
    this.waived = false,
    this.replacementId,
  });
  final String id, start, end, startsAt, endsAt, status, attendance;
  final int version;
  final bool waived;
  final String? replacementId;
  bool get hasStarted => DateTime.parse(startsAt).isBefore(DateTime.now());
  @override
  List<Object?> get props => [
    id,
    start,
    end,
    startsAt,
    endsAt,
    status,
    attendance,
    version,
    waived,
    replacementId,
  ];
}

class AdmissionEvent extends Equatable {
  const AdmissionEvent(this.action, this.at, this.actor, this.reason);
  final String action, at, actor, reason;
  @override
  List<Object?> get props => [action, at, actor, reason];
}

class Admission extends Equatable {
  const Admission({
    required this.id,
    required this.reference,
    required this.businessId,
    required this.poolId,
    required this.planId,
    required this.customer,
    required this.planName,
    required this.kind,
    required this.coach,
    required this.mode,
    required this.status,
    required this.start,
    required this.expiry,
    required this.allowance,
    required this.used,
    required this.remaining,
    required this.total,
    required this.paid,
    required this.balance,
    required this.version,
    required this.duration,
    required this.time,
    required this.weekdays,
    this.businessName = '',
    this.poolName = '',
    this.today = '',
    this.localNow = '',
    this.renewalId,
    this.visits = const [],
    this.payments = const [],
    this.history = const [],
  });
  final String id,
      reference,
      businessId,
      poolId,
      planId,
      planName,
      kind,
      coach,
      mode,
      status,
      start,
      expiry,
      time,
      businessName,
      poolName,
      today,
      localNow;
  final String? renewalId;
  final BookingCustomer customer;
  final int allowance, used, remaining, total, paid, balance, version, duration;
  final List<int> weekdays;
  final List<AdmissionVisit> visits;
  final List<BookingPayment> payments;
  final List<AdmissionEvent> history;
  bool get canRenew =>
      renewalId == null && ['completed', 'expired'].contains(status);
  bool get canCheckIn =>
      mode == 'flexible' &&
      ['active', 'completed'].contains(status) &&
      today.compareTo(expiry) <= 0 &&
      (remaining > 0 ||
          visits.any(
            (v) =>
                v.attendance == 'present' &&
                v.status != 'cancelled' &&
                v.start.startsWith(today),
          ));
  int get attended => visits
      .where((v) => v.status != 'cancelled' && v.attendance == 'present')
      .length;
  @override
  List<Object?> get props => [
    id,
    version,
    status,
    used,
    remaining,
    paid,
    balance,
    visits,
    payments,
    history,
    renewalId,
  ];
}

class AdmissionPage {
  const AdmissionPage(this.items, this.next);
  final List<Admission> items;
  final int? next;
}

class AdmissionPreview extends Equatable {
  const AdmissionPreview(this.token, this.expiry, this.total, this.sessions);
  final String token, expiry;
  final int total;
  final List<String> sessions;
  @override
  List<Object?> get props => [token, expiry, total, sessions];
}

class AdmissionDraft extends Equatable {
  const AdmissionDraft({
    this.businessId,
    this.poolId,
    this.planId,
    this.customer = const BookingCustomer(),
    this.mode = 'flexible',
    this.start = '',
    this.time = '06:00',
    this.duration = 60,
    this.weekdays = const [],
    this.payments = const [],
    this.renewedFrom,
  });
  final String? businessId, poolId, planId, renewedFrom;
  final String mode, start, time;
  final int duration;
  final BookingCustomer customer;
  final List<int> weekdays;
  final List<BookingPaymentDraft> payments;
  AdmissionDraft copyWith({
    String? businessId,
    String? poolId,
    String? planId,
    BookingCustomer? customer,
    String? mode,
    String? start,
    String? time,
    int? duration,
    List<int>? weekdays,
    List<BookingPaymentDraft>? payments,
    bool resetPlan = false,
  }) => AdmissionDraft(
    businessId: businessId ?? this.businessId,
    poolId: poolId ?? this.poolId,
    planId: resetPlan ? null : planId ?? this.planId,
    customer: customer ?? this.customer,
    mode: mode ?? this.mode,
    start: start ?? this.start,
    time: time ?? this.time,
    duration: duration ?? this.duration,
    weekdays: weekdays ?? this.weekdays,
    payments: payments ?? this.payments,
    renewedFrom: renewedFrom,
  );
  @override
  List<Object?> get props => [
    businessId,
    poolId,
    planId,
    customer,
    mode,
    start,
    time,
    duration,
    weekdays,
    payments,
    renewedFrom,
  ];
}
