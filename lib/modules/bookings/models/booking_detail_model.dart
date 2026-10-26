import 'booking_payment_entry_model.dart';
import 'package:equatable/equatable.dart';
import 'booking_models.dart';

enum BookingDetailAction {
  none,
  collection,
  refund,
  customer,
  cancelled,
  cancelAndRefund,
  completed,
  checkedIn,
  noShow,
}

class BookingDetailModel extends Equatable {
  BookingDetailModel({
    this.record,
    this.catalog = const BookingCatalog(),
    this.loading = true,
    this.saving = false,
    this.action = BookingDetailAction.none,
    Iterable<BookingPaymentDraft> payments = const [],
    this.customer = const BookingCustomer(),
    this.notes = '',
    this.reason = '',
    this.error,
    this.pending,
  }) : payments = List.unmodifiable(payments);
  final BookingRecord? record;
  final BookingCatalog catalog;
  final bool loading, saving;
  final BookingDetailAction action;
  final List<BookingPaymentDraft> payments;
  final BookingCustomer customer;
  final String notes, reason;
  final String? error;
  final BookingCommand? pending;
  bool get canCheckIn =>
      catalog.canManage &&
      record?.status == 'confirmed' &&
      record?.checkedIn == false;
  bool get canCollectPending =>
      catalog.canCollect &&
      record != null &&
      record!.status != 'cancelled' &&
      record!.balance > 0;
  bool get canCancelAndRefund =>
      catalog.canManage &&
      catalog.canRefund &&
      catalog.canCollect &&
      record?.status == 'confirmed' &&
      record?.admissionId == null &&
      (record?.netPaid ?? 0) > 0;
  List<BookingPayment> get paymentHistory {
    final rows = record?.payments.indexed.toList() ?? [];
    rows.sort((a, b) {
      final order = b.$2.localReceived.compareTo(a.$2.localReceived);
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
    return List.unmodifiable(rows.map((e) => e.$2));
  }

  List<BookingEvent> get bookingHistory {
    final rows = record?.history.indexed.toList() ?? [];
    rows.sort((a, b) {
      final order = b.$2.date.compareTo(a.$2.date);
      return order == 0 ? a.$1.compareTo(b.$1) : order;
    });
    return List.unmodifiable(rows.map((e) => e.$2));
  }

  int get paymentLimit => action == BookingDetailAction.refund
      ? record?.refundDue ?? 0
      : record?.balance ?? 0;
  BookingPaymentEntryModel get paymentEntry =>
      BookingPaymentEntryModel(total: paymentLimit, payments: payments);
  int? paymentBalance(String id) => paymentEntry.balanceFor(id);
  String? paymentError(BookingPaymentDraft p) => paymentEntry.errorFor(p);
  bool get locked => saving || pending != null;
  BookingDetailModel copyWith({
    BookingRecord? record,
    BookingCatalog? catalog,
    bool? loading,
    bool? saving,
    BookingDetailAction? action,
    Iterable<BookingPaymentDraft>? payments,
    BookingCustomer? customer,
    String? notes,
    String? reason,
    String? error,
    BookingCommand? pending,
    bool clearPending = false,
  }) => BookingDetailModel(
    record: record ?? this.record,
    catalog: catalog ?? this.catalog,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    action: action ?? this.action,
    payments: payments ?? this.payments,
    customer: customer ?? this.customer,
    notes: notes ?? this.notes,
    reason: reason ?? this.reason,
    error: error,
    pending: clearPending ? null : pending ?? this.pending,
  );
  @override
  List<Object?> get props => [
    record,
    catalog,
    loading,
    saving,
    action,
    payments,
    customer,
    notes,
    reason,
    error,
    pending,
  ];
}
