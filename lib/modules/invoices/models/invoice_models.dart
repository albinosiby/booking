import 'package:equatable/equatable.dart';

class BookingInvoice extends Equatable {
  const BookingInvoice({
    required this.id,
    required this.bookingId,
    required this.number,
    required this.totalMinor,
    required this.paidMinor,
    required this.balanceMinor,
    required this.currency,
    required this.generatedByName,
    required this.generatedAt,
  });
  factory BookingInvoice.fromJson(Map<String, dynamic> j) => BookingInvoice(
    id: j['id'] as String,
    bookingId: j['booking_id'] as String,
    number: j['invoice_number'] as String,
    totalMinor: (j['total_minor'] as num).toInt(),
    paidMinor: (j['paid_minor'] as num).toInt(),
    balanceMinor: (j['balance_minor'] as num).toInt(),
    currency: j['currency'] as String,
    generatedByName: j['generated_by_name'] as String,
    generatedAt: DateTime.parse(j['generated_at'] as String).toLocal(),
  );
  final String id, bookingId, number, currency, generatedByName;
  final int totalMinor, paidMinor, balanceMinor;
  final DateTime generatedAt;
  String get filename => '$number.pdf';
  @override
  List<Object?> get props => [id, number, generatedAt];
}

class BookingInvoiceList extends Equatable {
  const BookingInvoiceList({required this.enabled, required this.invoices});
  final bool enabled;
  final List<BookingInvoice> invoices;
  @override
  List<Object?> get props => [enabled, invoices];
}

class InvoiceSettingsModel extends Equatable {
  const InvoiceSettingsModel({
    this.enabled = true,
    this.loaded = false,
    this.loading = false,
    this.saving = false,
    this.error,
  });
  final bool enabled, loaded, loading, saving;
  final String? error;
  bool get busy => loading || saving;
  @override
  List<Object?> get props => [enabled, loaded, loading, saving, error];
}

class BookingInvoicesModel extends Equatable {
  const BookingInvoicesModel({
    this.enabled = false,
    this.invoices = const [],
    this.loading = true,
    this.workingOn,
    this.error,
    this.message,
  });
  final bool enabled, loading;
  final List<BookingInvoice> invoices;

  /// Invoice id being downloaded/shared, or [newInvoice] while generating one.
  final String? workingOn;
  final String? error, message;
  static const newInvoice = 'new';
  bool get busy => loading || workingOn != null;
  @override
  List<Object?> get props => [
    enabled,
    loading,
    invoices,
    workingOn,
    error,
    message,
  ];
}
