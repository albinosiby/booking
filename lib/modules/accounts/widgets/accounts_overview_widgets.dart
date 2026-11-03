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

String financeOverviewMoney(int minor, String currency) {
  final whole = (minor.abs() ~/ 100).toString();
  final grouped = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    grouped.write(whole[i]);
    final remaining = whole.length - i - 1;
    if (remaining > 0 &&
        (currency == 'INR'
            ? remaining == 3 || remaining > 3 && (remaining - 3) % 2 == 0
            : remaining % 3 == 0)) {
      grouped.write(',');
    }
  }
  final cents = (minor.abs() % 100).toString().padLeft(2, '0');
  return '${minor < 0 ? '−' : ''}${currency == 'INR' ? '₹' : currency} $grouped.$cents';
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
    if (b == null) return 'All Businesses';
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
    final apply = await showAdaptiveSheet<bool>(
      context: context,
      showDragHandle: false,
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
    final choice = await showAdaptiveSheet<String>(
      context: context,
      showClose: false,
      showDragHandle: false,
      maxWidth: 420,
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
    final income = totals.income < 0 ? 0 : totals.income;
    final out = totals.expenses + totals.refunds;
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B7723), Color(0xFF168B21), Color(0xFF39AF20)],
        ),
        border: Border.all(
          color: const Color(0xFF9BEB68).withValues(alpha: .45),
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _FinanceFlowBackdrop()),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: Color(0xFFC6F7A9),
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Net cash flow · $period',
                        style: const TextStyle(
                          color: Color(0xFFE5FFE0),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    financeOverviewMoney(totals.net, currency),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.7,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _flow(
                      Icons.south_west_rounded,
                      'In',
                      income,
                      const Color(0xFF9DFF65),
                    ),
                    _flow(
                      Icons.north_east_rounded,
                      'Out',
                      out,
                      const Color(0xFFFF776F),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Out covers expenses and refunds',
                  style: TextStyle(color: Color(0xFFE5FFE0), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _flow(IconData icon, String label, int amount, Color accent) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF064C1C).withValues(alpha: .42),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                '$label ${financeOverviewMoney(amount, currency)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
}

class _FinanceFlowBackdrop extends CustomPainter {
  const _FinanceFlowBackdrop();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final curve = Path()
      ..moveTo(w * .55, h * .83)
      ..cubicTo(w * .65, h * .66, w * .66, h * .48, w * .78, h * .5)
      ..cubicTo(w * .89, h * .53, w * .88, h * .38, w * .98, h * .23);
    canvas.drawPath(
      curve,
      Paint()
        ..color = Colors.white.withValues(alpha: .13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
    final bars = Paint()
      ..color = const Color(0xFFAAEB66).withValues(alpha: .48);
    for (var i = 0; i < 4; i++) {
      final height = 12.0 + i * 11;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(w - 86 + i * 17, h - 32 - height, 11, height),
          const Radius.circular(3),
        ),
        bars,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class FinanceDuesBanner extends StatelessWidget {
  const FinanceDuesBanner({
    super.key,
    required this.amount,
    required this.currency,
    this.onTap,
  });
  final int amount;
  final String currency;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final due = amount > 0;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF343519), Color(0xFF252B1C)],
          ),
          border: Border.all(color: financeAmber.withValues(alpha: .16)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Icon(
                  due
                      ? Icons.receipt_long_outlined
                      : Icons.check_circle_outline,
                  color: financeAmber,
                  size: 28,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        due ? 'Booking dues' : 'No booking dues',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Outstanding at period end',
                        style: const TextStyle(
                          color: Color(0xFFE6E6DE),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (due) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        financeOverviewMoney(amount, currency),
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
                if (onTap != null) ...[
                  const SizedBox(width: 6),
                  const Icon(Icons.chevron_right, color: financeAmber),
                ],
              ],
            ),
          ),
        ),
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
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1B371C), Color(0xFF132718)],
                        ),
                        border: Border.all(
                          color: const Color(0xFF89CB70).withValues(alpha: .35),
                        ),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Icon(a.icon, color: AppColors.lime, size: 26),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      a.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
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

class FinanceTodayCollectionHeading extends StatelessWidget {
  const FinanceTodayCollectionHeading({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 12),
    child: Row(
      children: [
        Expanded(
          child: Text(
            "Today's collection",
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: .5),
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.calendar_today_outlined, size: 16),
              SizedBox(width: 7),
              Text('Today', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ],
    ),
  );
}

class FinanceTodayCollectionCard extends StatelessWidget {
  const FinanceTodayCollectionCard({
    super.key,
    required this.total,
    required this.methods,
    required this.currency,
  });
  final int total;
  final Map<String, int> methods;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final width = MediaQuery.sizeOf(context).width;
    final scale = MediaQuery.textScalerOf(context).scale(1);
    final stacked = width < 370 || scale > 1.25;
    final summary = Row(
      children: [
        Image.asset(
          'assets/branding/collection_wallet_icon.png',
          width: 58,
          height: 58,
          semanticLabel: 'Collections wallet',
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Booking collections today',
                maxLines: 2,
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  financeOverviewMoney(total, currency),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
    final breakdown = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final method in financeMethods)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: _methodColors[method],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    financeLabel(method),
                    style: TextStyle(color: scheme.onSurface, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 3),
                Text(
                  financeOverviewMoney(methods[method] ?? 0, currency),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B211E) : scheme.surface,
        border: Border.all(color: scheme.outline.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(24),
      ),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                summary,
                const SizedBox(height: 14),
                Divider(color: scheme.outline.withValues(alpha: .4)),
                const SizedBox(height: 8),
                breakdown,
              ],
            )
          : IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(flex: 9, child: summary),
                  VerticalDivider(
                    color: scheme.outline.withValues(alpha: .5),
                    thickness: 1,
                    width: 22,
                  ),
                  Expanded(flex: 10, child: breakdown),
                ],
              ),
            ),
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
          child: Align(
            alignment: Alignment.centerRight,
            child: Text(
              amount,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
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
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    financeMoney(total, currency),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
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
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          financeMoney(a.balance ?? 0, currency),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
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
