import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../bookings/models/booking_models.dart';
import '../models/accounts_models.dart';
import 'accounts_widgets.dart';
import 'finance_ledger_widgets.dart';

const financeMethods = ['cash', 'upi', 'card', 'bank_transfer'];
const financeAmber = Color(0xFFE0A33A);
const _methodColors = {
  'cash': AppColors.lime,
  'upi': Color(0xFF4FA3E0),
  'card': Color(0xFFB07CE8),
  'bank_transfer': financeAmber,
};
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _shortDate(DateTime d, {bool year = false}) =>
    '${d.day} ${_months[d.month - 1]}${year ? ' ${d.year}' : ''}';

String financeRangeLabel(FinanceFilter f) {
  final from = DateTime.parse(f.from), until = DateTime.parse(f.until);
  if (f.from == f.until) return _shortDate(from, year: true);
  return '${_shortDate(from, year: from.year != until.year)} – ${_shortDate(until, year: true)}';
}

String financePeriodLabel(FinanceFilter f, String? today) {
  final t = DateTime.tryParse(today ?? '') ?? DateTime.now();
  if (f.until != bookingDate(t)) return financeRangeLabel(f);
  final from = DateTime.parse(f.from);
  if (f.from == f.until) return 'Today';
  if (from == DateTime(t.year, t.month)) return 'This month';
  if (from == DateTime(t.year)) return 'This year';
  return financeRangeLabel(f);
}

String financeDayLabel(String stamp, String? today) {
  final day = DateTime.tryParse(
    stamp.length >= 10 ? stamp.substring(0, 10) : '',
  );
  if (day == null) return stamp;
  final t = DateTime.tryParse(today ?? '') ?? DateTime.now();
  final diff = (DateTime(t.year, t.month, t.day).difference(day).inHours / 24)
      .round();
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  return _shortDate(day, year: day.year != t.year);
}

class FinanceFilterBar extends StatelessWidget {
  const FinanceFilterBar({
    super.key,
    required this.catalog,
    required this.filter,
    required this.onChanged,
  });
  final FinanceCatalog catalog;
  final FinanceFilter filter;
  final ValueChanged<FinanceFilter> onChanged;

  String get _scope {
    final b = catalog.businesses
        .where((b) => b.id == filter.businessId)
        .firstOrNull;
    if (b == null) return 'All businesses';
    return b.spaces.where((s) => s.id == filter.spaceId).firstOrNull?.name ??
        b.name;
  }

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      FinanceFilterChip(
        icon: Icons.storefront_outlined,
        label: _scope,
        tooltip: 'Choose business',
        onTap: () => _pickScope(context),
      ),
      FinanceFilterChip(
        icon: Icons.calendar_today_outlined,
        label: financePeriodLabel(filter, catalog.today),
        tooltip: 'Choose period',
        onTap: () => _pickPeriod(context),
      ),
    ],
  );

  Future<void> _pickScope(BuildContext context) async {
    String? business = filter.businessId, space = filter.spaceId;
    final apply = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            8,
            20,
            24 + MediaQuery.viewInsetsOf(c).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Show figures for',
                style: Theme.of(c).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FinanceScopePicker(
                catalog: catalog,
                business: business,
                space: space,
                onChanged: (b, r) => set(() {
                  business = b;
                  space = r;
                }),
              ),
              const SizedBox(height: 20),
              AppButton(
                label: 'Apply',
                onPressed: () => Navigator.pop(c, true),
              ),
            ],
          ),
        ),
      ),
    );
    if (apply == true) onChanged(filter.scope(business, space));
  }

  Future<void> _pickPeriod(BuildContext context) async {
    final t = DateTime.tryParse(catalog.today) ?? DateTime.now();
    final current = financePeriodLabel(filter, catalog.today);
    const presets = ['Today', 'This month', 'This year'];
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (c) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in [...presets, 'Custom range'])
              ListTile(
                title: Text(p),
                subtitle: p == 'Custom range' && !presets.contains(current)
                    ? Text(current)
                    : null,
                trailing:
                    p == current ||
                        (p == 'Custom range' && !presets.contains(current))
                    ? Icon(Icons.check, color: Theme.of(c).colorScheme.primary)
                    : null,
                onTap: () => Navigator.pop(c, p),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'Custom range') {
      final next = await chooseFinanceDates(context, filter);
      if (next != null) onChanged(next);
      return;
    }
    final start = choice == 'Today'
        ? t
        : choice == 'This month'
        ? DateTime(t.year, t.month)
        : DateTime(t.year);
    onChanged(filter.dates(bookingDate(start), bookingDate(t)));
  }
}

