import 'expense_mapper.dart';
import 'dart:typed_data';
import '../../../config/app_config.dart';
import 'package:dio/dio.dart';
import '../../../utils/services/rest_api_service.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/expense_models.dart';
import 'expenses_repository.dart';

class RestExpensesRepository implements ExpensesRepository {
  RestExpensesRepository(this.api);
  final RestApiService api;
  @override
  Stream<void> get changes => api.readUpdates
      .where(
        (p) =>
            p == '*' || p.startsWith('/expenses') || p.startsWith('/accounts'),
      )
      .map((_) {});
  @override
  void refresh() => api.invalidateReads(notify: false);
  String uri(String p, Map<String, Object?> q) => Uri(
    path: '/expenses$p',
    queryParameters: q.map((k, v) => MapEntry(k, '$v')),
  ).toString();
  @override
  Future<FinanceCatalog> financeCatalog() async => FinanceCatalog.fromJson(
    financeMap(await api.retainedRead('/accounts/catalog')),
  );
  @override
  Future<List<ExpenseCategory>> categories() async {
    final j = await api.retainedRead('/expenses/catalog');
    return [
      for (final v in j['categories']) ExpenseMapper.category(financeMap(v)),
    ];
  }

  @override
  Future<void> saveCategory(
    String name, {
    String? id,
    bool active = true,
  }) async {
    await api.request(
      '/expenses/categories${id == null ? '' : '/$id'}',
      method: id == null ? 'POST' : 'PATCH',
      data: {'name': name, 'active': active},
    );
  }

  @override
  Future<ExpenseSummary> overview(ExpenseFilter f) async =>
      ExpenseMapper.summary(
        financeMap(
          await api.retainedRead(uri('/overview', ExpenseMapper.filter(f))),
        ),
      );
  @override
  Future<ExpensePage> list(ExpenseFilter f, {int cursor = 0}) async {
    final j = await api.retainedRead(
      uri('', {...ExpenseMapper.filter(f), 'cursor': cursor}),
    );
    return ExpensePage([
      for (final r in j['items']) ExpenseMapper.item(financeMap(r)),
    ], j['next_cursor']);
  }

  @override
  Future<ExpenseDetail> detail(String id) async {
    final j = await api.retainedRead('/expenses/$id');
    return ExpenseDetail(
      ExpenseMapper.item(financeMap(j)),
      [for (final r in j['attachments']) ExpenseMapper.invoice(financeMap(r))],
      reversed: (j['reversals'] as List).isNotEmpty,
      canAttach: j['can_attach'] == true,
    );
  }

  @override
  Future<String> create(ExpenseDraft r) async =>
      (await api.request(
            '/expenses',
            method: 'POST',
            data: ExpenseMapper.draft(r),
          ))['id']
          as String;
  Uri signedUri(String url) {
    final u = Uri.parse(url), base = Uri.parse(AppConfig.supabaseUrl);
    if (u.scheme != 'https' ||
        u.host != base.host ||
        !u.path.startsWith('/storage/v1/object/')) {
      throw const AppException('Invalid invoice storage destination.');
    }
    return u;
  }

  @override
  Future<void> upload(String expenseId, ExpensePickedInvoice picked) async {
    final f = picked.invoice,
        j = await api.request(
          '/expenses/$expenseId/attachments',
          method: 'POST',
          data: {
            'id': f.id,
            'name': f.name,
            'content_type': f.type,
            'size_bytes': f.size,
          },
        );
    if (j['ready'] == true) return;
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        sendTimeout: const Duration(minutes: 3),
        receiveTimeout: const Duration(seconds: 30),
      ),
    );
    try {
      await dio.putUri(
        signedUri(j['upload_url']),
        data: Stream.value(picked.bytes),
        options: Options(
          headers: {'Content-Type': f.type, 'Content-Length': f.size},
        ),
      );
    } on DioException {
      throw const AppException(
        'Invoice upload failed. Your expense is saved; retry this file.',
      );
    } finally {
      dio.close();
    }
    await api.request(
      '/expenses/$expenseId/attachments/${f.id}/complete',
      method: 'POST',
      data: {},
    );
  }

  @override
  Future<void> discardPending(String expenseId, String invoiceId) async {
    await api.request(
      '/expenses/$expenseId/attachments/$invoiceId',
      method: 'DELETE',
    );
  }

  @override
  Future<Uint8List> invoice(String expenseId, String invoiceId) async {
    final j = await api.request('/expenses/$expenseId/attachments/$invoiceId'),
        dio = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(minutes: 1),
          ),
        );
    try {
      final r = await dio.getUri<List<int>>(
        signedUri(j['url']),
        options: Options(responseType: ResponseType.bytes),
      );
      if ((r.data?.length ?? 0) > 15 * 1024 * 1024) {
        throw const AppException('Invoice is too large.');
      }
      return Uint8List.fromList(r.data!);
    } on DioException {
      throw const AppException('Could not open the invoice. Please retry.');
    } finally {
      dio.close();
    }
  }

  @override
  Future<List<int>> report(ExpenseFilter f, String format) => api.bytes(
    uri('/reports/$format', ExpenseMapper.filter(f)),
    errorMessage: 'Could not download the expense report. Please retry.',
  );
}
