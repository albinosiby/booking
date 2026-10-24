import 'booking_discount.dart';
import '../../../utils/helpers/group_size.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/helpers/validation.dart';

String bookingMoney(int amount, String currency) =>
    '$currency ${(amount / 100).toStringAsFixed(2)}';
String bookingDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class BookingOption extends Equatable {
  const BookingOption({
    required this.id,
    required this.name,
    required this.kind,
    required this.durations,
    required this.defaultDuration,
    this.fixedTime,
    this.minimumDuration,
    this.groupMode,
    this.groupPeople,
    this.sport,
    this.format,
  });
  final String id, name, kind;
  final List<int> durations;
  final int defaultDuration;
  final String? fixedTime, groupMode;
  final int? minimumDuration;
  final int? groupPeople;
  String get groupExplanation => groupMode == null || groupPeople == null
      ? ''
      : groupSizeExplanation(groupMode!, groupPeople!);
  final String? sport, format;
  bool acceptsPeople(int people) {
    if (people < 1) return false;
    final limit = groupPeople;
    if (groupMode == null) return true;
    if (limit == null) return false;
    return switch (groupMode) {
      'exact' => people == limit,
      'up_to' => people <= limit,
      'at_least' => people >= limit,
      _ => false,
    };
  }

  factory BookingOption.fromJson(Map<String, dynamic> j) => BookingOption(
    id: j['id'],
    name: j['name'],
    kind: j['kind'],
    durations: List<int>.unmodifiable(j['durations']),
    defaultDuration: j['default_duration'] ?? j['durations'][0],
    fixedTime: j['fixed_time'],
    minimumDuration:
        j['minimum_duration'] ??
        (j['kind'] == 'hourly' && j['group_mode'] == null
            ? j['default_duration'] ?? (j['durations'] as List).first
            : null),
    groupMode: j['group_mode'],
    groupPeople: j['group_people'],
    sport: j['sport'],
    format: j['format'],
  );
  @override
  List<Object?> get props => [
    id,
    name,
    kind,
    durations,
    defaultDuration,
    fixedTime,
    minimumDuration,
    groupMode,
    groupPeople,
    sport,
    format,
  ];
}

class BookingSpace extends Equatable {
  const BookingSpace({
    required this.id,
    required this.name,
    required this.capacity,
    required this.options,
  });
  final String id, name;
  final int capacity;
  final List<BookingOption> options;
  factory BookingSpace.fromJson(Map<String, dynamic> j) => BookingSpace(
    id: j['id'],
    name: j['name'],
    capacity: j['capacity'],
    options: List.unmodifiable(
      (j['options'] as List).map(
        (o) => BookingOption.fromJson(Map<String, dynamic>.from(o)),
      ),
    ),
  );
  @override
  List<Object?> get props => [id, name, capacity, options];
}

class BookingBusiness extends Equatable {
  const BookingBusiness({
    required this.id,
    required this.name,
    required this.type,
    required this.timezone,
    required this.today,
    required this.spaces,
  });
  final String id, name, type, timezone, today;
  final List<BookingSpace> spaces;
  factory BookingBusiness.fromJson(Map<String, dynamic> j) => BookingBusiness(
    id: j['id'],
    name: j['name'],
    type: j['type'],
    timezone: j['timezone'],
    today: j['today'],
    spaces: List.unmodifiable(
      (j['resources'] as List).map(
        (r) => BookingSpace.fromJson(Map<String, dynamic>.from(r)),
      ),
    ),
  );
  @override
  List<Object?> get props => [id, name, type, timezone, today, spaces];
}

class BookingMoneyAccount extends Equatable {
  const BookingMoneyAccount(this.id, this.name, this.kind, this.primary);
  final String id, name, kind;
  final bool primary;
  factory BookingMoneyAccount.fromJson(Map<String, dynamic> j) =>
      BookingMoneyAccount(j['id'], j['name'], j['kind'], j['is_primary']);
  @override
  List<Object?> get props => [id, name, kind, primary];
}

