import '../../../utils/services/rest_api_service.dart';
import '../../accounts/models/accounts_models.dart' show financeMap;
import '../models/invoice_models.dart';
import 'invoice_repository.dart';

class RestInvoiceRepository implements IInvoiceRepository {
  RestInvoiceRepository(this.api);
  final RestApiService api;
  @override
  Future<bool> settings() async =>
      financeMap(await api.request('/invoices/settings'))['enabled'] as bool;
  @override
  Future<bool> saveSettings(bool enabled) async =>
      financeMap(
            await api.request(
              '/invoices/settings',
              method: 'PUT',
              data: {'enabled': enabled},
            ),
          )['enabled']
          as bool;
  // Invoices are never cached: the history must always be what the server holds.
  @override
  Future<BookingInvoiceList> list(String bookingId) async {
    final j = financeMap(await api.request('/invoices/bookings/$bookingId'));
    return BookingInvoiceList(
      enabled: j['enabled'] as bool,
      invoices: [
        for (final i in j['invoices'] as List)
          BookingInvoice.fromJson(financeMap(i)),
      ],
    );
  }

  @override
  Future<BookingInvoice> generate(String bookingId, String commandKey) async =>
      BookingInvoice.fromJson(
        financeMap(
          await api.request(
            '/invoices/bookings/$bookingId',
            method: 'POST',
            data: {'command_key': commandKey},
            readOnly: true,
          ),
        ),
      );
  @override
  Future<List<int>> pdf(String invoiceId) => api.bytes(
    '/invoices/$invoiceId/pdf',
    errorMessage: 'Could not download the invoice. Please try again.',
  );
}
