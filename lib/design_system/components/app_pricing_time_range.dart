import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../utils/helpers/pricing_time_bounds.dart';
import '../../utils/helpers/time_format.dart';

/// Edits both boundaries together; invalid intermediate values never leave the dialog.
class AppPricingTimeRange extends StatelessWidget {
  const AppPricingTimeRange({
    super.key,
    required this.opens,
    required this.closes,
    required this.bounds,
    required this.onChanged,
    this.allDay = false,
    this.enabled = true,
  });
  final String opens, closes;
  final bool allDay, enabled;
  final PricingTimeBounds bounds;
  final void Function(String opens, String closes, bool allDay) onChanged;
  @override
  Widget build(BuildContext context) {
    final error = bounds.validate(opens, closes, allDay: allDay);
    final defaults = bounds.defaultRange;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Opening hours: ${bounds.label}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.schedule_outlined),
              label: Text(
                allDay
                    ? 'All 24 hours'
                    : '${TimeFormat.display(opens)}–${TimeFormat.display(closes)}',
              ),
              onPressed: !enabled || defaults == null
                  ? null
                  : () async {
                      final result = await showDialog<(String, String, bool)>(
                        context: context,
                        builder: (_) => _PricingRangeDialog(
                          opens: opens,
                          closes: closes,
                          allDay: allDay,
                          bounds: bounds,
                        ),
                      );
                      if (result != null && context.mounted) {
                        onChanged(result.$1, result.$2, result.$3);
                      }
                    },
            ),
            TextButton(
              onPressed: !enabled || defaults == null
                  ? null
                  : () => onChanged(
                      defaults.opens,
                      defaults.closes,
                      defaults.allDay,
                    ),
              child: const Text('Use opening hours'),
            ),
          ],
        ),
        if (defaults == null)
          const Text(
            'No shared opening time is available for these days. Check the opening schedule and eligible spaces.',
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}

class _PricingRangeDialog extends StatefulWidget {
  const _PricingRangeDialog({
    required this.opens,
    required this.closes,
    required this.allDay,
    required this.bounds,
  });
  final String opens, closes;
  final bool allDay;
  final PricingTimeBounds bounds;
  @override
  State<_PricingRangeDialog> createState() => _PricingRangeDialogState();
}

class _PricingRangeDialogState extends State<_PricingRangeDialog> {
  final form = GlobalKey<FormState>();
  late final fields = [
    for (final time in [widget.opens, widget.closes])
      ...TimeFormat.display(
        time,
      ).split(':').map((part) => TextEditingController(text: part)),
  ];
  late bool allDay =
      widget.allDay && widget.bounds.allows('00:00', '00:00', allDay: true);
  String? error;
  @override
  void dispose() {
    for (final c in fields) {
      c.dispose();
    }
    super.dispose();
  }

  void submit() {
    if (!allDay && !form.currentState!.validate()) return;
    final start = allDay
        ? '00:00'
        : TimeFormat.normalize('${fields[0].text}:${fields[1].text}')!;
    final end = allDay
        ? '00:00'
        : TimeFormat.normalize('${fields[2].text}:${fields[3].text}')!;
    final message = widget.bounds.validate(start, end, allDay: allDay);
    if (message != null) {
      setState(() => error = message);
      return;
    }
    Navigator.pop(context, (start, end, allDay));
  }

  Widget timeFields(String label, int offset) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: Theme.of(context).textTheme.titleSmall),
      const SizedBox(height: 8),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < 2; i++) ...[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                child: Text(':'),
              ),
            Expanded(
              child: TextFormField(
                controller: fields[offset + i],
                decoration: InputDecoration(
                  labelText: i == 0 ? 'Hour' : 'Minute',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(2),
                ],
                validator: (_) =>
                    TimeFormat.normalize(
                          '${fields[offset].text}:${fields[offset + 1].text}',
                        ) ==
                        null
                    ? 'Invalid time'
                    : null,
                onChanged: (_) {
                  if (error != null) setState(() => error = null);
                },
              ),
            ),
          ],
        ],
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Pricing time range'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opening hours: ${widget.bounds.label}'),
            const SizedBox(height: 16),
            if (widget.bounds.allows('00:00', '00:00', allDay: true)) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('All 24 hours'),
                value: allDay,
                onChanged: (value) => setState(() {
                  allDay = value;
                  error = null;
                }),
              ),
              const SizedBox(height: 12),
            ],
            if (!allDay) ...[
              timeFields('Start time', 0),
              const SizedBox(height: 16),
              timeFields('End time', 2),
            ],
            const SizedBox(height: 12),
            const Text(
              '24-hour time. Use 24:00 for midnight. Overnight ranges must fit opening hours.',
            ),
            if (error != null) ...[
              const SizedBox(height: 12),
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(onPressed: submit, child: const Text('OK')),
    ],
  );
}
