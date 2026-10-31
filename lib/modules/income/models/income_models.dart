import '../../accounts/models/accounts_models.dart';
import '../../expenses/models/expense_models.dart' show expenseDate;

/// Sources that are not income categories.
const incomeBookings = 'bookings', incomeAdmissions = 'admissions';

class IncomeCategory {
  const IncomeCategory(this.id, this.name, {this.active = true});
  final String id, name;
  final bool active;
}

class IncomeFilter {
  const IncomeFilter({
    required this.anchor,
    this.yearly = false,
    this.day,
    this.source,
    this.businessId,
    this.spaceId,
    this.accountId,
    this.query = '',
  });
  final DateTime anchor;
  final bool yearly;

  /// Optional calendar day for fetching a single day's ledger.
  final int? day;

  /// [incomeBookings], [incomeAdmissions] or an income category ID.
  final String? source;
  final String? businessId, spaceId, accountId;
  final String query;
  String get from =>
      expenseDate(DateTime(anchor.year, yearly ? 1 : anchor.month, day ?? 1));
  String get until => day != null
      ? from
      : expenseDate(
          yearly
              ? DateTime(anchor.year + 1, 1, 0)
              : DateTime(anchor.year, anchor.month + 1, 0),
        );
  IncomeFilter copy({
    DateTime? anchor,
    bool? yearly,
    int? day,
    String? source,
    String? businessId,
    String? spaceId,
    String? accountId,
    String? query,
    bool clearSource = false,
    bool clearScope = false,
    bool clearAccount = false,
  }) => IncomeFilter(
    anchor: anchor ?? this.anchor,
    yearly: yearly ?? this.yearly,
    day: day ?? this.day,
    source: clearSource ? null : source ?? this.source,
    businessId: clearScope ? businessId : businessId ?? this.businessId,
    spaceId: clearScope ? spaceId : spaceId ?? this.spaceId,
    accountId: clearAccount ? null : accountId ?? this.accountId,
    query: query ?? this.query,
  );
  Map<String, Object?> toQuery() => {
    'from': from,
    'until': until,
    if (source != null) 'source': source,
    if (businessId != null) 'business_id': businessId,
    if (spaceId != null) 'resource_id': spaceId,
    if (accountId != null) 'account_id': accountId,
    if (query.trim().isNotEmpty) 'q': query.trim(),
  };
}

class IncomeSourceTotal {
  const IncomeSourceTotal(this.id, this.name, this.total);
  final String? id;
  final String name;
  final int total;
}

int incomeInt(dynamic n) => n is num ? n.toInt() : int.tryParse('$n') ?? 0;

class IncomeDailyTotal {
  const IncomeDailyTotal({
    required this.gross,
    this.refunds = 0,
    this.incomeCount = 0,
    this.refundCount = 0,
    this.methods = const {},
    this.purposes = const [],
    this.purposeCount = 0,
    this.methodBreakdownAvailable = true,
  });
  final int gross, refunds, incomeCount, refundCount;
  final Map<String, int> methods;
  final List<IncomePurposeTotal> purposes;
  final int purposeCount;
  final bool methodBreakdownAvailable;
  int get net => gross - refunds;
  int get cash => methods['cash'] ?? 0;
  int get bank => methods.entries
      .where((entry) => entry.key != 'cash')
      .fold(0, (total, entry) => total + entry.value);
}

class IncomePurposeTotal {
  const IncomePurposeTotal(this.purpose, this.space, this.amount);
  final String purpose, space;
  final int amount;
}

class IncomeSummary {
  IncomeSummary({
    required this.total,
    required this.refunds,
    required this.count,
    Map<String, int> days = const {},
    Map<String, IncomeDailyTotal> dailyTotals = const {},
    Map<String, int> methods = const {},
    this.methodBreakdownAvailable = true,
    List<IncomeSourceTotal> sources = const [],
  }) : days = Map.unmodifiable(days),
       dailyTotals = Map.unmodifiable(
         dailyTotals.isEmpty
             ? {
                 for (final entry in days.entries)
                   entry.key: IncomeDailyTotal(gross: entry.value),
               }
             : dailyTotals,
       ),
       methods = Map.unmodifiable(methods),
       sources = List.unmodifiable(sources);
  final int total, refunds, count;
  final Map<String, int> days;
  final Map<String, IncomeDailyTotal> dailyTotals;
  final Map<String, int> methods;
  final bool methodBreakdownAvailable;
  final List<IncomeSourceTotal> sources;
  int get net => total - refunds;
  int get cash => methods['cash'] ?? 0;
  int get bank => methods.entries
      .where((entry) => entry.key != 'cash')
      .fold(0, (total, entry) => total + entry.value);
  factory IncomeSummary.fromJson(Map<String, dynamic> j) => IncomeSummary(
    total: incomeInt(j['total_minor']),
    refunds: incomeInt(j['refunds_minor']),
    count: incomeInt(j['count']),
    days: {for (final r in j['days']) r['day']: incomeInt(r['total_minor'])},
    dailyTotals: {
      for (final r in j['days'])
        r['day']: IncomeDailyTotal(
          gross: incomeInt(r['total_minor']),
          refunds: incomeInt(r['refunds_minor']),
          incomeCount: incomeInt(r['income_count']),
          refundCount: incomeInt(r['refund_count']),
          methods: {
            for (final method in (r['methods'] as List? ?? const []))
              method['method'] as String: incomeInt(method['total_minor']),
          },
          purposes: [
            for (final purpose in (r['purposes'] as List? ?? const []))
              IncomePurposeTotal(
                purpose['purpose'] as String,
                purpose['space'] as String,
                incomeInt(purpose['total_minor']),
              ),
          ],
          purposeCount: incomeInt(r['purpose_count']),
          methodBreakdownAvailable: r.containsKey('methods'),
        ),
    },
    methodBreakdownAvailable: j.containsKey('methods'),
    methods: {
      for (final method in (j['methods'] as List? ?? const []))
        method['method'] as String: incomeInt(method['total_minor']),
    },
    sources: [
      for (final r in j['sources'])
        IncomeSourceTotal(
          r['source_id'],
          r['source_name'],
          incomeInt(r['total_minor']),
        ),
    ],
  );
  List<int> bars(IncomeFilter f) => List.generate(
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

class IncomeItem {
  const IncomeItem(this.entry, this.source, {this.refund = false});
  final FinanceTransaction entry;
  final String source;
  final bool refund;
  factory IncomeItem.fromJson(Map<String, dynamic> j) => IncomeItem(
    FinanceTransaction.fromJson({
      ...j,
      'reference': j['reference'] ?? '',
      'tariff_minor': j['tariff_minor'] == null
          ? null
          : incomeInt(j['tariff_minor']),
    }),
    j['source_name'] ?? 'Other',
    refund: j['is_refund'] == true,
  );
}

class IncomePage {
  IncomePage(Iterable<IncomeItem> items, this.next)
    : items = List.unmodifiable(items);
  final List<IncomeItem> items;
  final int? next;
}
