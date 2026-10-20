import 'package:flutter/material.dart';
import '../../utils/helpers/pricing_days.dart';

class AppWeekdayPicker extends StatelessWidget {
  const AppWeekdayPicker({
    super.key,
    required this.days,
    required this.onChanged,
    this.allowedDays,
    this.enabled = true,
    this.presets = true,
  });
  final List<int> days;
  final List<int>? allowedDays;
  final bool enabled, presets;
  final ValueChanged<List<int>> onChanged;
  @override
  Widget build(BuildContext context) {
    final allowed = allowedDays ?? const [1, 2, 3, 4, 5, 6, 7];
    final selected = pricingDays(days, allowed);
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (allowed.isEmpty) {
      return const Text(
        'No opening days available. Set up the space or select eligible pools first.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (presets) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final preset in [
                ('Weekdays', const [1, 2, 3, 4, 5]),
                ('Weekend', const [6, 7]),
                (
                  allowedDays == null ? 'Every day' : 'All open days',
                  const [1, 2, 3, 4, 5, 6, 7],
                ),
              ])
                if (pricingDays(preset.$2, allowed).isNotEmpty)
                  ActionChip(
                    label: Text(preset.$1),
                    onPressed: !enabled
                        ? null
                        : () => onChanged(pricingDays(preset.$2, allowed)),
                  ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (var day = 1; day <= 7; day++)
              if (allowed.contains(day))
                FilterChip(
                  label: Text(names[day - 1]),
                  selected: selected.contains(day),
                  onSelected: !enabled
                      ? null
                      : (checked) => onChanged(
                          pricingDays(
                            checked
                                ? [...selected, day]
                                : selected.where((d) => d != day),
                            allowed,
                          ),
                        ),
                ),
          ],
        ),
        if (allowedDays != null && selected.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Choose at least one open day, or remove this rule.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}