class BookingMoneyRoute extends Equatable {
  const BookingMoneyRoute(this.business, this.space, this.method, this.account);
  final String business, method, account;
  final String? space;
  factory BookingMoneyRoute.fromJson(Map<String, dynamic> j) =>
      BookingMoneyRoute(
        j['business_id'],
        j['resource_id'],
        j['method'],
        j['account_id'],
      );
  @override
  List<Object?> get props => [business, space, method, account];
}

class BookingCatalog extends Equatable {
  const BookingCatalog({
    this.currency = 'INR',
    this.paymentAccounts = const [],
    this.paymentRoutes = const [],
    this.canView = false,
    this.canManage = false,
    this.canCollect = false,
    this.canRefund = false,
    this.canFinance = false,
    this.businesses = const [],
    this.historyBusinesses = const [],
  });
  final String currency;
  final List<BookingMoneyAccount> paymentAccounts;
  final List<BookingMoneyRoute> paymentRoutes;
  String? paymentDestination(String method, String? business, String? space) =>
      method == 'cash'
      ? paymentAccounts.where((a) => a.kind == 'cash').firstOrNull?.id
      : paymentRoutes
                .where(
                  (r) =>
                      r.business == business &&
                      r.space == space &&
                      r.method == method,
                )
                .firstOrNull
                ?.account ??
            paymentRoutes
                .where(
                  (r) =>
                      r.business == business &&
                      r.space == null &&
                      r.method == method,
                )
                .firstOrNull
                ?.account ??
            paymentAccounts.where((a) => a.primary).firstOrNull?.id;
  final bool canView, canManage, canCollect, canRefund, canFinance;
  final List<BookingBusiness> businesses;
  final List<BookingBusiness> historyBusinesses;
  List<BookingBusiness> get filters =>
      historyBusinesses.isEmpty ? businesses : historyBusinesses;
  factory BookingCatalog.fromJson(Map<String, dynamic> j) => BookingCatalog(
    currency: j['currency'],
    paymentAccounts: List.unmodifiable(
      (j['payment_accounts'] as List? ?? []).map(
        (a) => BookingMoneyAccount.fromJson(Map<String, dynamic>.from(a)),
      ),
    ),
    paymentRoutes: List.unmodifiable(
      (j['payment_routes'] as List? ?? []).map(
        (a) => BookingMoneyRoute.fromJson(Map<String, dynamic>.from(a)),
      ),
    ),
    canView: j['can_view'] ?? true,
    canManage: j['can_manage'],
    canCollect: j['can_collect'],
    canRefund: j['can_refund'],
    canFinance: j['can_finance'],
    historyBusinesses: List.unmodifiable(
      (j['filter_businesses'] as List? ?? []).map(
        (b) => BookingBusiness.fromJson(Map<String, dynamic>.from(b)),
      ),
    ),
    businesses: List.unmodifiable(
      (j['businesses'] as List).map(
        (b) => BookingBusiness.fromJson(Map<String, dynamic>.from(b)),
      ),
    ),
  );
  @override
  List<Object?> get props => [
    currency,
    paymentAccounts,
    paymentRoutes,
    canView,
    canManage,
    canCollect,
    canRefund,
    canFinance,
    businesses,
  ];
}

class BookingSelection extends Equatable {
  const BookingSelection({
    required this.businessId,
    required this.resourceId,
    required this.optionId,
    required this.date,
    required this.time,
    required this.duration,
    required this.people,
    this.discount,
  });
  final String businessId, resourceId, optionId, date, time;
  final int duration, people;
  final BookingDiscount? discount;
  Map<String, dynamic> toJson() => {
    'business_id': businessId,
    'resource_id': resourceId,
    'option_id': optionId,
    'date': date,
    'time': time,
    'duration_minutes': duration,
    'people': people,
    if (discount != null) 'discount': discount!.toJson(),
  };
  factory BookingSelection.fromJson(Map<String, dynamic> j) => BookingSelection(
    businessId: j['business_id'],
    resourceId: j['resource_id'],
    optionId: j['option_id'],
    date: j['date'],
    time: j['time'],
    duration: j['duration_minutes'],
    people: j['people'],
    discount: j['discount'] == null
        ? null
        : BookingDiscount.fromJson(Map<String, dynamic>.from(j['discount'])),
  );
  @override
  List<Object?> get props => [
    businessId,
    resourceId,
    optionId,
    date,
    time,
    duration,
    people,
    discount,
  ];
}

