import 'booking_models.dart';

/// Shared local calculations for new bookings and later collections/refunds.
class BookingPaymentEntryModel {
  BookingPaymentEntryModel({
    required this.total,
    required Iterable<BookingPaymentDraft> payments,
  }) : payments = List.unmodifiable(payments);
  final int? total;
  final List<BookingPaymentDraft> payments;
  List<BookingPaymentDraft> get recorded =>
      payments.where((p) => !p.isBlank).toList(growable: false);
  int get received => payments.fold(0, (n, p) => n + (p.minor ?? 0));
  int? get remaining =>
      total == null ? null : (total! - received).clamp(0, total!);
  int? balanceFor(String id) => total == null
      ? null
      : (total! -
                payments
                    .where((p) => p.id != id)
                    .fold<int>(0, (n, p) => n + (p.minor ?? 0)))
            .clamp(0, total!);
  String? errorFor(BookingPaymentDraft p) {
    if (p.isBlank) return null;
    final error = p.validate();
    if (error != null) return error;
    final limit = balanceFor(p.id);
    return limit != null && p.minor! > limit
        ? 'Amount exceeds the remaining balance.'
        : null;
  }
}
