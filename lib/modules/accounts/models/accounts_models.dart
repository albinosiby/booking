import '../../../utils/helpers/time_format.dart';
import 'package:equatable/equatable.dart';
import '../../bookings/models/booking_models.dart';

String financeStamp(String value) {
  final raw = value.replaceFirst('T', ' ');
  if (raw.length < 16) return raw;
  return '${raw.substring(0, 10)} ${TimeFormat.display(raw.substring(11, 16))}';
}

int? financeOpeningMinor(String value) {
  if (!RegExp(r'^\d{1,10}(\.\d{1,2})?$').hasMatch(value)) return null;
  final p = value.split('.'), whole = int.tryParse(p[0]);
  if (whole == null) return null;
  final n =
      whole * 100 + (p.length == 1 ? 0 : int.parse(p[1].padRight(2, '0')));
  return n <= 100000000000 ? n : null;
}

String financeMoney(int n, String currency) =>
    '${currency == 'INR' ? '₹' : currency} ${(n / 100).toStringAsFixed(2)}';
String financeLabel(String v) => v == 'upi'
    ? 'UPI'
    : v
          .split('_')
          .map((s) => s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}')
          .join(' ');
Map<String, dynamic> financeMap(dynamic j) =>
    Map<String, dynamic>.from(j as Map);

class MoneyAccount {
  const MoneyAccount({
    required this.id,
    required this.name,
    required this.kind,
    this.bankName = '',
    this.lastFour = '',
    this.accountNumber = '',
    this.primary = false,
    this.openingSet = false,
    this.active = true,
    this.balance,
    this.openingAt,
  });
  final String id, name, kind, bankName, lastFour, accountNumber;
  final bool primary, active, openingSet;
  final int? balance;
  final DateTime? openingAt;
  factory MoneyAccount.fromJson(Map<String, dynamic> j) => MoneyAccount(
    id: j['id'],
    name: j['name'],
    kind: j['kind'],
    bankName: j['bank_name'] ?? '',
    lastFour: j['last_four'] ?? '',
    accountNumber: j['account_number'] ?? '',
    primary: j['is_primary'] ?? false,
    openingSet: j['opening_set'] ?? false,
    active: j['active'] ?? true,
    balance: (j['balance_minor'] as num?)?.toInt(),
    openingAt: DateTime.tryParse('${j['opening_at']}'),
  );
}

class FinanceBusiness {
  FinanceBusiness(this.id, this.name, Iterable<FinanceSpace> spaces)
    : spaces = List.unmodifiable(spaces);
  final String id, name;
  final List<FinanceSpace> spaces;
  factory FinanceBusiness.fromJson(Map<String, dynamic> j) => FinanceBusiness(
    j['id'],
    j['name'],
    (j['resources'] as List).map((v) => FinanceSpace(v['id'], v['name'])),
  );
}

class FinanceSpace {
  const FinanceSpace(this.id, this.name);
  final String id, name;
}

class PaymentRoute {
  const PaymentRoute(
    this.businessId,
    this.spaceId,
    this.method,
    this.accountId,
  );
  final String businessId, method, accountId;
  final String? spaceId;
  factory PaymentRoute.fromJson(Map<String, dynamic> j) => PaymentRoute(
    j['business_id'],
    j['resource_id'],
    j['method'],
    j['account_id'],
  );
}