class BookingQuote extends Equatable {
  const BookingQuote({
    required this.token,
    required this.total,
    required this.start,
    required this.end,
    required this.timezone,
    required this.businessName,
    required this.spaceName,
    required this.optionName,
    this.remaining,
    this.subtotal,
    this.discountMinor = 0,
    this.localStart = '',
    this.localEnd = '',
  });
  final String localStart, localEnd;
  final int? remaining;
  final String token, start, end, timezone, businessName, spaceName, optionName;
  final int total;
  final int? subtotal;
  final int discountMinor;
  factory BookingQuote.fromJson(Map<String, dynamic> j) => BookingQuote(
    token: j['quote_token'],
    total: j['total_minor'],
    subtotal: j['subtotal_minor'] ?? j['total_minor'],
    discountMinor: j['discount_minor'] ?? 0,
    start: j['starts_at'],
    end: j['ends_at'],
    timezone: j['timezone'],
    businessName: j['business_name'],
    spaceName: j['space_name'],
    optionName: j['option_name'],
    remaining: j['remaining_capacity'],
    localStart: j['local_start'] ?? '',
    localEnd: j['local_end'] ?? '',
  );
  @override
  List<Object?> get props => [
    subtotal,
    discountMinor,
    token,
    total,
    start,
    end,
    timezone,
    businessName,
    spaceName,
    optionName,
    localStart,
    localEnd,
    remaining,
  ];
}

class BookingSlot extends Equatable {
  const BookingSlot(
    this.time,
    this.available,
    this.total, [
    this.remaining,
    this.past = false,
    this.duration,
    this.status,
    this.date,
    this.endOptions,
  ]);
  final List<BookingSlot>? endOptions;
  final int? remaining;
  final int? duration;
  final String? status, date;
  final String time;
  final bool available;
  final bool past;
  bool get selectable => available && !past;
  final int total;
  factory BookingSlot.fromJson(Map<String, dynamic> j) => BookingSlot(
    j['time'],
    j['available'],
    j['total_minor'],
    j['remaining_capacity'],
    j['status'] == 'past',
    j['duration_minutes'],
    j['status'],
    j['date'],
    j['end_options'] == null
        ? null
        : List<BookingSlot>.unmodifiable(
            (j['end_options'] as List).map((value) {
              final end = value as List;
              final stamp = end[1] as String;
              return BookingSlot(
                stamp.substring(11, 16),
                true,
                0,
                null,
                false,
                (end[0] as num).toInt(),
                'available',
                stamp.substring(0, 10),
              );
            }),
          ),
  );
  @override
  List<Object?> get props => [
    time,
    available,
    total,
    remaining,
    past,
    duration,
    status,
    date,
    endOptions,
  ];
}

class BookingCustomer extends Equatable {
  const BookingCustomer({
    this.id,
    this.name = '',
    this.phone = '',
    this.email = '',
  });
  final String? id;
  final String name, phone, email;
  BookingCustomer copyWith({
    String? name,
    String? phone,
    String? email,
    bool clearId = false,
  }) => BookingCustomer(
    id: clearId ? null : id,
    name: name ?? this.name,
    phone: phone ?? this.phone,
    email: email ?? this.email,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name.trim(),
    'phone': phone.trim(),
    'email': email.trim().isEmpty ? null : email.trim(),
  };
  factory BookingCustomer.fromJson(Map<String, dynamic> j) => BookingCustomer(
    id: j['id'],
    name: j['name'],
    phone: j['phone'],
    email: j['email'] ?? '',
  );
  String? validate() => name.trim().length < 2 || name.trim().length > 100
      ? 'Enter a customer name (2–100 characters).'
      : !RegExp(r'^\+?[\d ()-]{7,25}$').hasMatch(phone.trim())
      ? 'Enter a valid phone number.'
      : email.isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email.trim())
      ? 'Enter a valid email or leave it empty.'
      : null;
  @override
  List<Object?> get props => [id, name, phone, email];
}

