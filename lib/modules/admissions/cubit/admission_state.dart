import '../../bookings/models/booking_payment_entry_model.dart';
import '../../bookings/models/booking_models.dart';
import 'package:equatable/equatable.dart';
import '../models/admission_models.dart';
import '../models/admission_overview.dart';

class AdmissionState extends Equatable {
  const AdmissionState({
    this.catalog = const AdmissionCatalog(),
    this.items = const [],
    this.customers = const [],
    this.detail,
    this.draft = const AdmissionDraft(),
    this.preview,
    this.kind = 'swimming',
    this.formKind,
    this.query = '',
    this.status,
    this.next,
    this.loading = false,
    this.busy = false,
    this.locked = false,
    this.renewAndCollect = false,
    this.error,
    this.savedId,
    this.overview = const AdmissionOverview(),
  });
  final AdmissionCatalog catalog;
  final List<Admission> items;
  final List<BookingCustomer> customers;
  final Admission? detail;
  final AdmissionDraft draft;
  final AdmissionPreview? preview;
  final String kind, query;
  final String? formKind;
  final AdmissionOverview overview;
  List<AdmissionPlan> get availablePlans =>
      business?.plans
          .where(
            (p) => p.poolIds.contains(draft.poolId) && p.matchesKind(formKind),
          )
          .toList() ??
      [];
  final String? status, error, savedId;
  final int? next;
  final bool loading, busy, locked;
  final bool renewAndCollect;
  AdmissionState copyWith({
    AdmissionCatalog? catalog,
    List<Admission>? items,
    List<BookingCustomer>? customers,
    Admission? detail,
    AdmissionDraft? draft,
    AdmissionPreview? preview,
    String? kind,
    String? formKind,
    String? query,
    String? status,
    int? next,
    bool? loading,
    bool? busy,
    bool? locked,
    bool? renewAndCollect,
    String? error,
    String? savedId,
    AdmissionOverview? overview,
    bool clearPreview = false,
    bool clearStatus = false,
    bool clearNext = false,
  }) => AdmissionState(
    catalog: catalog ?? this.catalog,
    items: items ?? this.items,
    customers: customers ?? this.customers,
    detail: detail ?? this.detail,
    draft: draft ?? this.draft,
    preview: clearPreview ? null : preview ?? this.preview,
    kind: kind ?? this.kind,
    formKind: formKind ?? this.formKind,
    query: query ?? this.query,
    status: clearStatus ? null : status ?? this.status,
    next: clearNext ? null : next ?? this.next,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    locked: locked ?? this.locked,
    renewAndCollect: renewAndCollect ?? this.renewAndCollect,
    error: error,
    savedId: savedId ?? this.savedId,
    overview: overview ?? this.overview,
  );
  AdmissionBusiness? get business =>
      catalog.businesses.where((b) => b.id == draft.businessId).firstOrNull;
  AdmissionPool? get pool =>
      business?.pools.where((p) => p.id == draft.poolId).firstOrNull;
  int get minimumVisitDuration => pool?.defaultDuration ?? 60;
  bool get adjustableVisitDuration =>
      plan != null && plan!.trackAttendance && plan!.kind != 'coaching';

  /// Visit lengths an end time may set, shortest first.
  List<int> get endDurations {
    if (plan?.trackAttendance != true) return const [];
    final options = <int>{};
    void steps() {
      for (var m = minimumVisitDuration; m <= 1440; m += 30) {
        options.add(m);
      }
    }

    if (adjustableVisitDuration) {
      steps();
    } else {
      options.add(draft.duration);
    }
    return List.unmodifiable(options.toList()..sort());
  }

  bool get validVisitDuration =>
      plan?.trackAttendance == false ||
      (adjustableVisitDuration
          ? draft.duration >= minimumVisitDuration &&
                draft.duration <= 1440 &&
                (draft.duration - minimumVisitDuration) % 30 == 0
          : plan?.duration == null || draft.duration == plan!.duration);
  bool get subscription => formKind == 'subscription' || draft.subscription;
  String? get expiry => preview?.expiry ?? plan?.expiryFor(draft.start);

  /// Sessions a subscription reserves: every chosen weekday until expiry.
  int get subscriptionSessions {
    final end = expiry;
    return plan?.subscription == true && end != null
        ? fixedSessionCount(draft.start, end, draft.weekdays)
        : 0;
  }

  /// Subscriptions have no configured price; staff agree a monthly fee.
  int? get configuredAmount => subscription ? null : plan?.total;

  /// The whole amount: for subscriptions the monthly fee × months.
  int? get planAmount => subscription
      ? (draft.amountMinor == null
            ? null
            : draft.amountMinor! * (draft.endsOn == null ? draft.months : 1))
      : draft.amount == null
      ? configuredAmount
      : draft.amountMinor;
  String get planAmountText =>
      draft.amount ??
      (subscription ? '' : ((configuredAmount ?? 0) / 100).toStringAsFixed(2));
  String? get planAmountError => subscription && draft.amount == null
      ? 'Enter the monthly fee.'
      : draft.amount != null && draft.amountMinor == null
      ? 'Enter a valid ${subscription ? 'monthly fee' : 'plan amount'} (0–1,000,000, up to two decimal places).'
      : subscription && (planAmount ?? 0) > 100000000
      ? 'The subscription is above the maximum amount. Choose fewer months or a lower fee.'
      : null;
  BookingPaymentEntryModel get paymentEntry => BookingPaymentEntryModel(
    total: preview?.total ?? planAmount,
    payments: draft.payments,
  );
  AdmissionPlan? get plan => subscription
      ? business == null
            ? null
            : AdmissionPlan.subscriptionFor(
                business!,
                months: draft.endsOn == null ? draft.months : null,
                endsOn: draft.endsOn,
                monthly: draft.amountMinor ?? 0,
              )
      : business?.plans.where((p) => p.id == draft.planId).firstOrNull;
  @override
  List<Object?> get props => [
    catalog,
    customers,
    items,
    detail,
    draft,
    preview,
    kind,
    formKind,
    query,
    status,
    next,
    loading,
    busy,
    locked,
    renewAndCollect,
    error,
    savedId,
    overview,
  ];
}
