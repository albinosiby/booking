import '../../workspace/repositories/refreshable_reads.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/accounts_models.dart';
import 'accounts_repository.dart';
import 'dart:convert';
import '../../../utils/services/logo_picker_service.dart';
import 'website_payment_repository.dart';

class RestAccountsRepository
    implements AccountsRepository, RefreshableReads, WebsitePaymentRepository {
  RestAccountsRepository(this.api);
  final RestApiService api;
  @override
  Future<WebsitePaymentDetails> websitePayments() async =>
      WebsitePaymentDetails.fromJson(
        financeMap(await api.request('/accounts/website-payments')),
      );
  @override
  Future<WebsitePaymentDetails> saveWebsitePayments(
    int version,
    String upiId,
    LogoSelection? qr,
  ) async => WebsitePaymentDetails.fromJson(
    financeMap(
      await api.request(
        '/accounts/website-payments',
        method: 'POST',
        data: {
          'version': version,
          'upi_id': upiId.trim(),
          'qr': qr == null
              ? null
              : {
                  'base64': base64Encode(qr.bytes),
                  'content_type': qr.contentType,
                },
        },
      ),
    ),
  );
  @override
  void invalidateReads() => api.invalidateReads(notify: false);
  @override
  Stream<void> get changes => api.readUpdates
      .where((key) => key == '*' || key.startsWith('/accounts'))
      .map((_) {});
  String uri(String path, Map<String, Object?> q) => Uri(
    path: '/accounts/$path',
    queryParameters: q.map((k, v) => MapEntry(k, '$v')),
  ).toString();
  Future<void> write(
    String path,
    Map<String, Object?> request, {
    String method = 'POST',
  }) async {
    await api.request('/accounts/$path', method: method, data: request);
  }

  @override
  Future<FinanceCatalog> catalog() async => FinanceCatalog.fromJson(
    financeMap(await api.retainedRead('/accounts/catalog')),
  );
  @override
  Future<FinanceOverview> overview(FinanceFilter f) async =>
      FinanceOverview.fromJson(
        financeMap(await api.retainedRead(uri('overview', f.toJson()))),
      );
  @override
  Future<FinanceTransactionPage> transactions(
    FinanceFilter f, {
    int cursor = 0,
  }) async {
    final j = await api.retainedRead(
      uri('transactions', {...f.toJson(), 'cursor': cursor}),
    );
    return FinanceTransactionPage(
      (j['items'] as List).map(
        (v) => FinanceTransaction.fromJson(financeMap(v)),
      ),
      j['next_cursor'],
    );
  }

  @override
  Future<void> cashOpening(Map<String, Object?> r) => write('cash/opening', r);
  @override
  Future<void> createBank(Map<String, Object?> r) => write('banks', r);
  @override
  Future<void> updateBank(String id, Map<String, Object?> r) =>
      write('banks/$id', r, method: 'PATCH');
  @override
  Future<void> route(Map<String, Object?> r) => write('routes', r);
  @override
  Future<void> entry(Map<String, Object?> r) => write('entries', r);
  @override
  Future<void> reverse(String id, Map<String, Object?> r) =>
      write('entries/$id/reverse', r);
  @override
  Future<List<int>> report(FinanceFilter f, String type, String format) =>
      api.bytes(
        uri('reports/$format', {...f.toJson(), 'type': type}),
        errorMessage: 'Could not download the report. Please try again.',
      );
}
