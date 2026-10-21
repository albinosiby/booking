import 'package:equatable/equatable.dart';
import '../../accounts/models/accounts_models.dart';
import '../models/income_models.dart';

class IncomeState extends Equatable {
  IncomeState({
    required this.filter,
    this.catalog,
    Iterable<IncomeCategory> categories = const [],
    this.summary,
    Iterable<IncomeItem> items = const [],
    this.next,
    this.loading = false,
    this.more = false,
    this.exporting = false,
    this.error,
    this.message,
  }) : categories = List.unmodifiable(categories),
       items = List.unmodifiable(items);
  final IncomeFilter filter;
  final FinanceCatalog? catalog;
  final List<IncomeCategory> categories;
  final IncomeSummary? summary;
  final List<IncomeItem> items;
  final int? next;
  final bool loading, more, exporting;
  final String? error, message;

  /// Display name for the selected source filter.
  String? get sourceName => switch (filter.source) {
    null => null,
    incomeBookings => 'Bookings',
    incomeAdmissions => 'Admissions',
    final id => categories.where((c) => c.id == id).firstOrNull?.name,
  };
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
  IncomeState copy({
    IncomeFilter? filter,
    FinanceCatalog? catalog,
    List<IncomeCategory>? categories,
    IncomeSummary? summary,
    List<IncomeItem>? items,
    int? next,
    bool clearNext = false,
    bool? loading,
    bool? more,
    bool? exporting,
    String? error,
    String? message,
  }) => IncomeState(
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
