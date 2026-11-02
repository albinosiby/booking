import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../design_system/design_system.dart';
import '../../../utils/helpers/subscription_labels.dart';
import '../../../utils/helpers/time_format.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/models/booking_time_cell.dart';
import '../../bookings/models/slot_holder.dart';
import '../../bookings/widgets/booking_form_sections.dart';
import '../../bookings/widgets/slot_holders_sheet.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_slot_chart_cubit.dart';
import '../cubit/admission_state.dart';
import '../models/admission_slot_chart.dart';

/// The chart request for a fixed schedule, or null until it can be checked.
SlotChartRequest? slotChartRequest(AdmissionState s) {
  final d = s.draft;
  if (d.mode != 'fixed' ||
      s.plan == null ||
      !s.plan!.trackAttendance ||
      d.businessId == null ||
      d.poolId == null ||
      d.planId == null ||
      d.start.isEmpty ||
      d.weekdays.isEmpty ||
      !s.validVisitDuration) {
    return null;
  }
  return SlotChartRequest(
    businessId: d.businessId!,
    poolId: d.poolId!,
    planId: d.planId!,
    start: d.start,
    weekdays: d.weekdays,
    // The shortest length lets every longer start–end range be checked.
    duration: s.endDurations.firstOrNull ?? d.duration,
    months: d.endsOn == null ? d.months : null,
    endsOn: d.endsOn,
  );
}

/// Start times free on every selected weekday for the whole plan term.
/// Tapping a free time selects it; tapping a taken time shows who holds it.
class AdmissionSlotChartPanel extends StatefulWidget {
  const AdmissionSlotChartPanel({
    super.key,
    required this.cubit,
    required this.state,
    required this.enabled,
  });
  final AdmissionCubit cubit;
  final AdmissionState state;
  final bool enabled;
  @override
  State<AdmissionSlotChartPanel> createState() =>
      _AdmissionSlotChartPanelState();
}

class _AdmissionSlotChartPanelState extends State<AdmissionSlotChartPanel> {
  late final chart = AdmissionSlotChartCubit(widget.cubit.repository)
    ..load(slotChartRequest(widget.state));

  /// Like booking: pick a start, then an end; the draft keeps the last range.
  PlanPick pick = PlanPick.done;
  @override
  void didUpdateWidget(AdmissionSlotChartPanel old) {
    super.didUpdateWidget(old);
    chart.load(slotChartRequest(widget.state));
    // An exact time typed elsewhere completes the range.
    if (pick == PlanPick.start &&
        old.state.draft.time != widget.state.draft.time) {
      pick = PlanPick.done;
    }
  }

  void choose(PlanCell cell) {
    final d = widget.state.draft, durations = widget.state.endDurations;
    final next = switch (cell.role) {
      PlanRole.start => PlanPick.start,
      PlanRole.end when pick == PlanPick.done => PlanPick.end,
      PlanRole.end => PlanPick.done,
      PlanRole.free => durations.length > 1 ? PlanPick.end : PlanPick.done,
    };
    setState(() => pick = next);
    if (cell.role == PlanRole.free) {
      widget.cubit.update(d.copyWith(time: cell.time));
    } else if (cell.role == PlanRole.end &&
        cell.duration != null &&
        next == PlanPick.done) {
      widget.cubit.update(d.copyWith(duration: cell.duration));
    }
  }

