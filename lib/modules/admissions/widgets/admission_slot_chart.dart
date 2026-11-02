import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../../bookings/models/slot_holder.dart';
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
    duration: d.duration,
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
  @override
  void didUpdateWidget(AdmissionSlotChartPanel old) {
    super.didUpdateWidget(old);
    chart.load(slotChartRequest(widget.state));
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
      final selected = data?.at(d.time);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  d.weekdays.isEmpty
                      ? 'Free start times'
                      : 'Free start times · ${weekdayNames(d.weekdays)}',
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
              'Choose the plan, activation date and weekdays to see which start times are free.',
              style: theme.textTheme.bodySmall,
            )
          else ...[
            if (data != null)
              Text(
                'Checked against all ${data.dates.length} sessions until ${data.expiresOn}. Tap a taken time to see who holds it.',
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
                times: data.times,
                selected: d.time,
                enabled: widget.enabled,
                onSelected: (t) =>
                    widget.cubit.update(d.copyWith(time: t.time)),
                onTaken: (t) => _showClashes(context, t),
              ),
            if (data != null && selected?.taken == true) ...[
              SizedBox(height: 8.h),
              Text(
                '${TimeFormat.display(d.time)} is taken on ${selected!.clashCount} of ${selected.sessionCount} dates. Review will be rejected until you choose a free time or move the other booking.',
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

class _TimeGrid extends StatelessWidget {
  const _TimeGrid({
    required this.times,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    required this.onTaken,
  });
  final List<SlotChartTime> times;
  final String selected;
  final bool enabled;
  final ValueChanged<SlotChartTime> onSelected, onTaken;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns = box.maxWidth >= 600
          ? 6
          : box.maxWidth >= 280 &&
                MediaQuery.textScalerOf(context).scale(14) <= 20
          ? 3
          : 2;
      final width = (box.maxWidth - (columns - 1) * 8.w) / columns;
      final c = Theme.of(context).colorScheme;
      return Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: [
          for (final t in times)
            Builder(
              builder: (context) {
                final active = t.available && t.time == selected;
                final label = switch (t.status) {
                  'available' when t.capacity > 1 =>
                    '${t.remaining} of ${t.capacity} left',
                  'available' => 'Free',
                  'taken' when t.clashCount < t.sessionCount =>
                    'Taken · ${t.clashCount} ${t.clashCount == 1 ? 'date' : 'dates'}',
                  'taken' => 'Taken',
                  _ => 'Past',
                };
                final tap = !enabled
                    ? null
                    : t.available
                    ? () => onSelected(t)
                    : t.taken
                    ? () => onTaken(t)
                    : null;
                final text = active
                    ? c.onPrimary
                    : t.available
                    ? c.onSurface
                    : t.taken
                    ? c.error
                    : c.onSurfaceVariant;
                return SizedBox(
                  width: width,
                  child: Semantics(
                    button: tap != null,
                    selected: active,
                    label: '${TimeFormat.display(t.time)}, $label',
                    child: Material(
                      color: active
                          ? c.primary
                          : t.available
                          ? c.surface
                          : t.taken
                          ? c.error.withValues(alpha: .06)
                          : c.onSurface.withValues(alpha: .04),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        side: BorderSide(
                          color: active
                              ? c.primary
                              : t.taken
                              ? c.error.withValues(alpha: .3)
                              : c.outline.withValues(alpha: .4),
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: ValueKey('admission-slot-${t.time}'),
                        onTap: tap,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 12.h,
                          ),
                          child: ExcludeSemantics(
                            child: Column(
                              children: [
                                Text(
                                  TimeFormat.display(t.time),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    color: text,
                                  ),
                                ),
                                SizedBox(height: 4.h),
                                Text(
                                  active ? 'Selected' : label,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.sp,
                                    color: text,
                                  ),
                                ),
                              ],
                            ),
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
