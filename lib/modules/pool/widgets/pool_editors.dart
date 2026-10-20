import '../../../utils/helpers/operating_window.dart';
import '../../../utils/helpers/pricing_time_bounds.dart';
import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/time_format.dart';
import '../../../utils/helpers/validation.dart';
import '../models/pool_configuration.dart';

String? poolName(String? value) =>
    value == null || value.trim().length < 2 || value.trim().length > 100
    ? 'Use 2–100 characters'
    : null;
String? poolInteger(String? value) =>
    int.tryParse(value ?? '') == null ||
        int.parse(value!) < 1 ||
        int.parse(value) > 10000
    ? 'Enter 1–10000'
    : null;
String? poolPrice(String? value) =>
    Validation.priceMinor(value ?? '') == null ? 'Enter a valid amount' : null;
String dateText(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

class PoolDateButton extends StatelessWidget {
  const PoolDateButton({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    icon: const Icon(Icons.calendar_month_outlined),
    label: Text('$label · ${value ?? 'Choose date'}'),
    onPressed: !enabled
        ? null
        : () async {
            var initial = DateTime.tryParse(value ?? '') ?? DateTime.now();
            final first = DateTime(2000), last = DateTime(2100, 12, 31);
            if (initial.isBefore(first)) initial = first;
            if (initial.isAfter(last)) initial = last;
            final date = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: first,
              lastDate: last,
            );
            if (date != null && context.mounted) onChanged(dateText(date));
          },
  );
}

class PoolHoursEditor extends StatelessWidget {
  const PoolHoursEditor({
    super.key,
    required this.hours,
    required this.onChanged,
    this.enabled = true,
    this.allowedDays,
    this.openingWindows,
    this.allowDates = false,
  });
  final List<OperatingWindow>? openingWindows;
  final List<int>? allowedDays;
  final PoolHours hours;
  final ValueChanged<PoolHours> onChanged;
  final bool enabled, allowDates;
  Future<void> pick(BuildContext context, bool start) async {
    final value = await showAppTimePicker(
      context: context,
      initialTime: start ? hours.opens : hours.closes,
    );
    if (value != null && context.mounted) {
      onChanged(
        hours.copyWith(
          opens: start ? value : null,
          closes: start ? null : value,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppWeekdayPicker(
        days: hours.days,
        allowedDays: allowedDays,
        enabled: enabled,
        onChanged: (days) => onChanged(hours.copyWith(days: days)),
      ),
      if (openingWindows != null) ...[
        const SizedBox(height: 14),
        AppPricingTimeRange(
          opens: hours.opens,
          closes: hours.closes,
          allDay: hours.allDay,
          bounds: PricingTimeBounds(openingWindows!, hours.days),
          enabled: enabled,
          onChanged: (opens, closes, allDay) => onChanged(
            hours.copyWith(opens: opens, closes: closes, allDay: allDay),
          ),
        ),
      ] else ...[
        const SizedBox(height: 14),
        AppHoursMode(
          allDay: hours.allDay,
          enabled: enabled,
          pricing: allowDates,
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
          const Text('Available for all 24 hours on the selected days.')
        else
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              OutlinedButton(
                onPressed: enabled ? () => pick(context, true) : null,
                child: Text('Start time · ${TimeFormat.display(hours.opens)}'),
              ),
              OutlinedButton(
                onPressed: enabled ? () => pick(context, false) : null,
                child: Text('End time · ${TimeFormat.display(hours.closes)}'),
              ),
            ],
          ),
      ],
      if (allowDates) ...[
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Specific date range'),
          subtitle: const Text(
            'Use for seasonal prices or limited-time offers.',
          ),
          value: hours.dated,
          onChanged: enabled
              ? (v) {
                  final today = DateTime.now();
                  onChanged(
                    v
                        ? hours.copyWith(
                            dateFrom: dateText(today),
                            dateUntil: dateText(
                              today.add(const Duration(days: 30)),
                            ),
                          )
                        : hours.copyWith(clearDates: true),
                  );
                }
              : null,
        ),
        if (hours.dated)
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              PoolDateButton(
                label: 'From date',
                value: hours.dateFrom,
                enabled: enabled,
                onChanged: (v) => onChanged(hours.copyWith(dateFrom: v)),
              ),
              PoolDateButton(
                label: 'Until date',
                value: hours.dateUntil,
                enabled: enabled,
                onChanged: (v) => onChanged(hours.copyWith(dateUntil: v)),
              ),
            ],
          ),
      ],
    ],
  );
}

class PoolEligibilityEditor extends StatelessWidget {
  const PoolEligibilityEditor({
    super.key,
    required this.pools,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });
  final List<PoolResource> pools;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Eligible pools', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      ...pools.map(
        (p) => CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(p.name),
          subtitle: Text(
            '${p.capacity} people${p.enabled ? '' : ' · disabled'}',
          ),
          value: selected.contains(p.id),
          onChanged: enabled && (p.enabled || selected.contains(p.id))
              ? (v) {
                  final ids = {...selected};
                  v == true ? ids.add(p.id) : ids.remove(p.id);
                  onChanged(ids.toList());
                }
              : null,
        ),
      ),
    ],
  );
}

class PoolDurationPicker extends StatelessWidget {
  const PoolDurationPicker({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final String label;
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) => AppPicker(
    label: label,
    enabled: enabled,
    value: '$value',
    items: ({
      ...[30, 60, 90, 120, 180, 240, 480, 720, 1440],
      value,
    }.toList()..sort()).map((v) => PickerItem('$v', '$v minutes')).toList(),
    onChanged: (v) => onChanged(int.parse(v)),
  );
}

class PoolItemList extends StatelessWidget {
  const PoolItemList({
    super.key,
    required this.items,
    required this.addLabel,
    required this.add,
    required this.select,
    this.enabled = true,
  });
  final List<(String, String, String)> items;
  final String addLabel;
  final VoidCallback? add;
  final ValueChanged<String> select;
  final bool enabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ...items.map(
        (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: const EdgeInsets.all(6),
            child: ListTile(
              key: ValueKey('pool-item-${i.$1}'),
              title: Text(i.$2),
              subtitle: Text(i.$3),
              trailing: const Icon(Icons.chevron_right),
              onTap: enabled ? () => select(i.$1) : null,
            ),
          ),
        ),
      ),
      if (items.isEmpty)
        const AppEmptyState(
          showCard: false,
          title: 'Nothing added yet',
          message: 'Add your first item to configure it.',
        ),
      if (add != null) ...[
        const SizedBox(height: 16),
        AppButton(
          label: addLabel,
          icon: Icons.add,
          onPressed: enabled ? add : null,
        ),
      ],
    ],
  );
}
