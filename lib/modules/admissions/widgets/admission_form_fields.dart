import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/widgets/booking_widgets.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';
import 'admission_slot_chart.dart';
import '../../bookings/models/slot_holder.dart' show weekdayNames;
import '../../../utils/helpers/subscription_labels.dart';

class AdmissionScheduleFields extends StatelessWidget {
  const AdmissionScheduleFields({
    super.key,
    required this.cubit,
    required this.state,
    this.showPlanKind = true,
  });
  final AdmissionCubit cubit;
  final AdmissionState state;
  final bool showPlanKind;
  @override
  Widget build(BuildContext context) {
    final s = state,
        d = s.draft,
        enabled = !s.busy && !s.locked && s.preview == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!s.subscription)
          AppPicker(
            label: !showPlanKind && s.formKind == 'coaching'
                ? 'Coaching plan'
                : 'Plan',
            value: d.planId,
            enabled: enabled,
            items: s.availablePlans
                .map(
                  (p) => PickerItem(
                    p.id,
                    [
                      p.name,
                      if (showPlanKind)
                        switch (p.kind) {
                          'swimming' => 'Swimming plan',
                          'play' => 'Court plan',
                          _ => 'Coaching',
                        },
                      bookingMoney(p.total, s.catalog.currency),
                    ].join(' · '),
                  ),
                )
                .toList(),
            onChanged: cubit.plan,
          ),
        if (s.plan?.kind == 'coaching' && s.plan?.trackAttendance != false)
          Padding(
            padding: EdgeInsets.only(top: 8.h),
            child: Text('Coach: ${s.plan!.coach}'),
          ),
        SizedBox(height: 12.h),
        OutlinedButton.icon(
          icon: const Icon(Icons.event),
          label: Text('Activation: ${d.start}'),
          onPressed: !enabled
              ? null
              : () async {
                  final today = DateTime.parse(s.business!.today);
                  final chosen = await showDatePicker(
                    context: context,
                    initialDate: DateTime.tryParse(d.start) ?? today,
                    firstDate: today,
                    lastDate: DateTime(2100, 12, 31),
                  );
                  if (chosen != null) {
                    cubit.update(d.copyWith(start: bookingDate(chosen)));
                  }
                },
        ),
        if (s.subscription) ...[
          SizedBox(height: 12.h),
          Text('How long', style: Theme.of(context).textTheme.titleSmall),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: [
              for (final months in const [1, 2, 3, 6, 12])
                ChoiceChip(
                  key: ValueKey('subscription-months-$months'),
                  label: Text('$months ${months == 1 ? 'month' : 'months'}'),
                  selected: d.endsOn == null && d.months == months,
                  onSelected: !enabled
                      ? null
                      : (_) => cubit.update(
                          d.copyWith(months: months, clearEndsOn: true),
                        ),
                ),
              ChoiceChip(
                key: const ValueKey('subscription-months-custom'),
                label: Text(
                  d.endsOn == null ? 'Custom days' : 'Until ${d.endsOn}',
                ),
                selected: d.endsOn != null,
                onSelected: !enabled
                    ? null
                    : (_) async {
                        final first =
                            DateTime.tryParse(d.start) ??
                            DateTime.parse(s.business!.today);
                        final chosen = await showDatePicker(
                          context: context,
                          helpText: 'Last day of the subscription',
                          initialDate:
                              DateTime.tryParse(d.endsOn ?? '') ??
                              first.add(const Duration(days: 13)),
                          firstDate: first,
                          lastDate: DateTime(
                            first.year + 2,
                            first.month,
                            first.day,
                          ),
                        );
                        if (chosen != null && !cubit.isClosed) {
                          cubit.update(d.copyWith(endsOn: bookingDate(chosen)));
                        }
                      },
              ),
            ],
          ),
        ],
        SizedBox(height: 12.h),
        if (s.plan?.trackAttendance == false)
          const Text(
            'Membership-only: validity and fees only. No sessions, attendance or space reservations.',
          )
        else ...[
          if (s.plan?.subscription == true)
            const Text(
              'Subscription: choose the days and the time slot. Every chosen day until it ends is reserved for this person.',
            )
          else ...[
            AppPicker(
              label: 'Attendance mode',
              value: d.mode,
              enabled: enabled,
              items: const [
                PickerItem('fixed', 'Fixed weekly schedule'),
                PickerItem('flexible', 'Flexible attendance'),
              ],
              onChanged: (v) => cubit.update(d.copyWith(mode: v)),
            ),
            SizedBox(height: 12.h),
            Text(
              d.mode == 'fixed'
                  ? 'Selected weekdays reserve sessions up to the plan limit. Any days without a reserved session expire unused.'
                  : 'Attendance uses one day per date. No advance slot is reserved.',
            ),
          ],
          if (d.mode == 'fixed') ...[
            SizedBox(height: 12.h),
            Text(
              'Choose the days this member will come each week. The reserved sessions appear on Calendar after admission is confirmed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (s.business?.court == true && s.pool != null) ...[
              SizedBox(height: 6.h),
              Text(
                s.pool!.allDay
                    ? '${s.pool!.name} follows its configured opening days.'
                    : s.pool!.opensAt != null && s.pool!.closesAt != null
                    ? '${s.pool!.name} opens ${TimeFormat.display(s.pool!.opensAt!)}–${TimeFormat.display(s.pool!.closesAt!)} on its configured days.'
                    : '${s.pool!.name} follows its configured opening hours.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (s.plan?.subscription == true) ...[
              SizedBox(height: 12.h),
              Wrap(
                spacing: 6.w,
                runSpacing: 6.h,
                children: [
                  for (final preset in [
                    ...subscriptionDayPresets.keys,
                    'custom',
                  ])
                    ChoiceChip(
                      key: ValueKey('subscription-days-$preset'),
                      label: Text(dayPresetLabel(preset)),
                      selected: (dayPresetOf(d.weekdays) ?? 'custom') == preset,
                      onSelected: !enabled || preset == 'custom'
                          ? null
                          : (_) => cubit.update(
                              d.copyWith(
                                weekdays: subscriptionDayPresets[preset],
                              ),
                            ),
                    ),
                ],
              ),
            ],
            SizedBox(height: 12.h),
            Wrap(
              spacing: 6.w,
              children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                    label: Text(
                      const [
                        'Mon',
                        'Tue',
                        'Wed',
                        'Thu',
                        'Fri',
                        'Sat',
                        'Sun',
                      ][day - 1],
                    ),
                    selected: d.weekdays.contains(day),
                    onSelected: !enabled
                        ? null
                        : (value) {
                            final days = {...d.weekdays};
                            value ? days.add(day) : days.remove(day);
                            cubit.update(
                              d.copyWith(weekdays: days.toList()..sort()),
                            );
                          },
                  ),
              ],
            ),
          ],
          SizedBox(height: 12.h),
          // A subscription's end time on the grid sets its hours.
          if (s.adjustableVisitDuration && !s.subscription) ...[
            Row(
              children: [
                IconButton(
                  tooltip: 'Decrease visit duration',
                  onPressed: enabled && d.duration > s.minimumVisitDuration
                      ? () => cubit.adjustVisitDuration(-1)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Expanded(
                  child: Text(
                    'Visit duration: ${d.duration} minutes',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Increase visit duration',
                  onPressed: enabled && d.duration + 30 <= 1440
                      ? () => cubit.adjustVisitDuration(1)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            Text(
              'Minimum ${s.minimumVisitDuration} minutes · 30-minute steps',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ] else if (!s.subscription)
            Text(
              'Visit duration: ${d.duration} minutes',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (d.mode == 'fixed') ...[
            SizedBox(height: 16.h),
            AdmissionSlotChartPanel(cubit: cubit, state: s, enabled: enabled),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                key: const ValueKey('admission-exact-time'),
                icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                label: Text(
                  'Enter an exact time · ${TimeFormat.display(d.time)}',
                ),
                onPressed: !enabled
                    ? null
                    : () async {
                        final t = await showAppTimePicker(
                          context: context,
                          initialTime: d.time,
                        );
                        if (t != null && !cubit.isClosed) {
                          cubit.update(d.copyWith(time: t));
                        }
                      },
              ),
            ),
          ],
          if (s.subscription && d.weekdays.isNotEmpty && s.expiry != null) ...[
            SizedBox(height: 12.h),
            Text(
              key: const ValueKey('subscription-summary'),
              [
                dayPresetLabel(dayPresetOf(d.weekdays) ?? 'custom'),
                '${TimeFormat.display(d.time)} · ${hoursLabel(d.duration)}',
                '${s.subscriptionSessions} sessions until ${s.expiry}',
              ].join(' · '),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
          SizedBox(height: 12.h),
        ],
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Expiry date'),
          child: Text(s.expiry ?? 'Calculated at review'),
        ),
        Text(
          s.subscription
              ? 'Ends after the chosen months, or on the custom last day.'
              : 'Expiry follows the selected plan validity.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class AdmissionReviewSummary extends StatelessWidget {
  const AdmissionReviewSummary({super.key, required this.state});
  final AdmissionState state;
  @override
  Widget build(BuildContext context) {
    final s = state, d = s.draft;
    final allowance = s.subscription
        ? s.preview!.sessions.length
        : s.plan?.allowance ?? s.preview!.sessions.length;
    final missing = allowance - s.preview!.sessions.length;
    final coaching = s.plan?.kind == 'coaching';
    final unit = coaching
        ? (allowance == 1 ? 'class' : 'classes')
        : (allowance == 1 ? 'plan day' : 'plan days');
    final missingUnit = coaching
        ? (missing == 1 ? 'class' : 'classes')
        : (missing == 1 ? 'day' : 'days');
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.customer.name, style: Theme.of(context).textTheme.titleLarge),
          Text(d.customer.phone),
          Text(s.plan?.name ?? ''),
          if (s.subscription)
            Text(
              '${d.endsOn == null ? '${d.months} × ${bookingMoney(d.amountMinor ?? 0, s.catalog.currency)} per month' : '${bookingMoney(d.amountMinor ?? 0, s.catalog.currency)} until ${d.endsOn}'} · ${weekdayNames(d.weekdays)} · ${TimeFormat.display(d.time)} · ${hoursLabel(d.duration)}',
            ),
          if (!s.subscription)
            Text(
              '${s.plan?.allowance} ${s.plan?.kind == 'coaching' ? 'classes' : 'days'} · ${d.mode == 'fixed' ? 'Fixed weekly schedule' : 'Flexible attendance'}',
            ),
          Text('Valid ${d.start} through ${s.preview!.expiry} (inclusive)'),
          Text('Total ${bookingMoney(s.preview!.total, s.catalog.currency)}'),
          Text(
            'Collecting ${bookingMoney(s.paymentEntry.received, s.catalog.currency)}',
          ),
          Text(
            'Balance due ${bookingMoney(s.paymentEntry.remaining ?? 0, s.catalog.currency)}',
          ),
          for (final payment in s.paymentEntry.recorded)
            Text(
              '${paymentLabel(payment.method)} · ${bookingMoney(payment.minor ?? 0, s.catalog.currency)}',
            ),
          SizedBox(height: 12.h),
          Text(
            d.mode == 'fixed'
                ? 'Every allotted session counts after it ends, including missed sessions. Attendance is recorded separately.'
                : 'One day is used when staff mark attendance. Multiple visits on the same date use one day. Expiry still applies.',
          ),
          if (d.mode == 'fixed') ...[
            SizedBox(height: 12.h),
            Text('${s.preview!.sessions.length} of $allowance $unit reserved'),
            if (missing > 0)
              Text(
                '$missing $missingUnit ${missing == 1 ? 'has' : 'have'} no reservation and will expire unused on ${s.preview!.expiry}.',
              ),
            for (final visit in s.preview!.sessions)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 3.h),
                child: Text(visit),
              ),
          ],
        ],
      ),
    );
  }
}

