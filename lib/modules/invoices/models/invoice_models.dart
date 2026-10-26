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

class InvoiceTemplateInfo extends Equatable {
  const InvoiceTemplateInfo({
    required this.id,
    required this.name,
    required this.description,
  });
  factory InvoiceTemplateInfo.fromJson(Map<String, dynamic> j) =>
      InvoiceTemplateInfo(
        id: j['id'] as String,
        name: j['name'] as String,
        description: j['description'] as String,
      );
  final String id, name, description;
  @override
  List<Object?> get props => [id, name, description];
}

const defaultInvoiceTemplates = [
  InvoiceTemplateInfo(
    id: 'classic',
    name: 'Classic',
    description: 'Green accents with a simple ruled layout.',
  ),
  InvoiceTemplateInfo(
    id: 'modern',
    name: 'Modern',
    description: 'Bold coloured header band with the balance due highlighted.',
  ),
  InvoiceTemplateInfo(
    id: 'minimal',
    name: 'Minimal',
    description: 'Plain black and white, light on decoration.',
  ),
];

class InvoiceSettings extends Equatable {
  const InvoiceSettings({
    required this.enabled,
    required this.template,
    this.templates = defaultInvoiceTemplates,
  });
  factory InvoiceSettings.fromJson(Map<String, dynamic> j) => InvoiceSettings(
    enabled: j['enabled'] as bool,
    template: j['template'] as String,
    templates: [
      for (final t in j['templates'] as List)
        InvoiceTemplateInfo.fromJson(Map<String, dynamic>.from(t as Map)),
    ],
  );
  final bool enabled;
  final String template;
  final List<InvoiceTemplateInfo> templates;
  @override
  List<Object?> get props => [enabled, template, templates];
}

class InvoiceSettingsModel extends Equatable {
  const InvoiceSettingsModel({
    this.enabled = true,
    this.template = 'classic',
    this.templates = defaultInvoiceTemplates,
    this.loaded = false,
    this.loading = false,
    this.saving = false,
    this.error,
  });
  final bool enabled, loaded, loading, saving;
  final String template;
  final List<InvoiceTemplateInfo> templates;
  final String? error;
  bool get busy => loading || saving;
  InvoiceTemplateInfo get selected => templates.firstWhere(
    (t) => t.id == template,
    orElse: () => templates.first,
  );
  @override
  List<Object?> get props => [
    enabled,
    template,
    templates,
    loaded,
    loading,
    saving,
    error,
  ];
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
