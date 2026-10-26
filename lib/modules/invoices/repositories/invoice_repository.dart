import 'package:get_it/get_it.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/invoice_models.dart';

/// Invoices need the API client; screens hide invoice controls where it is absent.
bool invoicesAvailable(GetIt di) =>
    di.isRegistered<IInvoiceRepository>() && di.isRegistered<RestApiService>();

abstract interface class IInvoiceRepository {
  Future<InvoiceSettings> settings();
  Future<InvoiceSettings> saveSettings({bool? enabled, String? template});

  /// A sample invoice PDF in the given design, filled with this organization's details.
  Future<List<int>> previewTemplate(String template);
  Future<BookingInvoiceList> list(String bookingId);

  /// Creates the invoice for the booking's current data, or returns the latest
  /// one when nothing changed since it was generated.
  Future<BookingInvoice> generate(String bookingId, String commandKey);
  Future<List<int>> pdf(String invoiceId);
}

/// Saving to the device and the system share sheet, kept apart so tests can fake them.
abstract interface class InvoiceFileGateway {
  Future<bool> save(List<int> bytes, String filename);
  Future<void> share(List<int> bytes, String filename);
}