class AdmissionPlanAmountField extends StatelessWidget {
  const AdmissionPlanAmountField({
    super.key,
    required this.cubit,
    required this.state,
  });
  final AdmissionCubit cubit;
  final AdmissionState state;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ConfigurationField(
        key: ValueKey('admission-plan-amount-${state.draft.planId}'),
        label: state.subscription
            ? (state.draft.endsOn == null
                  ? 'Monthly fee (${state.catalog.currency})'
                  : 'Fee for this period (${state.catalog.currency})')
            : 'Plan amount (${state.catalog.currency})',
        value: state.planAmountText,
        numeric: true,
        enabled:
            (state.catalog.canCollect || state.subscription) &&
            !state.loading &&
            !state.busy &&
            !state.locked &&
            state.preview == null,
        onChanged: cubit.planAmount,
      ),
      SizedBox(height: 6.h),
      Text(
        state.planAmountError ??
            (state.subscription && state.draft.endsOn == null
                ? '${state.draft.months} ${state.draft.months == 1 ? 'month' : 'months'} · ${bookingMoney(state.planAmount ?? 0, state.catalog.currency)} in all. Each month is collected when it starts.'
                : 'Enter the final fee agreed with the customer.'),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: state.planAmountError == null
              ? null
              : Theme.of(context).colorScheme.error,
        ),
      ),
    ],
  );
}

