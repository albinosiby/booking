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
    error: error,
    savedId: savedId ?? this.savedId,
    overview: overview ?? this.overview,
  );
  AdmissionBusiness? get business =>
      catalog.businesses.where((b) => b.id == draft.businessId).firstOrNull;
  AdmissionPool? get pool =>
      business?.pools.where((p) => p.id == draft.poolId).firstOrNull;
  int get minimumVisitDuration => pool?.defaultDuration ?? 60;
  bool get adjustableVisitDuration => plan != null && plan!.kind != 'coaching';
  bool get validVisitDuration => adjustableVisitDuration
      ? draft.duration >= minimumVisitDuration &&
            draft.duration <= 1440 &&
            (draft.duration - minimumVisitDuration) % 30 == 0
      : plan?.duration == null || draft.duration == plan!.duration;
  String? get expiry => preview?.expiry ?? plan?.expiryFor(draft.start);
  BookingPaymentEntryModel get paymentEntry => BookingPaymentEntryModel(
    total: preview?.total ?? plan?.total,
    payments: draft.payments,
  );
  AdmissionPlan? get plan =>
      business?.plans.where((p) => p.id == draft.planId).firstOrNull;
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
    error,
    savedId,
    overview,
  ];
}
