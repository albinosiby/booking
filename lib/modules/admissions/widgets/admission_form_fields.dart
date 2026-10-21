import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../../bookings/models/booking_models.dart';
import '../../bookings/widgets/booking_widgets.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';

class AdmissionScheduleFields extends StatelessWidget {
  const AdmissionScheduleFields({
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
        enabled = !s.busy && !s.locked && s.preview == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppPicker(
          label: 'Plan',
          value: d.planId,
          enabled: enabled,
          items: s.availablePlans
              .map(
                (p) => PickerItem(
                  p.id,
                  '${p.name} · ${p.kind} · ${bookingMoney(p.total, s.catalog.currency)}',
                ),
              )
              .toList(),
          onChanged: cubit.plan,
        ),
        if (s.plan?.kind == 'coaching')
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
        SizedBox(height: 12.h),
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
              ? 'Allotted sessions count after they end, even when missed.'
              : 'Attendance uses one day per date. No advance slot is reserved.',
        ),
        if (d.mode == 'fixed') ...[
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
          SizedBox(height: 12.h),
          OutlinedButton.icon(
            icon: const Icon(Icons.schedule),
            label: Text('Start time: ${TimeFormat.display(d.time)}'),
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
        ],
        SizedBox(height: 12.h),
        if (s.adjustableVisitDuration) ...[
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
        ] else
          Text(
            'Visit duration: ${d.duration} minutes',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        SizedBox(height: 12.h),
        InputDecorator(
          decoration: const InputDecoration(labelText: 'Expiry date'),
          child: Text(s.expiry ?? 'Calculated at review'),
        ),
        Text(
          'Expiry follows the selected plan validity.',
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
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(d.customer.name, style: Theme.of(context).textTheme.titleLarge),
          Text(d.customer.phone),
          Text(s.plan?.name ?? ''),
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
            Text('${s.preview!.sessions.length} reserved sessions'),
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
        total = s.paymentEntry.total,
        theme = Theme.of(context);
    if (d.payments.isEmpty) {
      // Payment is optional: offer quick full/half collection or confirm unpaid.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (total != null)
            Text(
              'Plan total ${bookingMoney(total, s.catalog.currency)}',
              style: theme.textTheme.titleMedium,
            ),
          SizedBox(height: 4.h),
          Text(
            'Collect now, in full or part, or confirm unpaid and collect later.',
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
