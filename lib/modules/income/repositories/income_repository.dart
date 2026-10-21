import '../../accounts/models/accounts_models.dart';
import '../models/income_models.dart';

abstract interface class IncomeRepository {
  Stream<void> get changes;
  void refresh();
  Future<FinanceCatalog> financeCatalog();
  Future<List<IncomeCategory>> categories();
  Future<void> saveCategory(String name, {String? id, bool active = true});
  Future<IncomeSummary> overview(IncomeFilter filter);
  Future<IncomePage> list(IncomeFilter filter, {int cursor = 0});
  Future<List<int>> report(IncomeFilter filter, String format);
}
