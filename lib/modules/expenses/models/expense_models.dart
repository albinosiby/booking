import 'dart:typed_data';
import '../../accounts/models/accounts_models.dart';

String expenseDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class ExpenseCategory {
  const ExpenseCategory(this.id, this.name, {this.active = true});
  final String id, name;
  final bool active;
}

class ExpenseFilter {
  const ExpenseFilter({
    required this.anchor,
    this.yearly = false,
    this.categoryId,
    this.businessId,
    this.spaceId,
    this.accountId,
    this.query = '',
  });
  final DateTime anchor;
  final bool yearly;
  final String? categoryId, businessId, spaceId, accountId;
  final String query;
  String get from =>
      expenseDate(DateTime(anchor.year, yearly ? 1 : anchor.month));
  String get until => expenseDate(
    yearly
        ? DateTime(anchor.year + 1, 1, 0)
        : DateTime(anchor.year, anchor.month + 1, 0),
  );
  ExpenseFilter copy({
    DateTime? anchor,
    bool? yearly,
    String? categoryId,
    String? businessId,
    String? spaceId,
    String? accountId,
    String? query,
    bool clearCategory = false,
    bool clearScope = false,
    bool clearAccount = false,
  }) => ExpenseFilter(
    anchor: anchor ?? this.anchor,
    yearly: yearly ?? this.yearly,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    businessId: clearScope ? businessId : businessId ?? this.businessId,
    spaceId: clearScope ? spaceId : spaceId ?? this.spaceId,
    accountId: clearAccount ? null : accountId ?? this.accountId,
    query: query ?? this.query,
  );
}

class ExpenseSummary {
  ExpenseSummary(
    this.total,
    this.count,
    Map<String, int> days,
    List<ExpenseCategoryTotal> categories,
  ) : days = Map.unmodifiable(days),
      categories = List.unmodifiable(categories);
  final int total, count;
  final Map<String, int> days;
  final List<ExpenseCategoryTotal> categories;

  List<int> bars(ExpenseFilter f) => List.generate(
    f.yearly ? 12 : DateTime(f.anchor.year, f.anchor.month + 1, 0).day,
    (i) => days.entries
        .where(
          (e) => f.yearly
              ? DateTime.parse(e.key).month == i + 1
              : DateTime.parse(e.key).day == i + 1,
        )
        .fold(0, (n, e) => n + e.value),
  );
}

class ExpenseCategoryTotal {
  const ExpenseCategoryTotal(this.id, this.name, this.total);
  final String? id;
  final String name;
  final int total;
}

class ExpenseInvoice {
  const ExpenseInvoice({
    required this.id,
    required this.name,
    required this.type,
    required this.size,
    this.ready = false,
  });
  final String id, name, type;
  final int size;
  final bool ready;
}

class ExpensePickedInvoice {
  const ExpensePickedInvoice(
    this.invoice,
    this.bytes, {
    this.uploaded = false,
    this.error,
  });
  final ExpenseInvoice invoice;
  final Uint8List bytes;
  final bool uploaded;
  final String? error;
  ExpensePickedInvoice copy({bool? uploaded, String? error}) =>
      ExpensePickedInvoice(
        invoice,
        bytes,
        uploaded: uploaded ?? this.uploaded,
        error: error,
      );
}

class ExpenseItem {
  ExpenseItem({
    required this.id,
    required this.reason,
    required this.category,
    required this.date,
    required this.amount,
    this.categoryId,
    this.business,
    this.space,
    this.reference = '',
    this.staff = '',
    this.originalId,
    this.invoicesCount = 0,
    Iterable<FinanceLine> lines = const [],
  }) : lines = List.unmodifiable(lines);
  final String id, reason, category, date, reference, staff;
  final String? categoryId, business, space, originalId;
  final int amount, invoicesCount;
  final List<FinanceLine> lines;
}

class ExpensePage {
  ExpensePage(Iterable<ExpenseItem> items, this.next)
    : items = List.unmodifiable(items);
  final List<ExpenseItem> items;
  final int? next;
}

class ExpenseDetail {
  ExpenseDetail(
    this.item,
    Iterable<ExpenseInvoice> invoices, {
    this.reversed = false,
    this.canAttach = false,
  }) : invoices = List.unmodifiable(invoices);
  final ExpenseItem item;
  final List<ExpenseInvoice> invoices;
  final bool reversed, canAttach;
}

class ExpensePayment {
  const ExpensePayment({
    required this.accountId,
    required this.method,
    required this.amount,
  });
  final String accountId, method;
  final int amount;
}

class ExpenseDraft {
  ExpenseDraft({
    required this.commandId,
    required this.categoryId,
    required this.categoryName,
    required this.reason,
    required this.reference,
    required this.occurredAt,
    this.businessId,
    this.spaceId,
    required Iterable<ExpensePayment> payments,
  }) : payments = List.unmodifiable(payments);
  final String commandId, categoryId, categoryName, reason, reference;
  final DateTime occurredAt;
  final String? businessId, spaceId;
  final List<ExpensePayment> payments;
}