class FinanceNetCard extends StatelessWidget {
  const FinanceNetCard({
    super.key,
    required this.totals,
    required this.period,
    required this.currency,
  });
  final FinanceTotals totals;
  final String period, currency;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme, on = scheme.onPrimary;
    final income = totals.income < 0 ? 0 : totals.income,
        out = totals.expenses + totals.refunds;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: on),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Net cash flow · $period',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: on.withValues(alpha: .8),
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                financeMoney(totals.net, currency),
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 6,
                child: income + out <= 0
                    ? ColoredBox(color: on.withValues(alpha: .2))
                    : Row(
                        children: [
                          if (income > 0)
                            Expanded(
                              flex: income,
                              child: ColoredBox(color: on),
                            ),
                          if (out > 0)
                            Expanded(
                              flex: out,
                              child: ColoredBox(
                                color: on.withValues(alpha: .3),
                              ),
                            ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 16,
              runSpacing: 6,
              children: [
                _flow(Icons.south_west, 'In', income),
                _flow(Icons.north_east, 'Out', out),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Out covers expenses and refunds',
              style: TextStyle(fontSize: 11, color: on.withValues(alpha: .7)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _flow(IconData icon, String label, int amount) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 14),
      const SizedBox(width: 4),
      Text(
        '$label ${financeMoney(amount, currency)}',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class FinanceDuesBanner extends StatelessWidget {
  const FinanceDuesBanner({
    super.key,
    required this.amount,
    required this.currency,
  });
  final int amount;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final due = amount > 0, scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: due
            ? financeAmber.withValues(alpha: .16)
            : scheme.outline.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            due ? Icons.receipt_long_outlined : Icons.check_circle_outline,
            color: due ? financeAmber : scheme.primary,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  due ? 'Booking dues' : 'No booking dues',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  'Outstanding at period end',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (due) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                financeMoney(amount, currency),
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class FinanceAction {
  const FinanceAction(this.icon, this.label, this.onTap);
  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

class FinanceQuickActions extends StatelessWidget {
  const FinanceQuickActions(this.actions, {super.key});
  final List<FinanceAction> actions;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final a in actions)
          Expanded(
            child: InkWell(
              onTap: a.onTap,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(a.icon, color: scheme.primary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      a.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class FinanceAmountRow extends StatelessWidget {
  const FinanceAmountRow(this.label, this.amount, {super.key, this.color});
  final String label, amount;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        if (color != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(child: Text(label)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            amount,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}

class FinanceMethodSplit extends StatelessWidget {
  const FinanceMethodSplit({
    super.key,
    required this.title,
    required this.total,
    required this.methods,
    required this.currency,
    this.footer = const [],
  });
  final String title, currency;
  final int total;
  final Map<String, int> methods;
  final List<Widget> footer;
  @override
  Widget build(BuildContext context) {
    final amounts = {for (final m in financeMethods) m: methods[m] ?? 0};
    final sum = amounts.values.where((v) => v > 0).fold(0, (n, v) => n + v);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  financeMoney(total, currency),
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: sum == 0
                  ? ColoredBox(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: .3),
                    )
                  : Row(
                      children: [
                        for (final e in amounts.entries)
                          if (e.value > 0)
                            Expanded(
                              flex: e.value,
                              child: ColoredBox(color: _methodColors[e.key]!),
                            ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 10),
          for (final e in amounts.entries)
            FinanceAmountRow(
              financeLabel(e.key),
              financeMoney(e.value, currency),
              color: _methodColors[e.key],
            ),
          if (footer.isNotEmpty) ...[const Divider(height: 20), ...footer],
        ],
      ),
    );
  }
}

class FinanceAccountsList extends StatelessWidget {
  const FinanceAccountsList({
    super.key,
    required this.accounts,
    required this.currency,
    required this.onTap,
  });
  final List<MoneyAccount> accounts;
  final String currency;
  final ValueChanged<MoneyAccount> onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, a) in accounts.indexed) ...[
            if (i > 0) const Divider(height: 1, indent: 52),
            InkWell(
              onTap: () => onTap(a),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      a.kind == 'cash'
                          ? Icons.payments_outlined
                          : a.kind == 'clearing'
                          ? Icons.pending_outlined
                          : Icons.account_balance_outlined,
                      color: a.kind == 'clearing' ? financeAmber : null,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            a.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (a.primary)
                            Text(
                              'Primary',
                              style: TextStyle(
                                color: scheme.primary,
                                fontSize: 12,
                              ),
                            ),
                          if (a.kind == 'clearing')
                            const Text(
                              'Allocate to the bank that received these funds',
                              style: TextStyle(
                                color: financeAmber,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        financeMoney(a.balance ?? 0, currency),
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class FinanceTransactionGroups extends StatelessWidget {
  const FinanceTransactionGroups({
    super.key,
    required this.entries,
    required this.currency,
    required this.onTap,
    this.today,
    this.labelOf,
  });
  final List<FinanceTransaction> entries;
  final String currency;
  final String? today;
  final ValueChanged<FinanceTransaction> onTap;
  final String? Function(FinanceTransaction)? labelOf;
  @override
  Widget build(BuildContext context) {
    final groups = <List<FinanceTransaction>>[];
    for (final e in entries) {
      if (groups.isEmpty ||
          !groups.last.first.date.startsWith(
            e.date.length >= 10 ? e.date.substring(0, 10) : e.date,
          )) {
        groups.add([e]);
      } else {
        groups.last.add(e);
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final g in groups) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              financeDayLabel(g.first.date, today),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (final (i, e) in g.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 64),
                  FinanceTransactionTile(
                    entry: e,
                    currency: currency,
                    onTap: () => onTap(e),
                    label: labelOf?.call(e),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }
}