class FinanceCatalog {
  FinanceCatalog({
    this.name = '',
    this.currency = 'INR',
    this.timezone = 'UTC',
    this.today = '',
    this.canView = false,
    this.canManage = false,
    this.canExpense = false,
    this.canIncome = false,
    Iterable<MoneyAccount> accounts = const [],
    Iterable<FinanceBusiness> businesses = const [],
    Iterable<PaymentRoute> routes = const [],
  }) : accounts = List.unmodifiable(accounts),
       businesses = List.unmodifiable(businesses),
       routes = List.unmodifiable(routes);
  final String name, currency, timezone, today;
  final bool canView, canManage, canExpense, canIncome;
  final List<MoneyAccount> accounts;
  final List<FinanceBusiness> businesses;
  final List<PaymentRoute> routes;
  factory FinanceCatalog.fromJson(Map<String, dynamic> j) => FinanceCatalog(
    name: j['name'],
    currency: j['currency'],
    timezone: j['timezone'],
    today: j['today'],
    canView: j['can_view'],
    canManage: j['can_manage'],
    canExpense: j['can_expense'],
    canIncome: j['can_income'],
    accounts: (j['accounts'] as List).map(
      (a) => MoneyAccount.fromJson(financeMap(a)),
    ),
    businesses: (j['businesses'] as List).map(
      (b) => FinanceBusiness.fromJson(financeMap(b)),
    ),
    routes: (j['routes'] as List).map(
      (r) => PaymentRoute.fromJson(financeMap(r)),
    ),
  );
  String? destination(String method, String? business, String? space) {
    if (method == 'cash') {
      return accounts
          .where((a) => a.kind == 'cash' && a.active)
          .firstOrNull
          ?.id;
    }
    return routes
            .where(
              (r) =>
                  r.businessId == business &&
                  r.spaceId == space &&
                  r.method == method,
            )
            .firstOrNull
            ?.accountId ??
        routes
            .where(
              (r) =>
                  r.businessId == business &&
                  r.spaceId == null &&
                  r.method == method,
            )
            .firstOrNull
            ?.accountId ??
        accounts.where((a) => a.primary && a.active).firstOrNull?.id;
  }
}

class FinanceFilter extends Equatable {
  const FinanceFilter({
    required this.from,
    required this.until,
    this.businessId,
    this.spaceId,
    this.kind,
    this.query = '',
    this.accountId,
  });
  final String from, until, query;
  final String? businessId, spaceId, kind, accountId;
  factory FinanceFilter.month(DateTime d) => FinanceFilter(
    from: bookingDate(DateTime(d.year, d.month)),
    until: bookingDate(d),
  );
  FinanceFilter dates(String from, String until) => FinanceFilter(
    from: from,
    until: until,
    businessId: businessId,
    spaceId: spaceId,
    kind: kind,
    query: query,
    accountId: accountId,
  );
  FinanceFilter scope(String? business, String? space) => FinanceFilter(
    from: from,
    until: until,
    businessId: business,
    spaceId: space,
    kind: kind,
    query: query,
    accountId: accountId,
  );
  FinanceFilter search(String q, String? kind) => FinanceFilter(
    from: from,
    until: until,
    businessId: businessId,
    spaceId: spaceId,
    kind: kind,
    query: q,
    accountId: accountId,
  );
  Map<String, Object?> toJson() => {
    'from': from,
    'until': until,
    if (businessId != null) 'business_id': businessId,
    if (spaceId != null) 'resource_id': spaceId,
    if (accountId != null) 'account_id': accountId,
    if (kind != null) 'kind': kind,
    if (query.isNotEmpty) 'q': query,
  };
  @override
  List<Object?> get props => [
    from,
    until,
    businessId,
    spaceId,
    kind,
    query,
    accountId,
  ];
}

class FinanceTotals {
  const FinanceTotals({
    this.collections = 0,
    this.extra = 0,
    this.refunds = 0,
    this.expenses = 0,
    this.income = 0,
    this.net = 0,
    this.methods = const {},
    this.incomeMethods = const {},
  });
  final int collections, extra, refunds, expenses, income, net;
  final Map<String, int> methods, incomeMethods;
  Map<String, int> get allMethods =>
      incomeMethods.isEmpty ? methods : incomeMethods;
  factory FinanceTotals.fromJson(Map<String, dynamic> j) => FinanceTotals(
    collections: j['collections_minor'],
    extra: j['extra_income_minor'],
    refunds: j['refunds_minor'],
    expenses: j['expenses_minor'],
    income: j['income_minor'],
    net: j['net_minor'],
    incomeMethods: Map.unmodifiable(
      financeMap(
        j['income_methods'] ?? j['methods'],
      ).map((k, v) => MapEntry(k, (v as num).toInt())),
    ),
    methods: Map.unmodifiable(
      financeMap(j['methods']).map((k, v) => MapEntry(k, (v as num).toInt())),
    ),
  );
}

class FinanceTrend {
  const FinanceTrend(this.month, this.income, this.expenses);
  final String month;
  final int income, expenses;
}

