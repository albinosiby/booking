import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/hall_configuration.dart';
import '../cubit/hall_setup_cubit.dart';
import 'hall_editors.dart';

class HallPackageEditor extends StatelessWidget {
  const HallPackageEditor({
    super.key,
    required this.hall,
    required this.option,
    required this.cubit,
    required this.disabled,
    required this.currency,
  });
  final HallResource hall;
  final HallPackage option;
  final HallSetupCubit cubit;
  final bool disabled;
  final String currency;
  @override
  Widget build(BuildContext context) {
    final full = option.id == hall.fullDay.id;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigurationField(
          label: full ? 'Package name' : 'Session name',
          value: option.name,
          enabled: !disabled,
          validator: hallName,
          onChanged: (v) => cubit.updatePackage(
            hall.id,
            option.id,
            (o) => o.copyWith(name: v),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(full ? 'Full-day package enabled' : 'Session enabled'),
          value: option.enabled,
          onChanged: disabled
              ? null
              : (v) => cubit.enablePackage(hall.id, option.id, v),
        ),
        const SizedBox(height: 12),
        Text(
          full ? 'Full-day package hours' : 'Session hours',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        HallHoursEditor(
          hours: option.hours,
          allowedDays: hall.hours.days,
          openingWindows: [hall.hours.window],
          enabled: !disabled,
          onChanged: (h) => cubit.updatePackage(
            hall.id,
            option.id,
            (o) => o.copyWith(hours: h),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Set a total price for the entire session or package. Dated seasonal prices override weekly prices. Days without a matching price are unavailable.',
        ),
        const SizedBox(height: 16),
        for (final r in option.prices)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Package price rule')),
                      IconButton(
                        tooltip: 'Remove package price',
                        onPressed: disabled
                            ? null
                            : () => cubit.removePackagePrice(
                                hall.id,
                                option.id,
                                r.id,
                              ),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  HallHoursEditor(
                    hours: r.window,
                    allowedDays: option.hours.days,
                    showTimes: false,
                    allowDates: true,
                    enabled: !disabled,
                    onChanged: (h) => cubit.updatePackagePrice(
                      hall.id,
                      option.id,
                      r.id,
                      (r) => r.copyWith(window: h),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ConfigurationField(
                    key: ValueKey('hall-package-price-${option.id}-${r.id}'),
                    label: 'Total package price · $currency',
                    value: r.price,
                    numeric: true,
                    enabled: !disabled,
                    validator: (v) => !option.enabled && (v ?? '').isEmpty
                        ? null
                        : hallPrice(v),
                    onChanged: (v) => cubit.updatePackagePrice(
                      hall.id,
                      option.id,
                      r.id,
                      (r) => r.copyWith(price: v),
                    ),
                  ),
                ],
              ),
            ),
          ),
        AppButton(
          label: 'Add package price',
          icon: Icons.add,
          secondary: true,
          onPressed: disabled || option.prices.length >= 40
              ? null
              : () => cubit.addPackagePrice(hall.id, option.id),
        ),
        if (!full)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('Remove session'),
            onPressed: disabled
                ? null
                : () async {
                    if (await confirmAction(
                      context,
                      'Remove ${option.name}?',
                      'This session and its prices will be removed.',
                    )) {
                      cubit.removeSession(hall.id, option.id);
                    }
                  },
          ),
      ],
    );
  }
}