class AdmissionPaymentFields extends StatelessWidget {
  const AdmissionPaymentFields({
    super.key,
    required this.cubit,
    required this.state,
  });
  final AdmissionCubit cubit;
  final AdmissionState state;
  @override
  Widget build(BuildContext context) {
    final s = state,
        d = s.draft,
        enabled = !s.loading && !s.busy && !s.locked && s.preview == null,
        whole = s.paymentEntry.total,
        // A subscription's first collection is normally its first month.
        total = s.subscription && d.endsOn == null && d.months > 1
            ? d.amountMinor
            : whole,
        theme = Theme.of(context);
    if (s.renewAndCollect && total == 0 && d.payments.isEmpty) {
      return const Text('This renewal has no fee. No payment is required.');
    }
    if (d.payments.isEmpty) {
      // Payment is optional: offer quick full/half collection or confirm unpaid.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (whole != null)
            Text(
              s.subscription && total != whole
                  ? 'First month ${bookingMoney(total ?? 0, s.catalog.currency)} · ${bookingMoney(whole, s.catalog.currency)} in all'
                  : 'Plan total ${bookingMoney(whole, s.catalog.currency)}',
              style: theme.textTheme.titleMedium,
            ),
          SizedBox(height: 4.h),
          Text(
            s.renewAndCollect
                ? 'Choose the payment collected for the new plan, in full or part.'
                : 'Collect now, in full or part, or confirm unpaid and collect later.',
            style: theme.textTheme.bodySmall,
          ),
          SizedBox(height: 14.h),
          if (total != null && total > 0) ...[
            AppButton(
              key: const ValueKey('admission-collect-full'),
              label:
                  'Collect full · ${bookingMoney(total, s.catalog.currency)}',
              icon: Icons.payments_outlined,
              onPressed: enabled ? () => cubit.startCollection(total) : null,
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('admission-collect-half'),
                    onPressed: enabled
                        ? () => cubit.startCollection((total / 2).round())
                        : null,
                    child: Text(
                      'Half · ${bookingMoney((total / 2).round(), s.catalog.currency)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('admission-collect-other'),
                    onPressed: enabled ? () => cubit.startCollection() : null,
                    child: const Text(
                      'Other amount',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ] else
            AppButton(
              key: const ValueKey('admission-collect-other'),
              label: 'Collect payment',
              icon: Icons.payments_outlined,
              secondary: true,
              onPressed: enabled ? () => cubit.startCollection() : null,
            ),
        ],
      );
    }
    return BookingPaymentEditor(
      catalog: s.catalog.paymentCatalog,
      businessId: d.businessId,
      spaceId: d.poolId,
      payments: d.payments,
      enabled: enabled,
      currency: s.catalog.currency,
      entrySummary: s.paymentEntry,
      remainingFor: s.paymentEntry.balanceFor,
      paymentError: s.paymentEntry.errorFor,
      onPayBalance: cubit.payBalance,
      onAdd: cubit.addPayment,
      addLabel: 'Split with another method',
      onRemove: (id) => cubit.update(
        d.copyWith(payments: d.payments.where((p) => p.id != id).toList()),
      ),
      onUpdate: cubit.paymentUpdate,
    );
  }
}
