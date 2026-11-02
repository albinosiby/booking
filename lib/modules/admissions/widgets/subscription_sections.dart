import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../design_system/design_system.dart';
import '../../../utils/helpers/subscription_labels.dart';
import '../../../utils/helpers/time_format.dart';
import '../../bookings/models/booking_models.dart';
import '../models/admission_models.dart';
import 'payment_reminders_section.dart' show termMonth;

/// How much of each monthly fee is paid, filling months in order.
List<({AdmissionFee fee, int paid})> feeCoverage(Admission a) {
  var left = a.paid;
  return [
    for (final fee in a.subscription?.fees ?? const <AdmissionFee>[])
      (() {
        final paid = left.clamp(0, fee.amount);
        left -= paid;
        return (fee: fee, paid: paid);
      })(),
  ];
}

/// Each month's fee with its due date and whether it is paid.
class SubscriptionFeesCard extends StatelessWidget {
  const SubscriptionFeesCard({
    super.key,
    required this.admission,
    required this.currency,
    required this.today,
  });
  final Admission admission;
  final String currency, today;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final sub = admission.subscription!;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            sub.months == null
                ? '${bookingMoney(sub.monthly, currency)} for ${sub.periodLabel.toLowerCase()}'
                : '${bookingMoney(sub.monthly, currency)} per month · ${sub.periodLabel}',
            style: theme.textTheme.titleMedium,
          ),
          if (sub.stoppedOn != null)
            Text(
              'Stopped on ${sub.stoppedOn}. Months not started were removed.',
              style: theme.textTheme.bodySmall,
            ),
          SizedBox(height: 8.h),
          for (final (:fee, :paid) in feeCoverage(admission))
            Padding(
              key: ValueKey('subscription-fee-${fee.dueOn}'),
              padding: EdgeInsets.symmetric(vertical: 6.h),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${termMonth(fee.dueOn)} · due ${fee.dueOn}',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  Text(
                    paid >= fee.amount
                        ? 'Paid'
                        : fee.dueOn.compareTo(today) > 0
                        ? bookingMoney(fee.amount - paid, currency)
                        : '${bookingMoney(fee.amount - paid, currency)} due',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: paid >= fee.amount
                          ? scheme.primary
                          : fee.dueOn.compareTo(today) > 0
                          ? null
                          : scheme.error,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

typedef SubscriptionSchedule = ({
  String from,
  List<int> weekdays,
  String time,
  int duration,
  String reason,
});

/// Asks for a new weekly slot that applies from a chosen date.
Future<SubscriptionSchedule?> showRescheduleSheet(
  BuildContext context, {
  required Admission admission,
  required String today,
  required int minimumDuration,
}) => showAdaptiveSheet<SubscriptionSchedule>(
  context: context,
  builder: (_) => _RescheduleSheet(
    admission: admission,
    today: today,
    minimumDuration: minimumDuration,
  ),
);

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({
    required this.admission,
    required this.today,
    required this.minimumDuration,
  });
  final Admission admission;
  final String today;
  final int minimumDuration;
  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late String from = widget.today.compareTo(widget.admission.start) < 0
      ? widget.admission.start
      : widget.today;
  late List<int> weekdays = [...widget.admission.weekdays];
  late String time = widget.admission.time;
  late int duration = widget.admission.duration;
  String reason = '';
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valid = weekdays.isNotEmpty && reason.trim().length >= 2;
    return Padding(
      padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 24.h),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Reschedule subscription', style: theme.textTheme.titleMedium),
          SizedBox(height: 4.h),
          Text(
            'Sessions from the chosen date move to the new days and time. Earlier sessions stay. Taken slots are refused with who holds them.',
            style: theme.textTheme.bodySmall,
          ),
          SizedBox(height: 12.h),
          OutlinedButton.icon(
            key: const ValueKey('reschedule-from'),
            icon: const Icon(Icons.event),
            label: Text('From $from'),
            onPressed: () async {
              final first = DateTime.parse(
                widget.today.compareTo(widget.admission.start) < 0
                    ? widget.admission.start
                    : widget.today,
              );
              final last = DateTime.parse(widget.admission.expiry);
              if (last.isBefore(first)) return;
              final chosen = await showDatePicker(
                context: context,
                initialDate: DateTime.parse(from),
                firstDate: first,
                lastDate: last,
              );
              if (chosen != null) setState(() => from = bookingDate(chosen));
            },
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 6.w,
            runSpacing: 6.h,
            children: [
              for (final e in subscriptionDayPresets.entries)
                ChoiceChip(
                  label: Text(dayPresetLabel(e.key)),
                  selected: dayPresetOf(weekdays) == e.key,
                  onSelected: (_) => setState(() => weekdays = [...e.value]),
                ),
            ],
          ),
          SizedBox(height: 6.h),
          Wrap(
            spacing: 6.w,
            children: [
              for (var day = 1; day <= 7; day++)
                FilterChip(
                  key: ValueKey('reschedule-day-$day'),
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
                  selected: weekdays.contains(day),
                  onSelected: (on) => setState(() {
                    final days = {...weekdays};
                    on ? days.add(day) : days.remove(day);
                    weekdays = days.toList()..sort();
                  }),
                ),
            ],
          ),
          SizedBox(height: 12.h),
          OutlinedButton.icon(
            key: const ValueKey('reschedule-time'),
            icon: const Icon(Icons.schedule),
            label: Text('Start ${TimeFormat.display(time)}'),
            onPressed: () async {
              final t = await showAppTimePicker(
                context: context,
                initialTime: time,
              );
              if (t != null) setState(() => time = t);
            },
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Shorter',
                onPressed: duration - 30 >= widget.minimumDuration
                    ? () => setState(() => duration -= 30)
                    : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Expanded(
                child: Text(
                  '${TimeFormat.display(time)} · ${hoursLabel(duration)}',
                  textAlign: TextAlign.center,
                ),
              ),
              IconButton(
                tooltip: 'Longer',
                onPressed: duration + 30 <= 1440
                    ? () => setState(() => duration += 30)
                    : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
          TextField(
            key: const ValueKey('reschedule-reason'),
            maxLength: 500,
            decoration: const InputDecoration(labelText: 'Reason (required)'),
            onChanged: (v) => setState(() => reason = v),
          ),
          SizedBox(height: 8.h),
          AppButton(
            key: const ValueKey('reschedule-save'),
            label: 'Move sessions',
            icon: Icons.event_repeat_outlined,
            onPressed: valid
                ? () => Navigator.pop(context, (
                    from: from,
                    weekdays: weekdays,
                    time: time,
                    duration: duration,
                    reason: reason.trim(),
                  ))
                : null,
          ),
        ],
      ),
    );
  }
}
