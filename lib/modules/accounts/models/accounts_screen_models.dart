import 'accounts_models.dart';
import '../../income/models/income_models.dart' show IncomeCategory;

class AccountsOverviewModel {
  const AccountsOverviewModel({
    required this.filter,
    this.catalog,
    this.overview,
    this.transactions = const [],
    this.loading = false,
    this.error,
    this.selectedMonth,
  });
  final FinanceFilter filter;
  final FinanceCatalog? catalog;
  final FinanceOverview? overview;
  final List<FinanceTransaction> transactions;
  final bool loading;
  final String? error, selectedMonth;
  FinanceMonthAnalysis? get activeMonth =>
      overview?.monthlyAnalysis
          .where(
            (m) => m.month == (selectedMonth ?? filter.until.substring(0, 7)),
          )
          .firstOrNull ??
      overview?.monthlyAnalysis.firstOrNull;
  List<FinanceSpaceMonth> get spaceBreakdown {
    final rows = [...?activeMonth?.spaces];
    for (final business in catalog?.businesses ?? <FinanceBusiness>[]) {
      if (filter.businessId != null && filter.businessId != business.id) {
        continue;
      }
      for (final space in business.spaces) {
        if (filter.spaceId != null && filter.spaceId != space.id) continue;
        if (!rows.any(
          (r) => r.businessId == business.id && r.spaceId == space.id,
        )) {
          rows.add(
            FinanceSpaceMonth(
              businessId: business.id,
              spaceId: space.id,
              business: business.name,
              space: space.name,
            ),
          );
        }
      }
    }
    rows.sort((a, b) => a.label.compareTo(b.label));
    return List.unmodifiable(rows);
  }

  AccountsOverviewModel month(String value) => AccountsOverviewModel(
    filter: filter,
    catalog: catalog,
    overview: overview,
    transactions: transactions,
    loading: loading,
    error: error,
    selectedMonth: value,
  );
}

class AccountSettingsModel {
  const AccountSettingsModel({
    this.catalog,
    this.loading = false,
    this.busy = false,
    this.error,
  });
  final FinanceCatalog? catalog;
  final bool loading, busy;
  final String? error;
}

class FinanceEntryModel {
  const FinanceEntryModel({
    required this.kind,
    required this.date,
    this.catalog,
    this.loading = false,
    this.busy = false,
    this.businessId,
    this.spaceId,
    this.reason = '',
    this.category = '',
    this.reference = '',
    this.lines = const [FinanceDraftLine()],
    this.toAccountId,
    this.error,
    this.saved = false,
    this.incomeCategories = const [],
    this.incomeCategoryId,
  });
  final String kind, reason, category, reference;

  /// Managed income categories; empty when they could not be loaded, in
  /// which case the form falls back to a typed category.
  final List<IncomeCategory> incomeCategories;
  final String? incomeCategoryId;
  final DateTime date;
  final FinanceCatalog? catalog;
  final String? businessId, spaceId, toAccountId, error;
  final List<FinanceDraftLine> lines;
  final bool loading, busy, saved;
  FinanceEntryModel copyWith({
    FinanceCatalog? catalog,
    bool? loading,
    bool? busy,
    String? businessId,
    String? spaceId,
    bool clearScope = false,
    String? reason,
    String? category,
    String? reference,
    DateTime? date,
    List<FinanceDraftLine>? lines,
    String? toAccountId,
    String? error,
    bool? saved,
    List<IncomeCategory>? incomeCategories,
    String? incomeCategoryId,
  }) => FinanceEntryModel(
    kind: kind,
    date: date ?? this.date,
    catalog: catalog ?? this.catalog,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    businessId: clearScope ? businessId : businessId ?? this.businessId,
    spaceId: clearScope ? spaceId : spaceId ?? this.spaceId,
    reason: reason ?? this.reason,
    category: category ?? this.category,
    reference: reference ?? this.reference,
    lines: List.unmodifiable(lines ?? this.lines),
    toAccountId: toAccountId ?? this.toAccountId,
    error: error,
    saved: saved ?? this.saved,
    incomeCategories: incomeCategories ?? this.incomeCategories,
    incomeCategoryId: incomeCategoryId ?? this.incomeCategoryId,
  );
}

class BankAccountModel {
  const BankAccountModel({
    this.name = '',
    this.bank = '',
    this.accountNumber = '',
    this.opening = '0',
    required this.date,
    this.primary = false,
    this.busy = false,
    this.saved = false,
    this.error,
  });
  final String name, bank, accountNumber, opening;
  final DateTime date;
  final bool primary, busy, saved;
  final String? error;
  BankAccountModel copyWith({
    String? name,
    String? bank,
    String? accountNumber,
    String? opening,
    DateTime? date,
    bool? primary,
    bool? busy,
    bool? saved,
    String? error,
  }) => BankAccountModel(
    name: name ?? this.name,
    bank: bank ?? this.bank,
    accountNumber: accountNumber ?? this.accountNumber,
    opening: opening ?? this.opening,
    date: date ?? this.date,
    primary: primary ?? this.primary,
    busy: busy ?? this.busy,
    saved: saved ?? this.saved,
    error: error,
  );
}

class ReportsModel {
  const ReportsModel({
    required this.filter,
    this.type = 'monthly',
    this.busy = false,
    this.message,
    this.error,
  });
  final FinanceFilter filter;
  final String type;
  final bool busy;
  final String? message, error;
}

class TransactionsModel {
  const TransactionsModel({
    required this.filter,
    this.items = const [],
    this.next,
    this.loading = false,
    this.error,
  });
  final FinanceFilter filter;
  final List<FinanceTransaction> items;
  final int? next;
  final bool loading;
  final String? error;
}

class TransactionDetailsModel {
  const TransactionDetailsModel(
    this.transaction, {
    this.busy = false,
    this.reversed = false,
    this.error,
  });
  final FinanceTransaction transaction;
  bool get isTransfer =>
      transaction.kind == 'transfer' ||
      (transaction.kind == 'reversal' &&
          transaction.net == 0 &&
          transaction.lines.any((l) => l.amount < 0) &&
          transaction.lines.any((l) => l.amount > 0));
  int get displayAmount => isTransfer
      ? transaction.lines
            .where((l) => l.amount > 0)
            .fold(0, (n, l) => n + l.amount)
      : transaction.amount.abs();
  String get typeLabel => switch (transaction.kind) {
    'booking_collection' => 'Booking payment',
    'admission_collection' => 'Admission payment',
    'admission_refund' => 'Admission refund',
    'booking_refund' => 'Refund',
    'reversal' => isTransfer ? 'Transfer reversal' : 'Reversal',
    _ => financeLabel(transaction.kind),
  };
  String get categoryLabel => transaction.category.isNotEmpty
      ? transaction.category
      : transaction.bookingId != null
      ? 'Booking'
      : 'Not specified';
  String get scopeLabel => [
    transaction.business ?? 'Organization',
    if (transaction.space?.isNotEmpty == true) transaction.space!,
  ].join(' · ');
  bool get reversibleKind =>
      ['income', 'expense', 'transfer'].contains(transaction.kind);
  final bool busy, reversed;
  final String? error;
}
