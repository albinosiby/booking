import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../models/turf_configuration.dart';

class TurfHoursEditor extends StatelessWidget {
  const TurfHoursEditor({
    super.key,
    required this.hours,
    required this.onChanged,
    this.enabled = true,
  });
  final TurfHours hours;
  final ValueChanged<TurfHours> onChanged;
  final bool enabled;
  Future<void> pick(BuildContext context, bool opening) async {
    final result = await showAppTimePicker(
      context: context,
      initialTime: opening ? hours.opens : hours.closes,
    );
    if (result != null && context.mounted) {
      onChanged(
        hours.copyWith(
          opens: opening ? result : null,
          closes: opening ? null : result,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
            .asMap()
            .entries
            .map(
              (entry) => FilterChip(
                label: Text(entry.value),
                selected: hours.days.contains(entry.key + 1),
                onSelected: !enabled
                    ? null
                    : (selected) {
                        final days = {...hours.days};
                        selected
                            ? days.add(entry.key + 1)
                            : days.remove(entry.key + 1);
                        onChanged(hours.copyWith(days: days));
                      },
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 12),
      AppHoursMode(
        allDay: hours.allDay,
        enabled: enabled,
        onChanged: (value) {
          if (value == hours.allDay) return;
          onChanged(
            hours.copyWith(
              allDay: value,
              opens: value ? '00:00' : '06:00',
              closes: value ? '00:00' : '23:00',
            ),
          );
        },
      ),
      const SizedBox(height: 12),
      if (hours.allDay)
        const Text('Open all 24 hours on the selected days.')
      else
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            OutlinedButton(
              onPressed: enabled ? () => pick(context, true) : null,
              child: Text('Opens · ${TimeFormat.display(hours.opens)}'),
            ),
            OutlinedButton(
              onPressed: enabled ? () => pick(context, false) : null,
              child: Text('Closes · ${TimeFormat.display(hours.closes)}'),
            ),
          ],
        ),
      const SizedBox(height: 8),
      if (!hours.allDay)
        const Text(
          'A closing time earlier than opening means the next day.',
          style: TextStyle(fontSize: 12),
        ),
    ],
  );
}
