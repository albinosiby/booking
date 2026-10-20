import 'accounts_models.dart';

class AccountsOverviewModel {
  const AccountsOverviewModel({
    required this.filter,
    this.catalog,
    this.overview,
    this.transactions = const [],
    this.loading = false,
    this.error,
  });
  final FinanceFilter filter;
  final FinanceCatalog? catalog;
  final FinanceOverview? overview;
  final List<FinanceTransaction> transactions;
  final bool loading;
  final String? error;
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
  });
  final String kind, reason, category, reference;
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
  final bool busy, reversed;
  final String? error;
}