class BookingPaymentDraft extends Equatable {
  BookingPaymentDraft({
    String? id,
    this.method = 'cash',
    this.accountId,
    this.amount = '',
    this.reference = '',
    DateTime? receivedAt,
  }) : id = id ?? const Uuid().v4(),
       receivedAt = receivedAt ?? DateTime.now();
  final String id, method, amount, reference;
  final DateTime receivedAt;
  final String? accountId;
  bool get isBlank => amount.trim().isEmpty && reference.trim().isEmpty;
  int? get minor => Validation.priceMinor(amount);
  BookingPaymentDraft copyWith({
    String? method,
    String? accountId,
    String? amount,
    String? reference,
    DateTime? receivedAt,
  }) => BookingPaymentDraft(
    id: id,
    method: method ?? this.method,
    accountId: method != null && method != this.method
        ? null
        : accountId ?? this.accountId,
    amount: amount ?? this.amount,
    reference: reference ?? this.reference,
    receivedAt: receivedAt ?? this.receivedAt,
  );
  Map<String, dynamic> toJson() => {
    'method': method,
    if (accountId != null) 'account_id': accountId,
    'amount_minor': minor,
    'reference': reference.trim(),
    'received_at': receivedAt.toUtc().toIso8601String(),
  };
  String? validate() => minor == null || minor! <= 0
      ? 'Enter a positive payment amount.'
      : reference.trim().length > 200
      ? 'Keep payment references under 200 characters.'
      : receivedAt.isAfter(DateTime.now().add(const Duration(minutes: 1)))
      ? 'Payment time cannot be in the future.'
      : null;
  @override
  List<Object?> get props => [
    id,
    method,
    amount,
    reference,
    receivedAt,
    accountId,
  ];
}

class BookingPayment extends Equatable {
  const BookingPayment({
    required this.id,
    required this.kind,
    required this.method,
    required this.amount,
    required this.reference,
    required this.localReceived,
    required this.collector,
    required this.reason,
  });
  final String id, kind, method, reference, localReceived, collector, reason;
  final int amount;
  factory BookingPayment.fromJson(Map<String, dynamic> j) => BookingPayment(
    id: j['id'],
    kind: j['kind'],
    method: j['method'],
    amount: j['amount_minor'],
    reference: j['reference'],
    localReceived: j['local_received'] ?? j['received_at'],
    collector: j['collector_name'] ?? j['recorded_by'],
    reason: j['reason'] ?? '',
  );
  @override
  List<Object?> get props => [
    id,
    kind,
    method,
    amount,
    reference,
    localReceived,
    collector,
    reason,
  ];
}

class BookingEvent extends Equatable {
  const BookingEvent(
    this.action,
    this.actor,
    this.date,
    this.reason,
    this.before,
    this.after,
  );
  final String action, actor, date, reason;
  final String? before, after;
  factory BookingEvent.fromJson(Map<String, dynamic> j) => BookingEvent(
    j['action'],
    j['actor_name'] ?? j['actor_id'],
    j['local_created'] ?? j['created_at'],
    j['details']['reason'] ?? '',
    j['previous_local'] ?? j['details']['previous']?['starts_at'],
    j['current_local'] ?? j['details']['current']?['starts_at'],
  );
  @override
  List<Object?> get props => [action, actor, date, reason, before, after];
}

