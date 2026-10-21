import '../../../utils/services/rest_api_service.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/income_models.dart';
import 'income_repository.dart';

class RestIncomeRepository implements IncomeRepository {
  RestIncomeRepository(this.api);
  final RestApiService api;
  @override
  Stream<void> get changes => api.readUpdates
      .where(
        (p) => p == '*' || p.startsWith('/income') || p.startsWith('/accounts'),
      )
      .map((_) {});
  @override
  void refresh() => api.invalidateReads(notify: false);
  String uri(String p, Map<String, Object?> q) => Uri(
    path: '/income$p',
    queryParameters: q.map((k, v) => MapEntry(k, '$v')),
  ).toString();
  @override
  Future<FinanceCatalog> financeCatalog() async => FinanceCatalog.fromJson(
    financeMap(await api.retainedRead('/accounts/catalog')),
  );
  @override
  Future<List<IncomeCategory>> categories() async {
    final j = await api.retainedRead('/income/catalog');
    return [
      for (final v in j['categories'])
        IncomeCategory(v['id'], v['name'], active: v['active'] == true),
    ];
  }

  @override
  Future<void> saveCategory(
    String name, {
    String? id,
    bool active = true,
  }) async {
    await api.request(
      '/income/categories${id == null ? '' : '/$id'}',
      method: id == null ? 'POST' : 'PATCH',
      data: {'name': name, 'active': active},
    );
  }

  @override
  Future<IncomeSummary> overview(IncomeFilter f) async =>
      IncomeSummary.fromJson(
        financeMap(await api.retainedRead(uri('/overview', f.toQuery()))),
      );
  @override
  Future<IncomePage> list(IncomeFilter f, {int cursor = 0}) async {
    final j = await api.retainedRead(
      uri('', {...f.toQuery(), 'cursor': cursor}),
    );
    return IncomePage([
      for (final r in j['items']) IncomeItem.fromJson(financeMap(r)),
    ], j['next_cursor']);
  }

  @override
  Future<List<int>> report(IncomeFilter f, String format) => api.bytes(
    uri('/reports/$format', f.toQuery()),
    errorMessage: 'Could not download the income report. Please retry.',
  );
}