class FinanceOverview {
  FinanceOverview({
    required this.selected,
    required this.today,
    required this.previous,
    this.growth,
    this.outstanding = 0,
    this.previousFrom = '',
    this.previousUntil = '',
    Iterable<MoneyAccount> accounts = const [],
    Iterable<FinanceTrend> trend = const [],
  }) : accounts = List.unmodifiable(accounts),
       trend = List.unmodifiable(trend);
  final FinanceTotals selected, today, previous;
  final double? growth;
  final int outstanding;
  final String previousFrom, previousUntil;
  final List<MoneyAccount> accounts;
  final List<FinanceTrend> trend;
  factory FinanceOverview.fromJson(Map<String, dynamic> j) => FinanceOverview(
    selected: FinanceTotals.fromJson(financeMap(j['selected'])),
    today: FinanceTotals.fromJson(financeMap(j['today'])),
    previous: FinanceTotals.fromJson(financeMap(j['previous'])),
    growth: (j['growth_percent'] as num?)?.toDouble(),
    outstanding: j['outstanding_minor'],
    previousFrom: j['previous_from'],
    previousUntil: j['previous_until'],
    accounts: (j['accounts'] as List).map(
      (a) => MoneyAccount.fromJson(financeMap(a)),
    ),
    trend: (j['trend'] as List).map(
      (r) => FinanceTrend(r['month'], r['income_minor'], r['expenses_minor']),
    ),
  );
}

class FinanceLine {
  const FinanceLine(this.accountId, this.accountName, this.method, this.amount);
  final String accountId, accountName, method;
  final int amount;
  factory FinanceLine.fromJson(Map<String, dynamic> j) => FinanceLine(
    j['account_id'],
    j['account_name'],
    j['method'],
    (j['amount_minor'] as num).toInt(),
  );
}

class FinanceTransaction {
  FinanceTransaction({
    required this.id,
    required this.kind,
    required this.reason,
    required this.category,
    required this.date,
    required this.staff,
    this.reference = '',
    this.business,
    this.space,
    this.bookingId,
    this.bookingReference,
    this.customer,
    this.tariff,
    this.reversesId,
    Iterable<FinanceLine> lines = const [],
  }) : lines = List.unmodifiable(lines);
  final String id, kind, reason, category, date, staff, reference;
  final String? business,
      space,
      bookingId,
      bookingReference,
      customer,
      reversesId;
  final int? tariff;
  final List<FinanceLine> lines;
  int get net => lines.fold(0, (n, l) => n + l.amount);
  int get amount => kind == 'transfer'
      ? lines.where((l) => l.amount > 0).fold(0, (n, l) => n + l.amount)
      : net;
  factory FinanceTransaction.fromJson(Map<String, dynamic> j) =>
      FinanceTransaction(
        id: j['id'],
        kind: j['kind'],
        reason: j['reason'],
        category: j['category'],
        date: j['local_time'],
        staff: j['staff_name'],
        reference: j['reference'],
        business: j['business_name'],
        space: j['space_name'],
        bookingId: j['booking_id'],
        bookingReference: j['booking_reference'],
        customer: j['customer_name'],
        tariff: j['tariff_minor'],
        reversesId: j['reverses_id'],
        lines: (j['lines'] as List).map(
          (l) => FinanceLine.fromJson(financeMap(l)),
        ),
      );
}

class FinanceTransactionPage {
  FinanceTransactionPage(Iterable<FinanceTransaction> items, this.next)
    : items = List.unmodifiable(items);
  final List<FinanceTransaction> items;
  final int? next;
}

class FinanceDraftLine extends Equatable {
  const FinanceDraftLine({
    this.id = '',
    this.accountId,
    this.method = 'cash',
    this.amount = '',
  });
  final String? accountId;
  final String id, method, amount;
  FinanceDraftLine copyWith({
    String? id,
    String? accountId,
    String? method,
    String? amount,
    bool clearAccount = false,
  }) => FinanceDraftLine(
    id: id ?? this.id,
    accountId: clearAccount ? null : accountId ?? this.accountId,
    method: method ?? this.method,
    amount: amount ?? this.amount,
  );
  @override
  List<Object?> get props => [id, accountId, method, amount];
}