class BookingRecord extends Equatable {
  const BookingRecord({
    required this.id,
    required this.reference,
    required this.status,
    required this.version,
    required this.selection,
    required this.customer,
    required this.notes,
    required this.total,
    required this.netPaid,
    required this.balance,
    required this.refundDue,
    required this.paymentStatus,
    required this.localStart,
    required this.localEnd,
    required this.startsAt,
    required this.endsAt,
    required this.timezone,
    required this.businessName,
    required this.spaceName,
    required this.optionName,
    this.cleanupMinutes = 5,
    this.admissionId,
    this.admissionAttendance,
    this.subtotal,
    this.discountMinor = 0,
    this.payments = const [],
    this.history = const [],
    this.websitePayment,
  });
  final String id,
      reference,
      status,
      notes,
      paymentStatus,
      localStart,
      localEnd,
      startsAt,
      endsAt,
      timezone,
      businessName,
      spaceName,
      optionName;
  final String? admissionId, admissionAttendance;
  final int version, total, netPaid, balance, refundDue;
  final int cleanupMinutes;
  final int? subtotal;
  final int discountMinor;
  final BookingSelection selection;
  final BookingCustomer customer;
  final List<BookingPayment> payments;
  final List<BookingEvent> history;
  final Map<String, dynamic>? websitePayment;
  bool get checkedIn => history.any((event) => event.action == 'checked_in');
  factory BookingRecord.fromJson(Map<String, dynamic> j) => BookingRecord(
    websitePayment: j['website_payment_submission'] == null
        ? null
        : Map<String, dynamic>.unmodifiable(
            j['website_payment_submission'] as Map,
          ),
    admissionId: j['admission_id'],
    admissionAttendance: j['admission_attendance'],
    id: j['id'],
    reference: j['reference'],
    status: j['status'],
    version: j['version'],
    selection: BookingSelection.fromJson(
      Map<String, dynamic>.from(j['selection']),
    ),
    customer: BookingCustomer.fromJson({
      ...Map<String, dynamic>.from(j['customer_snapshot']),
      'id': j['customer_id'],
    }),
    notes: j['notes'],
    total: j['total_minor'],
    subtotal: j['price_snapshot']['subtotal_minor'] ?? j['total_minor'],
    discountMinor: j['price_snapshot']['discount_minor'] ?? 0,
    netPaid: j['net_paid_minor'],
    balance: j['balance_minor'],
    refundDue: j['refund_due_minor'],
    paymentStatus: j['payment_status'],
    localStart: j['local_start'],
    localEnd: j['local_end'],
    startsAt: j['starts_at'],
    endsAt: j['ends_at'],
    cleanupMinutes:
        (j['price_snapshot']['cleanup_minutes'] as num?)?.toInt() ?? 5,
    timezone: j['price_snapshot']['timezone'],
    businessName: j['price_snapshot']['business_name'],
    spaceName: j['price_snapshot']['space_name'],
    optionName: j['price_snapshot']['option_name'],
    payments: List.unmodifiable(
      (j['payments'] as List? ?? []).map(
        (p) => BookingPayment.fromJson(Map<String, dynamic>.from(p)),
      ),
    ),
    history: List.unmodifiable(
      (j['history'] as List? ?? []).map(
        (p) => BookingEvent.fromJson(Map<String, dynamic>.from(p)),
      ),
    ),
  );
  @override
  List<Object?> get props => [
    id,
    reference,
    status,
    version,
    selection,
    customer,
    notes,
    total,
    netPaid,
    balance,
    refundDue,
    paymentStatus,
    localStart,
    localEnd,
    startsAt,
    endsAt,
    timezone,
    businessName,
    spaceName,
    optionName,
    admissionId,
    admissionAttendance,
    cleanupMinutes,
    subtotal,
    discountMinor,
    payments,
    history,
    websitePayment,
  ];
}

class BookingPageResult {
  const BookingPageResult(this.items, this.next);
  final List<BookingRecord> items;
  final int? next;
}

