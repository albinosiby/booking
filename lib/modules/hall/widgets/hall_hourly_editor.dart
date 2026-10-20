import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/hall_configuration.dart';
import '../cubit/hall_setup_cubit.dart';
import 'hall_editors.dart';

class HallHourlyEditor extends StatelessWidget {
  const HallHourlyEditor({
    super.key,
    required this.hall,
    required this.cubit,
    required this.disabled,
    required this.currency,
  });
  final HallResource hall;
  final HallSetupCubit cubit;
  final bool disabled;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final p = hall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Hourly pricing', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        Text(
          'Minimum booking duration',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children:
              ({
                    ...[30, 60, 90, 120, 180, 240],
                    ...p.durations,
                  }.toList()..sort())
                  .map(
                    (d) => FilterChip(
                      label: Text('$d min'),
                      selected: p.defaultDuration == d,
                      onSelected: disabled
                          ? null
                          : (v) => cubit.duration(p.id, d, v),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 12),
        const Text(
          'Longer bookings extend in 15-minute increments and are priced proportionally from this minimum.',
        ),
        const SizedBox(height: 22),
        Text('Prices per hall', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
          'The booking start time determines the price. Dated seasonal rules override regular weekly rules. Start times without a rule are unavailable.',
        ),
        const SizedBox(height: 16),
        ...p.tariffs.indexed.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Price rule ${e.$1 + 1}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Remove price rule',
                        onPressed: disabled
                            ? null
                            : () => cubit.removeTariff(p.id, e.$2.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  HallHoursEditor(
                    hours: e.$2.hours,
                    allowedDays: p.hours.days,
                    openingWindows: [p.hours.window],
                    enabled: !disabled,
                    allowDates: true,
                    onChanged: (h) => cubit.tariffHours(p.id, e.$2.id, h),
                  ),
                  const SizedBox(height: 16),
                  ...e.$2.rates
                      .where((r) => r.minutes == p.defaultDuration)
                      .map(
                        (r) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: ConfigurationField(
                            key: ValueKey(
                              'hall-rate-${p.id}-${e.$2.id}-${r.minutes}',
                            ),
                            label:
                                '${r.minutes}-minute price per hall · $currency',
                            value: r.price,
                            numeric: true,
                            enabled: !disabled,
                            validator: hallPrice,
                            onChanged: (v) =>
                                cubit.tariffPrice(p.id, e.$2.id, r.minutes, v),
                          ),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
        AppButton(
          label: 'Add time-based price',
          icon: Icons.add,
          secondary: true,
          onPressed: disabled || p.tariffs.length >= 40
              ? null
              : () => cubit.addTariff(p.id),
        ),
      ],
    );
  }
}
