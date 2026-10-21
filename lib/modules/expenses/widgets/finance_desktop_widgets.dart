import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../../design_system/design_system.dart';
import '../../accounts/models/accounts_models.dart' show financeMoney;
import '../../accounts/widgets/finance_ledger_widgets.dart'
    show FinanceShare, financeShareColors;
import '../../accounts/widgets/monthly_finance_chart.dart' show financeMonths;

/// Desktop page heading for the finance ledgers (Income, Expenses): large
/// title and context line on the left, outlined icon actions on the right.
class FinanceDesktopHeader extends StatelessWidget {
  const FinanceDesktopHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });
  final String title, subtitle;
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineLarge),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: .65),
                ),
              ),
            ],
          ),
        ),
        for (final (i, a) in actions.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          a,
        ],
      ],
    );
  }
}

/// One-line monthly/yearly switch with a period stepper for desktop toolbars.
/// Same behaviour as the stacked `FinancePeriodBar` used on phones.
class FinanceDesktopPeriod extends StatelessWidget {
  const FinanceDesktopPeriod({
    super.key,
    required this.anchor,
    required this.yearly,
    required this.onChanged,
  });
  final DateTime anchor;
  final bool yearly;
  final void Function(DateTime anchor, bool yearly) onChanged;

  Future<void> _choose(BuildContext context) async {
    final d = await showDatePicker(
      context: context,
      initialDate: anchor,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100, 12, 31),
      helpText: yearly
          ? 'Choose a date in the year'
          : 'Choose a date in the month',
    );
    if (d != null) onChanged(d, yearly);
  }

  void _step(int by) => onChanged(
    yearly
        ? DateTime(anchor.year + by)
        : DateTime(anchor.year, anchor.month + by),
    yearly,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final last = yearly
        ? DateTime(anchor.year, 12, 31)
        : DateTime(anchor.year, anchor.month + 1, 0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SegmentedButton<bool>(
          showSelectedIcon: false,
          style: const ButtonStyle(
            visualDensity: VisualDensity(horizontal: -1, vertical: -1),
          ),
          segments: const [
            ButtonSegment(value: false, label: Text('Monthly')),
            ButtonSegment(value: true, label: Text('Yearly')),
          ],
          selected: {yearly},
          onSelectionChanged: (v) => onChanged(anchor, v.first),
        ),
        const SizedBox(width: 12),
        Container(
          height: 44,
          decoration: BoxDecoration(
            color: scheme.surface,
            border: Border.all(color: scheme.outline.withValues(alpha: .5)),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Previous period',
                visualDensity: VisualDensity.compact,
                onPressed: () => _step(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Tooltip(
                message: 'Choose period',
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _choose(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.calendar_month_outlined,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          yearly
                              ? '${anchor.year}'
                              : '${financeMonths[anchor.month - 1]} ${anchor.year}',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '1 ${financeMonths[yearly ? 0 : anchor.month - 1]} – ${last.day} ${financeMonths[last.month - 1]}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next period',
                visualDensity: VisualDensity.compact,
                onPressed: () => _step(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Side panel offering the report downloads directly on desktop.
class FinanceExportCard extends StatelessWidget {
  const FinanceExportCard({
    super.key,
    required this.note,
    required this.exporting,
    required this.onExport,
  });
  final String note;
  final bool exporting;
  final ValueChanged<String> onExport;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String format, IconData icon, String label) => ListTile(
      key: ValueKey('desktop-export-$format'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18),
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: const Icon(Icons.download_outlined, size: 20),
      enabled: !exporting,
      onTap: () => onExport(format),
    );
    return AppListCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
          child: Row(
            children: [
              Expanded(child: Text(note, style: theme.textTheme.bodySmall)),
              if (exporting) const AppSavingDots(),
            ],
          ),
        ),
        row('pdf', Icons.picture_as_pdf_outlined, 'PDF report'),
        row('xlsx', Icons.table_chart_outlined, 'Excel workbook'),
      ],
    );
  }
}

/// Empty state sized for a desktop panel.
class FinanceEmptyCard extends StatelessWidget {
  const FinanceEmptyCard({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });
  final IconData icon;
  final String title, message;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Center(
          child: Column(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: .12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: scheme.primary),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ranked category or source totals for desktop side panels: each row shows
/// its share as a bar, with the amount aligned to the right edge. Rows with
/// an ID select that filter, like the phone breakdown.
class FinanceShareList extends StatefulWidget {
  const FinanceShareList({
    super.key,
    required this.shares,
    required this.currency,
    required this.onSelect,
    this.selected,
  });
  final List<FinanceShare> shares;
  final String currency;
  final String? selected;
  final ValueChanged<String> onSelect;
  @override
  State<FinanceShareList> createState() => _FinanceShareListState();
}

class _FinanceShareListState extends State<FinanceShareList> {
  static const preview = 6;
  var all = false;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final shares = widget.shares;
    final total = shares.fold<int>(0, (n, s) => n + math.max(0, s.total));
    Color color(int i) => financeShareColors[i % financeShareColors.length];
    final shown = all ? shares.length : math.min(preview, shares.length);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, s) in shares.take(shown).indexed)
            Material(
              color: s.id != null && s.id == widget.selected
                  ? scheme.primary.withValues(alpha: .1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: s.id == null ? null : () => widget.onSelect(s.id!),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color(i).withValues(alpha: .16),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(s.icon, size: 18, color: color(i)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    s.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  financeMoney(s.total, widget.currency),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: total == 0
                                          ? 0
                                          : math.max(0, s.total) / total,
                                      minHeight: 6,
                                      color: color(i),
                                      backgroundColor: scheme.outline
                                          .withValues(alpha: .25),
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 44,
                                  child: Text(
                                    total == 0
                                        ? '0%'
                                        : '${(math.max(0, s.total) / total * 100).round()}%',
                                    textAlign: TextAlign.right,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (shares.length > preview)
            TextButton(
              onPressed: () => setState(() => all = !all),
              child: Text(all ? 'Show fewer' : 'Show all ${shares.length}'),
            ),
        ],
      ),
    );
  }
}