class BookingDashboard extends Equatable {
  const BookingDashboard({
    required this.today,
    required this.upcomingCount,
    required this.value,
    required this.collected,
    required this.refunded,
    required this.outstanding,
    required this.upcoming,
  });
  final int today, upcomingCount;
  final int? value, collected, refunded, outstanding;
  final List<BookingRecord> upcoming;
  factory BookingDashboard.fromJson(Map<String, dynamic> j) => BookingDashboard(
    today: j['today_count'],
    upcomingCount: j['upcoming_count'],
    value: j['booking_value_minor'],
    collected: j['collected_minor'],
    refunded: j['refunded_minor'],
    outstanding: j['outstanding_minor'],
    upcoming: List.unmodifiable(
      (j['upcoming'] as List).map(
        (b) => BookingRecord.fromJson(Map<String, dynamic>.from(b)),
      ),
    ),
  );
  @override
  List<Object?> get props => [
    today,
    upcomingCount,
    value,
    collected,
    refunded,
    outstanding,
    upcoming,
  ];
}

class CollectionEntry {
  const CollectionEntry(
    this.bookingId,
    this.reference,
    this.customer,
    this.payment,
  );
  final String bookingId, reference, customer;
  final BookingPayment payment;
  factory CollectionEntry.fromJson(Map<String, dynamic> j) => CollectionEntry(
    j['booking_id'],
    j['booking_reference'],
    j['customer_snapshot']['name'],
    BookingPayment.fromJson(j),
  );
}

class CollectionTotal extends Equatable {
  const CollectionTotal(this.kind, this.method, this.total);
  final String kind, method;
  final int total;
  factory CollectionTotal.fromJson(Map<String, dynamic> j) =>
      CollectionTotal(j['kind'], j['method'], j['total_minor']);
  @override
  List<Object?> get props => [kind, method, total];
}

class CollectionPage {
  const CollectionPage(this.items, this.next, this.totals);
  final List<CollectionEntry> items;
  final int? next;
  final List<CollectionTotal> totals;
}

class BookingCommand {
  BookingCommand(this.key, this.endpoint, Map<String, dynamic> body)
    : body = Map.unmodifiable({...body, 'command_key': key});
  final String key, endpoint;
  final Map<String, dynamic> body;
}

class BookingLaunch {
  const BookingLaunch({
    this.rescheduleId,
    this.businessId,
    this.spaceId,
    this.date,
    this.time,
  });
  final String? rescheduleId, businessId, spaceId, date, time;
}

class BookingOutstanding extends Equatable {
  const BookingOutstanding({
    required this.id,
    required this.reference,
    required this.status,
    required this.customer,
    required this.business,
    required this.space,
    required this.localStart,
    required this.balance,
    required this.refund,
    this.phone = '',
    this.localEnd,
    this.total,
    this.option,
  });
  final String id, reference, status, customer, business, space, localStart;
  final int balance, refund;
  final String phone;
  final String? localEnd, option;
  final int? total;
  factory BookingOutstanding.fromJson(Map<String, dynamic> j) =>
      BookingOutstanding(
        id: j['id'],
        reference: j['reference'],
        status: j['status'],
        customer: j['customer_name'],
        phone: j['customer_phone'] ?? '',
        localEnd: j['local_end'],
        total: j['total_minor'],
        option: j['option_name'],
        business: j['business_name'],
        space: j['space_name'],
        localStart: j['local_start'],
        balance: j['balance_minor'],
        refund: j['refund_due_minor'],
      );
  @override
  List<Object?> get props => [
    id,
    reference,
    status,
    customer,
    phone,
    localEnd,
    total,
    option,
    business,
    space,
    localStart,
    balance,
    refund,
  ];
}

class OutstandingPage {
  const OutstandingPage(this.items, this.next, this.balance, this.refund);
  final List<BookingOutstanding> items;
  final int? next;
  final int balance, refund;
}