  @override
  void dispose() {
    chart.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<AdmissionSlotChartCubit, AdmissionSlotChartState>(
    bloc: chart,
    builder: (context, c) {
      final theme = Theme.of(context);
      final d = widget.state.draft;
      final data = c.chart;
      final clash = data == null || c.request == null
          ? null
          : rangeClash(data, d.time, d.duration, c.request!.duration);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.weekdays.isEmpty
                      ? 'Choose start & end'
                      : 'Choose start & end · ${weekdayNames(d.weekdays)}',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                tooltip: 'Refresh free times',
                onPressed: c.request == null || c.loading
                    ? null
                    : chart.refresh,
                icon: c.loading
                    ? const AppRefreshIndicator(
                        label: 'Checking free times…',
                        iconOnly: true,
                      )
                    : Icon(Icons.refresh, size: 20.r),
              ),
            ],
          ),
          if (c.request == null)
            Text(
              'Choose the plan, activation date, days and hours to see which start times are free.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            if (data != null)
              Text(
                'Tap start and end. Tap a selected boundary again to clear it. Checked against all ${data.dates.length} sessions until ${data.expiresOn}; tap a booked time to see who holds it.',
                style: theme.textTheme.bodySmall,
              ),
            SizedBox(height: 8.h),
            if (c.error != null)
              AppErrorWidget(message: c.error!, onRetry: chart.refresh)
            else if (data == null)
              const AppLoadingState(
                initial: true,
                label: 'Checking free times…',
              )
            else if (data.times.isEmpty)
              const Text(
                'No start time fits these weekdays within opening hours. Choose other weekdays or a shorter duration.',
              )
            else
              _TimeGrid(
                cells: planCells(
                  data,
                  start: d.time,
                  duration: d.duration,
                  durations: widget.state.endDurations,
                  step: c.request!.duration,
                  // A booked range is never shown as chosen.
                  pick: pick == PlanPick.done && clash != null
                      ? PlanPick.start
                      : pick,
                ),
                enabled: widget.enabled,
                onSelected: choose,
                onTaken: pick == PlanPick.end
                    ? null
                    : (t) => _showClashes(context, t),
              ),
            if (data != null && pick == PlanPick.done && clash != null) ...[
              SizedBox(height: 8.h),
              Text(
                '${TimeFormat.display(d.time)}–${TimeFormat.display(_hhmm(_minutes(d.time) + d.duration))} is booked on ${clash.$1} of ${clash.$2} dates. Review will be rejected until you choose a free time or move the other booking.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ],
      );
    },
  );

  void _showClashes(
    BuildContext context,
    SlotChartTime t,
  ) => showAdaptiveSheet<void>(
    context: context,
    builder: (sheet) => Padding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${TimeFormat.display(t.time)}–${TimeFormat.display(t.endTime)} is taken',
            style: Theme.of(sheet).textTheme.titleMedium,
          ),
          SizedBox(height: 4.h),
          Text(
            t.clashCount == t.sessionCount
                ? 'Taken on all ${t.sessionCount} dates.'
                : 'Taken on ${t.clashCount} of ${t.sessionCount} dates.',
            style: Theme.of(sheet).textTheme.bodySmall,
          ),
          for (final clash in t.clashes) ...[
            SizedBox(height: 12.h),
            Text(clash.label, style: Theme.of(sheet).textTheme.labelLarge),
            if (clash.holders.isEmpty)
              Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: Text(clash.reason),
              )
            else ...[
              for (final h in clash.holders) SlotHolderTile(holder: h),
              if (clash.holderCount > clash.holders.length)
                Text('+${clash.holderCount - clash.holders.length} more'),
            ],
          ],
          if (t.clashCount > t.clashes.length) ...[
            SizedBox(height: 12.h),
            Text(
              '${t.clashCount - t.clashes.length} more dates also clash.',
              style: Theme.of(sheet).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    ),
  );
}

int _minutes(String t) =>
    int.parse(t.substring(0, 2)) * 60 + int.parse(t.substring(3, 5));
String _hhmm(int m) =>
    '${(m ~/ 60 % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// Chart times inside a start–end range, or null when they leave a gap.
/// Each time was checked for [step] minutes, so together they cover the range.
List<SlotChartTime>? _covered(
  AdmissionSlotChart chart,
  int start,
  int length,
  int step,
) {
  final end = start + length;
  if (end > 1440) return null;
  final inside = [
    for (final t in chart.times)
      if (_minutes(t.time) >= start && _minutes(t.time) + step <= end) t,
  ]..sort((a, b) => _minutes(a.time).compareTo(_minutes(b.time)));
  var reach = start;
  for (final t in inside) {
    final m = _minutes(t.time);
    if (m > reach) return null;
    if (m + step > reach) reach = m + step;
  }
  return reach >= end ? inside : null;
}

/// Booked dates (at least) and term sessions for a range, or null when free.
(int, int)? rangeClash(
  AdmissionSlotChart chart,
  String start,
  int length,
  int step,
) {
  final taken = (_covered(chart, _minutes(start), length, step) ?? const [])
      .where((t) => t.taken)
      .toList();
  if (taken.isEmpty) return null;
  final dates = {
    for (final t in taken)
      for (final c in t.clashes) c.date,
  };
  final count = [
    dates.length,
    ...taken.map((t) => t.clashCount),
  ].reduce((a, b) => a > b ? a : b);
  return (count, taken.first.sessionCount);
}

enum PlanPick { start, end, done }

enum PlanRole { start, end, free }

