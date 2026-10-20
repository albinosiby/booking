import 'dart:typed_data';
import '../../accounts/models/accounts_models.dart';
import '../models/expense_models.dart';

abstract interface class ExpensesRepository {
  Stream<void> get changes;
  void refresh();
  Future<FinanceCatalog> financeCatalog();
  Future<List<ExpenseCategory>> categories();
  Future<void> saveCategory(String name, {String? id, bool active = true});
  Future<ExpenseSummary> overview(ExpenseFilter filter);
  Future<ExpensePage> list(ExpenseFilter filter, {int cursor = 0});
  Future<ExpenseDetail> detail(String id);
  Future<String> create(ExpenseDraft request);
  Future<void> upload(String expenseId, ExpensePickedInvoice invoice);
  Future<void> discardPending(String expenseId, String invoiceId);
  Future<Uint8List> invoice(String expenseId, String invoiceId);
  Future<List<int>> report(ExpenseFilter filter, String format);
}

abstract interface class InvoicePicker {
  Future<List<ExpensePickedInvoice>> pick({
    bool camera = false,
    bool photos = false,
  });
}
