import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/court_configuration.dart';
import '../models/court_screen_models.dart';
import '../cubit/court_setup_cubit.dart';
import '../widgets/court_editors.dart';

class CourtPricingScreen extends StatelessWidget {
  const CourtPricingScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final CourtPricingModel model;
  final CourtSetupCubit cubit;
  final bool disabled;
  Future<void> copy(BuildContext context, CourtResource source) async {
    final targets = model.courts.where((p) => p.id != source.id).toList();
    final selected = <String>{};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Copy timing and pricing'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Court names, indoor/outdoor and surface details stay separate. Existing prices on selected courts will be replaced.',
                  ),
                  ...targets.map(
                    (p) => CheckboxListTile(
                      title: Text(p.name),
                      value: selected.contains(p.id),
                      onChanged: (v) => setState(
                        () => v == true
                            ? selected.add(p.id)
                            : selected.remove(p.id),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(c, selected.toList()),
              child: const Text('Copy'),
            ),
          ],
        ),
      ),
    );
    if (result != null) cubit.copyPricing(source.id, result);
  }

  @override
  Widget build(BuildContext context) {
    final p = model.selected;
    if (p == null && model.courts.isEmpty) {
      return Column(
        children: [
          const AppEmptyState(
            showCard: false,
            title: 'Nothing added yet',
            message: 'Add your first court to configure it.',
          ),
          AppButton(
            label: 'Add court',
            icon: Icons.add,
            onPressed: disabled ? null : cubit.addCourt,
          ),
        ],
      );
    }
    if (p == null) {
      return CourtItemList(
        items: model.courts
            .map(
              (p) => (
                p.id,
                p.name,
                '${p.tariffs.length} price rules${p.enabled ? '' : ' · disabled'}',
              ),
            )
            .toList(),
        addLabel: '',
        add: null,
        select: (id) => cubit.open(CourtSection.pricing, id: id),
        enabled: !disabled,
      );
    }
    void update(CourtResource Function(CourtResource) change) =>
        cubit.updateCourt(p.id, change);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.name, style: Theme.of(context).textTheme.titleLarge),
        if (model.courts.length > 1) ...[
          const SizedBox(height: 12),
          AppPicker(
            label: 'Use timing & prices from another court',
            value: '',
            items: [
              const PickerItem('', 'Set up manually'),
              ...model.courts
                  .where((other) => other.id != p.id)
                  .map((other) => PickerItem(other.id, other.name)),
            ],
            enabled: !disabled,
            onChanged: (id) async {
              if (id.isNotEmpty &&
                  await confirmAction(
                    context,
                    'Copy timing and pricing?',
                    'This replaces timing, durations and prices for ${p.name}. Its name and physical details stay the same.',
                  )) {
                cubit.copyPricing(id, [p.id]);
              }
            },
          ),
        ],
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Court opening hours',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'When this court is available. Bookings must finish before closing.',
              ),
              const SizedBox(height: 12),
              CourtHoursEditor(
                hours: p.hours,
                enabled: !disabled,
                onChanged: (h) => update((p) => p.copyWith(hours: h)),
              ),
            ],
          ),
        ),
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
        Text(
          'Prices per court',
          style: Theme.of(context).textTheme.titleMedium,
        ),
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
                  CourtHoursEditor(
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
                              'court-rate-${p.id}-${e.$2.id}-${r.minutes}',
                            ),
                            label:
                                '${r.minutes}-minute price per court · ${model.currency}',
                            value: r.price,
                            numeric: true,
                            enabled: !disabled,
                            validator: courtPrice,
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
        const SizedBox(height: 20),
        AppCard(
          padding: const EdgeInsets.all(6),
          child: ExpansionTile(
            key: PageStorageKey('court-buffers-${p.id}'),
            title: const Text('Preparation and cleanup (informational)'),
            subtitle: const Text(
              'Internal only. Does not block back-to-back bookings.',
            ),
            childrenPadding: const EdgeInsets.all(14),
            children: [
              ...[
                (true, p.before, 'Preparation before booking'),
                (false, p.after, 'Cleanup after booking'),
              ].map(
                (v) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AppPicker(
                    label: v.$3,
                    value: '${v.$2}',
                    items:
                        ({
                              ...[
                                0,
                                5,
                                10,
                                15,
                                20,
                                30,
                                45,
                                60,
                                90,
                                120,
                                180,
                                240,
                              ],
                              v.$2,
                            }.toList()..sort())
                            .map((m) => PickerItem('$m', '$m minutes'))
                            .toList(),
                    enabled: !disabled,
                    onChanged: (value) => update(
                      (p) => p.copyWith(
                        before: v.$1 ? int.parse(value) : null,
                        after: v.$1 ? null : int.parse(value),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (model.courts.length > 1)
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy timing and pricing to other courts'),
            onPressed: disabled ? null : () => copy(context, p),
          ),
      ],
    );
  }
}
