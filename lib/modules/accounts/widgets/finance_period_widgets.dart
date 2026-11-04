import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/accounts_models.dart';
import 'monthly_finance_chart.dart';

/// Monthly/yearly switch with a period stepper, shared by the Expenses and
/// Income pages. Tapping the period label opens a calendar.
class FinancePeriodBar extends StatelessWidget {
  const FinancePeriodBar({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            border: Border.all(color: scheme.outline.withValues(alpha: .35)),
            borderRadius: BorderRadius.circular(26),
          ),
          child: Row(
            children: [
              _FinancePeriodOption(
                label: 'Monthly',
                selected: !yearly,
                onTap: () => onChanged(anchor, false),
              ),
              _FinancePeriodOption(
                label: 'Yearly',
                selected: yearly,
                onTap: () => onChanged(anchor, true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .06),
            border: Border.all(color: scheme.outline.withValues(alpha: .38)),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Previous period',
                onPressed: () => _step(-1),
                icon: Icon(Icons.chevron_left, color: scheme.primary),
              ),
              Expanded(
                child: Tooltip(
                  message: 'Choose period',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _choose(context),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Column(
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  yearly
                                      ? '${anchor.year}'
                                      : '${financeMonths[anchor.month - 1]} ${anchor.year}',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(
                                Icons.calendar_month_outlined,
                                size: 16,
                                color: scheme.primary,
                              ),
                              const SizedBox(width: 3),
                              const Icon(Icons.keyboard_arrow_down, size: 17),
                            ],
                          ),
                          Text(
                            '1 ${financeMonths[yearly ? 0 : anchor.month - 1]} – ${last.day} ${financeMonths[last.month - 1]}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Next period',
                onPressed: () => _step(1),
                icon: Icon(Icons.chevron_right, color: scheme.primary),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FinancePeriodOption extends StatelessWidget {
  const _FinancePeriodOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Material(
      color: selected ? const Color(0xFF73E329) : Colors.transparent,
      borderRadius: BorderRadius.circular(23),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF102008)
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Bar per day (monthly) or per month (yearly), sized to fit the card.
/// Tapping a month drills into it; tapping a day selects its ledger.
class FinancePeriodChart extends StatelessWidget {
  const FinancePeriodChart({
    super.key,
    required this.values,
    required this.yearly,
    required this.currency,
    required this.onMonth,
    required this.yearlyTitle,
    required this.monthlyTitle,
    this.note,
    this.onDay,
    this.selectedDay,
    this.anchor,
    this.onClearDay,
    this.showHeading = true,
  });
  final List<int> values;
  final bool yearly;
  final String currency, yearlyTitle, monthlyTitle;
  final String? note;
  final ValueChanged<int> onMonth;
  final ValueChanged<int>? onDay;
  final int? selectedDay;
  final DateTime? anchor;
  final VoidCallback? onClearDay;
  final bool showHeading;

  String _name(int i) => yearly ? financeMonths[i] : 'Day ${i + 1}';

  @override
  Widget build(BuildContext context) {
    const height = 120.0;
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final max = values.fold<int>(0, (n, v) => math.max(n, v.abs()));
    final peak = max == 0 ? -1 : values.indexWhere((v) => v.abs() == max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Text(
            yearly ? yearlyTitle : monthlyTitle,
            style: theme.textTheme.titleSmall,
          ),
          if (peak >= 0)
            Text(
              'Highest: ${_name(peak)} · ${financeMoney(values[peak], currency)}',
              style: theme.textTheme.bodySmall,
            ),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final column = constraints.maxWidth / math.max(1, values.length);
            final bar = math.min(yearly ? 18.0 : 8.0, column * .6);
            String label(int i) {
              if (yearly) {
                return column >= 30
                    ? financeMonths[i]
                    : financeMonths[i].substring(0, 1);
              }
              final day = i + 1;
              return day == 1 || day % 5 == 0 ? '$day' : '';
            }

            VoidCallback? select(int i) => yearly
                ? () => onMonth(i + 1)
                : onDay == null
                ? null
                : () => onDay!(i + 1);

            return Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Semantics(
                      button: yearly || onDay != null,
                      selected: !yearly && selectedDay == i + 1,
                      label:
                          '${_name(i)}: ${financeMoney(values[i], currency)}',
                      excludeSemantics: true,
                      onTap: select(i),
                      child: Tooltip(
                        message:
                            '${_name(i)} · ${financeMoney(values[i], currency)}',
                        child: InkWell(
                          key: ValueKey('finance-bar-$i'),
                          onTap: select(i),
                          borderRadius: BorderRadius.circular(6),
                          child: Column(
                            children: [
                              Container(
                                height: height,
                                decoration: BoxDecoration(
                                  color: !yearly && selectedDay == i + 1
                                      ? scheme.primary.withValues(alpha: .12)
                                      : null,
                                  borderRadius: BorderRadius.circular(6),
                                  border: !yearly && selectedDay == i + 1
                                      ? Border.all(color: scheme.primary)
                                      : null,
                                ),
                                child: Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Container(
                                    width: bar,
                                    height: values[i] == 0
                                        ? 2
                                        : math.max(
                                            4,
                                            height * values[i].abs() / max,
                                          ),
                                    decoration: BoxDecoration(
                                      color: values[i] == 0
                                          ? scheme.outlineVariant
                                          : values[i] < 0
                                          ? scheme.error
                                          : scheme.primary.withValues(
                                              alpha: i == peak ? 1 : .55,
                                            ),
                                      borderRadius: BorderRadius.vertical(
                                        top: Radius.circular(bar / 2),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                label(i),
                                maxLines: 1,
                                softWrap: false,
                                overflow: TextOverflow.visible,
                                textScaler: TextScaler.noScaling,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 10,
                                  color: !yearly && selectedDay == i + 1
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        if (!yearly && onDay != null && selectedDay == null) ...[
          const SizedBox(height: 10),
          Text(
            'Tap a day to view its transactions.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (!yearly &&
            selectedDay != null &&
            anchor != null &&
            onClearDay != null)
          FinanceDaySelection(
            date: DateTime(anchor!.year, anchor!.month, selectedDay!),
            total: values[selectedDay! - 1],
            currency: currency,
            onClear: onClearDay!,
          ),
        if (note != null) ...[
          const SizedBox(height: 10),
          Text(note!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Compact report chart with an optional line view; bar view keeps the
/// existing per-day and per-month touch targets.
class FinanceTrendChart extends StatefulWidget {
  const FinanceTrendChart({
    super.key,
    required this.values,
    required this.yearly,
    required this.currency,
    required this.title,
    required this.onMonth,
    this.onDay,
    this.selectedDay,
    this.anchor,
    this.note,
  });
  final List<int> values;
  final bool yearly;
  final String currency, title;
  final DateTime? anchor;
  final int? selectedDay;
  final ValueChanged<int> onMonth;
  final ValueChanged<int>? onDay;
  final String? note;

  @override
  State<FinanceTrendChart> createState() => _FinanceTrendChartState();
}

class _FinanceTrendChartState extends State<FinanceTrendChart> {
  bool line = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final values = widget.values;
    final peak = values.isEmpty
        ? -1
        : values.indexWhere((value) => value == values.reduce(math.max));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.insert_chart_outlined_rounded, color: scheme.primary),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (peak >= 0)
                    Text(
                      'Highest: ${widget.yearly ? financeMonths[peak] : 'Day ${peak + 1}'} · ${financeMoney(values[peak], widget.currency)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: .35),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _FinanceChartMode(
                    icon: Icons.bar_chart_rounded,
                    label: 'Bar chart',
                    selected: !line,
                    onTap: () => setState(() => line = false),
                  ),
                  _FinanceChartMode(
                    icon: Icons.show_chart_rounded,
                    label: 'Line chart',
                    selected: line,
                    onTap: () => setState(() => line = true),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (line)
          _FinanceLineChart(
            values: values,
            yearly: widget.yearly,
            currency: widget.currency,
            selectedDay: widget.selectedDay,
            onMonth: widget.onMonth,
            onDay: widget.onDay,
          )
        else
          FinancePeriodChart(
            values: values,
            yearly: widget.yearly,
            currency: widget.currency,
            onMonth: widget.onMonth,
            onDay: widget.onDay,
            selectedDay: widget.selectedDay,
            anchor: widget.anchor,
            yearlyTitle: widget.title,
            monthlyTitle: widget.title,
            note: widget.note,
            showHeading: false,
          ),
        if (line && widget.note != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.note!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _FinanceChartMode extends StatelessWidget {
  const _FinanceChartMode({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: label,
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    icon: Icon(
      icon,
      color: selected
          ? const Color(0xFF72E629)
          : Theme.of(context).colorScheme.onSurfaceVariant,
    ),
  );
}

class _FinanceLineChart extends StatelessWidget {
  const _FinanceLineChart({
    required this.values,
    required this.yearly,
    required this.currency,
    required this.onMonth,
    required this.onDay,
    this.selectedDay,
  });
  final List<int> values;
  final bool yearly;
  final String currency;
  final int? selectedDay;
  final ValueChanged<int> onMonth;
  final ValueChanged<int>? onDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) => GestureDetector(
            onTapDown: values.isEmpty
                ? null
                : (details) {
                    final ratio =
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        );
                    final index = (ratio * (values.length - 1)).round();
                    if (yearly) {
                      onMonth(index + 1);
                    } else {
                      onDay?.call(index + 1);
                    }
                  },
            child: Semantics(
              label: yearly ? 'Monthly income trend' : 'Daily trend',
              child: SizedBox(
                key: const ValueKey('finance-line-chart'),
                height: 145,
                width: double.infinity,
                child: CustomPaint(
                  painter: _FinanceLinePainter(
                    values: values,
                    selected: selectedDay == null ? null : selectedDay! - 1,
                    color: scheme.primary,
                    grid: scheme.outline.withValues(alpha: .22),
                  ),
                ),
              ),
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1', style: Theme.of(context).textTheme.labelSmall),
            Text(
              yearly ? '6' : '15',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            Text(
              '${values.length}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        if (selectedDay != null &&
            selectedDay! > 0 &&
            selectedDay! <= values.length)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              '${yearly ? financeMonths[selectedDay! - 1] : 'Day $selectedDay'} · ${financeMoney(values[selectedDay! - 1], currency)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

class _FinanceLinePainter extends CustomPainter {
  const _FinanceLinePainter({
    required this.values,
    required this.selected,
    required this.color,
    required this.grid,
  });
  final List<int> values;
  final int? selected;
  final Color color, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (var i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (values.isEmpty) return;
    final top = math.max(1, values.reduce(math.max));
    final bottom = math.min(0, values.reduce(math.min));
    final range = math.max(1, top - bottom);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          values.length == 1
              ? size.width / 2
              : size.width * i / (values.length - 1),
          8 + (size.height - 16) * (top - values[i]) / range,
        ),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: .13));
    canvas.drawPath(
      line,
      Paint()
        ..color = color
        ..strokeWidth = 2.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (selected != null && selected! >= 0 && selected! < points.length) {
      final point = points[selected!];
      canvas.drawCircle(point, 6, Paint()..color = color);
      canvas.drawCircle(point, 3, Paint()..color = Colors.white);
    }
  }

  @override
  bool shouldRepaint(covariant _FinanceLinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.selected != selected ||
      oldDelegate.color != color ||
      oldDelegate.grid != grid;
}

/// Selected calendar date and chart total, independent of ledger pagination.
class FinanceDaySelection extends StatelessWidget {
  const FinanceDaySelection({
    super.key,
    required this.date,
    required this.total,
    required this.currency,
    required this.onClear,
  });
  final DateTime date;
  final int total;
  final String currency;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Wrap(
      spacing: 16,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            '${date.day} ${financeMonths[date.month - 1]} ${date.year} · ${financeMoney(total, currency)}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        TextButton(onPressed: onClear, child: const Text('Show all days')),
      ],
    ),
  );
}
