import '../models/expense_models.dart';
import '../../accounts/models/accounts_models.dart';

int expenseInt(dynamic n) => n is num ? n.toInt() : int.tryParse('$n') ?? 0;

class ExpenseMapper {
  static ExpenseCategory category(Map<String, dynamic> j) =>
      ExpenseCategory(j['id'], j['name'], active: j['active'] == true);
  static ExpenseSummary summary(Map<String, dynamic> j) => ExpenseSummary(
    expenseInt(j['total_minor']),
    expenseInt(j['count']),
    {for (final r in j['days']) r['day']: expenseInt(r['total_minor'])},
    [
      for (final r in j['categories'])
        ExpenseCategoryTotal(
          r['category_id'],
          r['category_name'],
          expenseInt(r['total_minor']),
        ),
    ],
    gross: expenseInt(j['gross_minor'] ?? j['total_minor']),
    reversals: expenseInt(j['reversals_minor']),
    methodBreakdownAvailable: j.containsKey('methods'),
    methods: {
      for (final method in (j['methods'] as List? ?? const []))
        method['method'] as String: expenseInt(method['total_minor']),
    },
    dailyTotals: {
      for (final r in j['days'])
        r['day']: ExpenseDailyTotal(
          gross: expenseInt(r['gross_minor'] ?? r['total_minor']),
          reversals: expenseInt(r['reversals_minor']),
          expenseCount: expenseInt(r['expense_count']),
          reversalCount: expenseInt(r['reversal_count']),
          methods: {
            for (final method in (r['methods'] as List? ?? const []))
              method['method'] as String: expenseInt(method['total_minor']),
          },
          purposes: [
            for (final purpose in (r['purposes'] as List? ?? const []))
              ExpensePurposeTotal(
                purpose['category'] as String,
                purpose['reason'] as String,
                purpose['space'] as String,
                expenseInt(purpose['total_minor']),
              ),
          ],
          purposeCount: expenseInt(r['purpose_count']),
          methodBreakdownAvailable: r.containsKey('methods'),
        ),
    },
  );
  static ExpenseInvoice invoice(Map<String, dynamic> j) => ExpenseInvoice(
    id: j['id'],
    name: j['name'],
    type: j['content_type'],
    size: expenseInt(j['size_bytes']),
    ready: j['status'] == 'ready',
  );
  static ExpenseItem item(Map<String, dynamic> j) => ExpenseItem(
    id: j['id'],
    reason: j['reason'],
    category: j['category_name'] ?? j['category'] ?? 'Other',
    date: j['local_date'] ?? j['occurred_at'].toString(),
    amount: expenseInt(j['amount_minor']),
    categoryId: j['category_id'] ?? j['expense_category_id'],
    business: j['business_name'],
    space: j['space_name'],
    reference: j['reference'] ?? '',
    staff: j['staff_name'] ?? '',
    originalId: j['reverses_id'],
    invoicesCount: expenseInt(j['attachments_count']),
    lines: [
      for (final l in j['lines'] ?? [])
        FinanceLine(
          l['account_id'],
          l['account_name'],
          l['method'],
          expenseInt(l['amount_minor']),
        ),
    ],
  );
  static Map<String, Object?> filter(ExpenseFilter f) => {
    'from': f.from,
    'until': f.until,
    if (f.categoryId != null) 'category_id': f.categoryId,
    if (f.businessId != null) 'business_id': f.businessId,
    if (f.spaceId != null) 'resource_id': f.spaceId,
    if (f.accountId != null) 'account_id': f.accountId,
    if (f.query.trim().isNotEmpty) 'q': f.query.trim(),
  };
  static Map<String, Object?> draft(ExpenseDraft d) => {
    'command_key': d.commandId,
    'kind': 'expense',
    'expense_category_id': d.categoryId,
    'category': d.categoryName,
    'reason': d.reason,
    'reference': d.reference,
    'business_id': d.businessId,
    'resource_id': d.spaceId,
    'occurred_at': d.occurredAt.toUtc().toIso8601String(),
    'lines': [
      for (final l in d.payments)
        {
          'account_id': l.accountId,
          'method': l.method,
          'amount_minor': l.amount,
        },
    ],
  };
}
