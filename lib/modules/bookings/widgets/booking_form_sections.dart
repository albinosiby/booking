import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../models/booking_models.dart';
import '../models/booking_form_model.dart';
import '../models/booking_time_cell.dart';

IconData bookingBusinessIcon(String type) => switch (type) {
  'turf' => Icons.sports_soccer,
  'pool' => Icons.pool_outlined,
  'hall' => Icons.celebration_outlined,
  'basketball' => Icons.sports_basketball_outlined,
  _ => Icons.sports_tennis,
};
String bookingBusinessType(String type) => switch (type) {
  'turf' => 'Turf',
  'pool' => 'Swimming pool',
  'hall' => 'Party hall',
  'basketball' => 'Basketball',
  'tennis' => 'Tennis',
  'badminton' => 'Badminton',
  _ => 'Business',
};

class BookingFormSection extends StatelessWidget {
  const BookingFormSection({
    super.key,
    required this.number,
    required this.title,
    required this.children,
    this.summary,
    this.expanded = true,
    this.onToggle,
  });
  final int number;
  final String title;
  final String? summary;
  final List<Widget> children;
  final bool expanded;
  final VoidCallback? onToggle;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final heading = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.primary,
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: colors.onPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              if (summary != null) ...[
                const SizedBox(height: 4),
                Text(
                  summary!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onToggle != null)
          Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 22),
      ],
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (onToggle != null)
              InkWell(
                onTap: onToggle,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: heading,
                ),
              )
            else
              heading,
            if (expanded) ...[const SizedBox(height: 16), ...children],
          ],
        ),
      ),
    );
  }
}