/// One grid cell for a plan's start–end pick.
class PlanCell {
  const PlanCell(this.cell, this.role, {this.chart, this.duration});
  final BookingTimeCell cell;
  final PlanRole role;
  final SlotChartTime? chart;

  /// The visit length an end cell sets.
  final int? duration;
  String get time => cell.slot.time;
}

/// Chart times as booking-style cells: free starts, then valid ends.
List<PlanCell> planCells(
  AdmissionSlotChart chart, {
  required String start,
  required int duration,
  required List<int> durations,
  required int step,
  required PlanPick pick,
}) {
  final s = _minutes(start);
  final byTime = {for (final t in chart.times) _minutes(t.time): t};
  // Only ends whose whole range lies within opening hours.
  final ends = <int, int>{
    for (final length in durations)
      if (_covered(chart, s, length, step) != null) s + length: length,
  };
  final endMinute = s + duration;
  final keys = {
    ...byTime.keys,
    if (pick == PlanPick.end) ...ends.keys,
    if (pick == PlanPick.done && byTime.containsKey(s) && endMinute <= 1440)
      endMinute,
  }.toList()..sort();
  bool free(int length) =>
      _covered(chart, s, length, step)?.every((t) => t.available) ?? false;
  String status(SlotChartTime t) => switch (t.status) {
    'available' when t.capacity > 1 => '${t.remaining} of ${t.capacity} left',
    'available' => 'Available',
    'taken' when t.clashCount < t.sessionCount =>
      'Booked · ${t.clashCount} of ${t.sessionCount} dates',
    'taken' => 'Booked',
    _ => 'Past',
  };
  return [
    for (final m in keys)
      (() {
        final t = byTime[m];
        final time = _hhmm(m);
        final slot = BookingSlot(
          time,
          t?.available ?? false,
          0,
          t != null && t.capacity > 1 ? t.remaining : null,
          t?.status == 'past',
          null,
          t == null ? 'end_only' : (t.taken ? 'booked' : t.status),
        );
        PlanCell cell(
          PlanRole role, {
          required bool enabled,
          String? label,
          bool start = false,
          bool end = false,
          bool inRange = false,
          int? length,
        }) => PlanCell(
          BookingTimeCell(
            slot: slot,
            date: '',
            enabled: enabled,
            start: start,
            end: end,
            inRange: inRange,
            label: label ?? (t == null ? 'End only' : status(t)),
          ),
          role,
          chart: t,
          duration: length,
        );
        final isStart = pick != PlanPick.start && m == s && t != null;
        if (isStart) {
          return cell(
            PlanRole.start,
            enabled: true,
            start: true,
            label: 'Start · tap to clear',
          );
        }
        if (pick == PlanPick.end) {
          final length = ends[m];
          final valid = length != null && free(length);
          return cell(
            PlanRole.end,
            enabled: valid,
            length: length,
            label: valid
                ? hoursLabel(length)
                : length != null &&
                      _covered(chart, s, length, step)!.any((t) => t.taken)
                ? 'Booked'
                : t?.status == 'past'
                ? 'Past'
                : 'Not a valid end',
          );
        }
        if (pick == PlanPick.done && byTime.containsKey(s)) {
          if (m == endMinute) {
            return cell(
              PlanRole.end,
              enabled: true,
              end: true,
              label: 'End · tap to clear',
            );
          }
          if (m > s && m < endMinute) {
            return cell(
              PlanRole.free,
              enabled: t?.available ?? false,
              inRange: true,
              label: 'Selected range',
            );
          }
        }
        return cell(PlanRole.free, enabled: t?.available ?? false);
      })(),
  ];
}

/// Shows plan cells in the booking time grid so plans and bookings look alike.
class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.cells,
    required this.enabled,
    required this.onSelected,
    required this.onTaken,
  });
  final List<PlanCell> cells;
  final bool enabled;
  final ValueChanged<PlanCell> onSelected;
  final ValueChanged<SlotChartTime>? onTaken;
  @override
  Widget build(BuildContext context) {
    final byTime = {for (final c in cells) c.time: c};
    return BookingTimeGrid(
      slots: [for (final c in cells) c.cell.slot],
      cells: [for (final c in cells) c.cell],
      selectedDate: '',
      enabled: enabled,
      onSelected: (slot) => onSelected(byTime[slot.time]!),
      onUnavailable: onTaken == null
          ? null
          : (slot) {
              final t = byTime[slot.time]?.chart;
              if (t != null && t.taken) onTaken!(t);
            },
    );
  }
}
