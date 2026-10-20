import '../models/accounts_models.dart';

abstract interface class AccountsRepository {
  Stream<void> get changes;
  Future<FinanceCatalog> catalog();
  Future<FinanceOverview> overview(FinanceFilter filter);
  Future<FinanceTransactionPage> transactions(
    FinanceFilter filter, {
    int cursor = 0,
  });
  Future<void> cashOpening(Map<String, Object?> request);
  Future<void> createBank(Map<String, Object?> request);
  Future<void> updateBank(String id, Map<String, Object?> request);
  Future<void> route(Map<String, Object?> request);
  Future<void> entry(Map<String, Object?> request);
  Future<void> reverse(String id, Map<String, Object?> request);
  Future<List<int>> report(FinanceFilter filter, String type, String format);
}