/// Shared selection treatment for business, sport and physical space choices.
class BookingChoiceCard extends StatelessWidget {
  const BookingChoiceCard({
    super.key,
    required this.title,
    required this.icon,
    required this.selected,
    this.subtitle,
    this.onTap,
    this.compact = false,
    this.strong = false,
  });
  final String title;
  final String? subtitle;
  final IconData icon;
  final bool selected, compact, strong;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), c = theme.colorScheme;
    final filled = selected && strong;
    final foreground = filled ? c.onPrimary : c.onSurface;
    final accent = filled ? c.onPrimary : c.primary;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: theme.textTheme.labelLarge?.copyWith(color: foreground),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: filled
                  ? c.onPrimary.withValues(alpha: .85)
                  : c.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
    final check = Icon(
      selected ? Icons.check_circle : Icons.circle_outlined,
      size: 18,
      color: selected ? accent : c.outline.withValues(alpha: .5),
    );
    return Semantics(
      button: true,
      selected: selected,
      enabled: onTap != null,
      child: Material(
        color: filled
            ? c.primary
            : selected
            ? c.primary.withValues(alpha: .08)
            : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: selected ? c.primary : c.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: compact ? 56 : 92),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: compact
                  ? Row(
                      children: [
                        Icon(icon, color: accent, size: 21),
                        const SizedBox(width: 10),
                        Expanded(child: text),
                        const SizedBox(width: 6),
                        check,
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: accent, size: 22),
                            const Spacer(),
                            check,
                          ],
                        ),
                        const SizedBox(height: 12),
                        text,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class BookingBusinessCards extends StatelessWidget {
  const BookingBusinessCards({
    super.key,
    required this.businesses,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });
  final List<BookingBusiness> businesses;
  final String? selected;
  final ValueChanged<String> onSelected;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final scaler = MediaQuery.textScalerOf(context);
    final height = 72 + scaler.scale(16) * 2 + scaler.scale(12);
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: businesses.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final business = businesses[index], active = selected == business.id;
          return SizedBox(
            width: 180,
            height: height,
            child: Semantics(
              button: true,
              selected: active,
              enabled: enabled,
              child: Material(
                color: active
                    ? colors.primary.withValues(alpha: .1)
                    : colors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: active ? colors.primary : colors.outlineVariant,
                    width: active ? 1.5 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: ValueKey('booking-business-${business.id}'),
                  onTap: enabled
                      ? () {
                          if (!active) onSelected(business.id);
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              bookingBusinessIcon(business.type),
                              color: colors.primary,
                              size: 20,
                            ),
                            const Spacer(),
                            if (active)
                              Icon(
                                Icons.check_circle,
                                color: colors.primary,
                                size: 18,
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Tooltip(
                            message: business.name,
                            child: Text(
                              business.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ),
                        Text(
                          bookingBusinessType(business.type),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class BookingDateRow extends StatelessWidget {
  const BookingDateRow({
    super.key,
    required this.date,
    required this.today,
    required this.onSelected,
    required this.onPick,
    this.enabled = true,
  });
  final String date, today;
  final bool enabled;
  final ValueChanged<String> onSelected;
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) {
    DateTime calendarDate(String v) {
      final parsed = DateTime.parse(v);
      return DateTime.utc(parsed.year, parsed.month, parsed.day);
    }

    final minimum = calendarDate(today),
        selected = DateTime.tryParse(date) == null
            ? minimum
            : calendarDate(date);
    final anchor = selected.subtract(const Duration(days: 2));
    final first = anchor.isBefore(minimum) ? minimum : anchor;
    final c = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < 7; i++)
                Builder(
                  builder: (context) {
                    final d = first.add(Duration(days: i)),
                        value = bookingDate(d),
                        active = value == date;
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Semantics(
                        button: true,
                        selected: active,
                        label: MaterialLocalizations.of(
                          context,
                        ).formatFullDate(d),
                        child: Material(
                          color: active ? c.primary : c.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: active
                                  ? c.primary
                                  : c.outline.withValues(alpha: .4),
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            key: ValueKey('booking-date-$value'),
                            onTap: !enabled ? null : () => onSelected(value),
                            child: Container(
                              width: 64,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Text(
                                    [
                                      'Mon',
                                      'Tue',
                                      'Wed',
                                      'Thu',
                                      'Fri',
                                      'Sat',
                                      'Sun',
                                    ][d.weekday - 1],
                                    style: TextStyle(
                                      color: active
                                          ? c.onPrimary
                                          : c.onSurfaceVariant,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${d.day}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w700,
                                      color: active ? c.onPrimary : c.onSurface,
                                    ),
                                  ),
                                  Text(
                                    [
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
                                    ][d.month - 1],
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: active
                                          ? c.onPrimary
                                          : c.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: enabled ? onPick : null,
            icon: const Icon(Icons.calendar_month_outlined, size: 18),
            label: const Text('Choose another date'),
          ),
        ),
      ],
    );
  }
}

class BookingTimeGrid extends StatelessWidget {
  const BookingTimeGrid({
    super.key,
    required this.slots,
    required this.onSelected,
    this.selected,
    this.pool = false,
    this.enabled = true,
    this.choosingEnd = false,
    this.minimumDuration,
    this.selectedDate,
    this.cells,
  });
  final List<BookingSlot> slots;
  final List<BookingTimeCell>? cells;
  final String? selected;
  final bool pool, enabled, choosingEnd;
  final int? minimumDuration;
  final String? selectedDate;
  final ValueChanged<BookingSlot> onSelected;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 600
          ? 6
          : box.maxWidth >= 280 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20
          ? 3
          : 2;
      final width = (box.maxWidth - (columns - 1) * 8) / columns;
      final c = Theme.of(context).colorScheme;
      final visible = cells?.map((cell) => cell.slot).toList() ?? slots;
      final bySlot = {
        for (final cell in cells ?? <BookingTimeCell>[]) cell.slot: cell,
      };
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final slot in visible)
            Builder(
              builder: (context) {
                final cell = bySlot[slot];
                final active = cell != null
                    ? cell.start || cell.end
                    : selected == slot.time && slot.selectable;
                final inRange = cell?.inRange ?? false;
                final selectable =
                    enabled && (cell?.enabled ?? slot.selectable);
                final status =
                    cell?.label ??
                    (slot.status == 'minimum'
                        ? 'Minimum $minimumDuration min'
                        : slot.past
                        ? 'Past'
                        : !slot.available
                        ? (pool ? 'Unavailable' : 'Booked')
                        : pool && slot.remaining != null
                        ? '${slot.remaining} places'
                        : 'Available');
                final text = active
                    ? c.onPrimary
                    : selectable
                    ? c.onSurface
                    : c.onSurfaceVariant;
                return SizedBox(
                  width: width,
                  child: Semantics(
                    button: true,
                    selected: active || inRange,
                    enabled: selectable,
                    label: '${TimeFormat.display(slot.time)}, $status',
                    child: Material(
                      color: active
                          ? c.primary
                          : inRange
                          ? c.primary.withValues(alpha: .1)
                          : selectable
                          ? c.surface
                          : c.onSurface.withValues(alpha: .04),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: active
                              ? c.primary
                              : c.outline.withValues(alpha: .4),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey(
                          cell != null && cell.date != selectedDate
                              ? 'booking-time-${cell.date}-${slot.time}'
                              : 'booking-time-${slot.time}',
                        ),
                        onTap: selectable ? () => onSelected(slot) : null,
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 80),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 14,
                          ),
                          child: Column(
                            children: [
                              Text(
                                '${TimeFormat.display(slot.time)}${(cell?.date ?? slot.date) != null && (cell?.date ?? slot.date) != selectedDate ? ' +1 day' : ''}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: text,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                cell != null
                                    ? status
                                    : active
                                    ? (choosingEnd
                                          ? 'Selected finish'
                                          : 'Selected')
                                    : choosingEnd && slot.selectable
                                    ? '${slot.duration} min'
                                    : status,
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: text),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      );
    },
  );
}

class BookingConfirmBar extends StatelessWidget {
  const BookingConfirmBar({
    super.key,
    required this.model,
    required this.onReview,
    required this.onConfirm,
  });
  final BookingFormModel model;
  final VoidCallback onReview, onConfirm;
  @override
  Widget build(BuildContext context) {
    final s = model, c = Theme.of(context).colorScheme;
    final total = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          s.quote == null && s.estimatedTotal != null
              ? 'ESTIMATED TOTAL'
              : 'TOTAL',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: c.onSurfaceVariant,
            letterSpacing: 1,
          ),
        ),
        Text(
          s.displayedTotal == null
              ? '—'
              : bookingMoney(s.displayedTotal!, s.catalog.currency),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        Text(
          s.selectedSpaceTitle ?? 'Choose a space',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
        ),
      ],
    );
    final action = AppButton(
      label: s.option?.minimumDuration != null && !s.rangeComplete
          ? (s.choosingEnd ? 'Choose finish time' : 'Choose start time')
          : s.pending != null
          ? 'Retry confirmation'
          : s.review
          ? (s.quote == null
                ? (s.checking ? 'Verifying booking…' : 'Retry verification')
                : (s.original == null
                      ? 'Confirm booking'
                      : 'Confirm reschedule'))
          : 'Review booking',
      icon: Icons.check_rounded,
      busy: s.saving,
      busyLabel: 'Saving booking…',
      onPressed:
          s.saving ||
              (s.review && s.checking) ||
              (s.option?.minimumDuration != null && !s.rangeComplete)
          ? null
          : (s.review && s.quote != null) || s.pending != null
          ? onConfirm
          : onReview,
    );
    return Material(
      elevation: 16,
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 728),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LayoutBuilder(
                    builder: (context, box) =>
                        box.maxWidth < 340 ||
                            MediaQuery.textScalerOf(context).scale(14) > 20
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              total,
                              const SizedBox(height: 10),
                              action,
                            ],
                          )
                        : Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(flex: 2, child: total),
                              const SizedBox(width: 12),
                              Expanded(flex: 3, child: action),
                            ],
                          ),
                  ),
                  if (s.error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      s.error!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: c.error),
                    ),
                  ],
                  if (s.paid > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Received ${bookingMoney(s.paid, s.catalog.currency)}${s.balance == null ? '' : ' · Balance ${bookingMoney(s.balance!, s.catalog.currency)}'}${(s.refund ?? 0) > 0 ? ' · Refund due ${bookingMoney(s.refund!, s.catalog.currency)}' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
