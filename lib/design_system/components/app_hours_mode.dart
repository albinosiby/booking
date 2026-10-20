import 'package:flutter/material.dart';

/// An explicit full-day mode avoids ambiguous equal opening/closing times.
class AppHoursMode extends StatelessWidget {
  const AppHoursMode({
    super.key,
    required this.allDay,
    required this.onChanged,
    this.enabled = true,
    this.pricing = false,
  });
  final bool allDay, enabled, pricing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      ChoiceChip(
        label: Text(pricing ? 'All 24 hours' : 'Open 24 hours'),
        avatar: const Icon(Icons.all_inclusive_rounded, size: 18),
        selected: allDay,
        onSelected: enabled ? (_) => onChanged(true) : null,
      ),
      ChoiceChip(
        label: Text(
          pricing ? 'Set start & end times' : 'Set opening & closing times',
        ),
        selected: !allDay,
        onSelected: enabled ? (_) => onChanged(false) : null,
      ),
    ],
  );
}
