import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/booking_models.dart';

/// Month grid with per-day booking counts, used by the desktop calendar.
class BookingMonthCalendar extends StatefulWidget {
  const BookingMonthCalendar({
    super.key,
    required this.date,
    required this.onChanged,
    this.counts = const {},
    this.onRangeChanged,
  });
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final Map<String, int> counts;
  final void Function(String from, String until)? onRangeChanged;
  @override
  State<BookingMonthCalendar> createState() => _BookingMonthCalendarState();
}

class _BookingMonthCalendarState extends State<BookingMonthCalendar> {
  static const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  late DateTime month = DateTime(widget.date.year, widget.date.month);

  // Six Monday-first weeks: 42 days, inside the server's 62-day count limit.
  DateTime get gridStart =>
      DateTime(month.year, month.month, 1 - (month.weekday - 1));
  DateTime day(int i) =>
      DateTime(gridStart.year, gridStart.month, gridStart.day + i);

  void reportRange() {
    final from = bookingDate(day(0)), until = bookingDate(day(41));
    // Publish after the frame; the cubit emits while the page builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onRangeChanged?.call(from, until);
    });
  }

  void show(DateTime next) {
    setState(() => month = DateTime(next.year, next.month));
    reportRange();
  }

  @override
  void initState() {
    super.initState();
    reportRange();
  }

  @override
  void didUpdateWidget(covariant BookingMonthCalendar old) {
    super.didUpdateWidget(old);
    if (widget.date.year != month.year || widget.date.month != month.month) {
      if (bookingDate(old.date) != bookingDate(widget.date)) show(widget.date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);
    final today = DateTime.now();
    return AppCard(
      key: const ValueKey('booking-month-calendar'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  localizations.formatMonthYear(month),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Previous month',
                visualDensity: VisualDensity.compact,
                onPressed: () => show(DateTime(month.year, month.month - 1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                tooltip: 'Next month',
                visualDensity: VisualDensity.compact,
                onPressed: () => show(DateTime(month.year, month.month + 1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final w in weekdays)
                Expanded(
                  child: Text(
                    w,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface.withValues(alpha: .5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var week = 0; week < 6; week++)
            Row(
              children: [
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: _DayCell(
                      date: day(week * 7 + d),
                      inMonth: day(week * 7 + d).month == month.month,
                      selected: DateUtils.isSameDay(
                        day(week * 7 + d),
                        widget.date,
                      ),
                      today: DateUtils.isSameDay(day(week * 7 + d), today),
                      count: widget.counts[bookingDate(day(week * 7 + d))],
                      onTap: () => widget.onChanged(day(week * 7 + d)),
                    ),
                  ),
              ],
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              widget.onChanged(today);
              show(today);
            },
            icon: const Icon(Icons.today_outlined, size: 18),
            label: const Text('Today'),
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.inMonth,
    required this.selected,
    required this.today,
    required this.count,
    required this.onTap,
  });
  final DateTime date;
  final bool inMonth, selected, today;
  final int? count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final busy = (count ?? 0) > 0;
    final foreground = selected
        ? colors.onPrimary
        : colors.onSurface.withValues(alpha: inMonth ? 1 : .35);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: AspectRatio(
        aspectRatio: 1,
        child: Material(
          color: selected ? colors.primary : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: today && !selected
                ? BorderSide(color: colors.primary, width: 1.5)
                : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: ValueKey('booking-month-day-${bookingDate(date)}'),
            onTap: onTap,
            child: Semantics(
              button: true,
              selected: selected,
              label:
                  '${MaterialLocalizations.of(context).formatFullDate(date)}, ${count == null ? 'booking count unavailable' : '$count bookings'}',
              child: ExcludeSemantics(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: selected || today
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 3),
                    SizedBox(
                      height: 14,
                      child: busy
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.onPrimary.withValues(alpha: .2)
                                    : colors.primary.withValues(alpha: .16),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10,
                                  height: 1.4,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? colors.onPrimary
                                      : colors.primary,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
