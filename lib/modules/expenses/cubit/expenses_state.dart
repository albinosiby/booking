import 'package:equatable/equatable.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/expense_models.dart';

class ExpensesState extends Equatable {
  ExpensesState({
    required this.filter,
    this.catalog,
    Iterable<ExpenseCategory> categories = const [],
    this.summary,
    Iterable<ExpenseItem> items = const [],
    this.next,
    this.loading = false,
    this.more = false,
    this.exporting = false,
    this.error,
    this.message,
  }) : categories = List.unmodifiable(categories),
       items = List.unmodifiable(items);
  final ExpenseFilter filter;
  final FinanceCatalog? catalog;
  final List<ExpenseCategory> categories;
  final ExpenseSummary? summary;
  final List<ExpenseItem> items;
  final int? next;
  final bool loading, more, exporting;
  final String? error, message;
  @override
  List<Object?> get props => [
    filter,
    catalog,
    categories,
    summary,
    items,
    next,
    loading,
    more,
    exporting,
    error,
    message,
  ];
  ExpensesState copy({
    ExpenseFilter? filter,
    FinanceCatalog? catalog,
    List<ExpenseCategory>? categories,
    ExpenseSummary? summary,
    List<ExpenseItem>? items,
    int? next,
    bool clearNext = false,
    bool? loading,
    bool? more,
    bool? exporting,
    String? error,
    String? message,
  }) => ExpensesState(
    filter: filter ?? this.filter,
    catalog: catalog ?? this.catalog,
    categories: categories ?? this.categories,
    summary: summary ?? this.summary,
    items: items ?? this.items,
    next: clearNext ? next : next ?? this.next,
    loading: loading ?? this.loading,
    more: more ?? this.more,
    exporting: exporting ?? this.exporting,
    error: error,
    message: message,
  );
}

class ExpenseFormState extends Equatable {
  ExpenseFormState({
    this.catalog,
    Iterable<ExpenseCategory> categories = const [],
    this.loading = false,
    this.busy = false,
    this.picking = false,
    this.complete = false,
    this.error,
    this.savedId,
    this.categoryId,
    this.businessId,
    this.spaceId,
    this.date,
    this.reason = '',
    this.reference = '',
    Iterable<FinanceDraftLine> lines = const [],
    Iterable<ExpensePickedInvoice> files = const [],
  }) : categories = List.unmodifiable(categories),
       lines = List.unmodifiable(lines),
       files = List.unmodifiable(files);
  final FinanceCatalog? catalog;
  final List<ExpenseCategory> categories;
  final bool loading, busy, picking, complete;
  final String? error, savedId, categoryId, businessId, spaceId;
  final DateTime? date;
  final String reason, reference;
  final List<FinanceDraftLine> lines;
  final List<ExpensePickedInvoice> files;
  @override
  List<Object?> get props => [
    catalog,
    categories,
    loading,
    busy,
    picking,
    complete,
    error,
    savedId,
    categoryId,
    businessId,
    spaceId,
    date,
    reason,
    reference,
    lines,
    files,
  ];
  ExpenseFormState copy({
    FinanceCatalog? catalog,
    List<ExpenseCategory>? categories,
    bool? loading,
    bool? busy,
    bool? picking,
    bool? complete,
    String? error,
    String? savedId,
    String? categoryId,
    String? businessId,
    String? spaceId,
    bool clearScope = false,
    DateTime? date,
    String? reason,
    String? reference,
    List<FinanceDraftLine>? lines,
    List<ExpensePickedInvoice>? files,
  }) => ExpenseFormState(
    catalog: catalog ?? this.catalog,
    categories: categories ?? this.categories,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    picking: picking ?? this.picking,
    complete: complete ?? this.complete,
    error: error,
    savedId: savedId ?? this.savedId,
    categoryId: categoryId ?? this.categoryId,
    businessId: clearScope ? businessId : businessId ?? this.businessId,
    spaceId: clearScope ? spaceId : spaceId ?? this.spaceId,
    date: date ?? this.date,
    reason: reason ?? this.reason,
    reference: reference ?? this.reference,
    lines: lines ?? this.lines,
    files: files ?? this.files,
  );
}

class ExpenseDetailState extends Equatable {
  const ExpenseDetailState({
    this.detail,
    this.catalog,
    this.loading = false,
    this.busy = false,
    this.error,
  });
  final ExpenseDetail? detail;
  final FinanceCatalog? catalog;
  final bool loading, busy;
  final String? error;
  @override
  List<Object?> get props => [detail, catalog, loading, busy, error];
  ExpenseDetailState copy({
    ExpenseDetail? detail,
    FinanceCatalog? catalog,
    bool? loading,
    bool? busy,
    String? error,
  }) => ExpenseDetailState(
    detail: detail ?? this.detail,
    catalog: catalog ?? this.catalog,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    error: error,
  );
}
