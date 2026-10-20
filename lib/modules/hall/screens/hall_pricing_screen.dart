import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/hall_configuration.dart';
import '../models/hall_screen_models.dart';
import '../cubit/hall_setup_cubit.dart';
import '../widgets/hall_editors.dart';
import '../widgets/hall_hourly_editor.dart';
import '../widgets/hall_package_editor.dart';

class HallPricingScreen extends StatelessWidget {
  const HallPricingScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final HallPricingModel model;
  final HallSetupCubit cubit;
  final bool disabled;
  Future<void> copy(BuildContext context, HallResource source) async {
    final targets = model.halls.where((p) => p.id != source.id).toList();
    final selected = <String>{};
    final result = await showDialog<List<String>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Copy booking options and pricing'),
          content: SizedBox(
            width: 320,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Hall names, capacities and amenities stay separate. Selected halls receive independent copies of all booking options, hours and prices.',
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
    if (p == null) {
      return model.halls.isEmpty
          ? Column(
              children: [
                const AppEmptyState(
                  title: 'Add a hall first',
                  message: 'Each hall has its own booking options and prices.',
                ),
                AppButton(
                  label: 'Configure halls',
                  onPressed: disabled
                      ? null
                      : () => cubit.open(HallSection.halls),
                ),
              ],
            )
          : HallItemList(
              items: model.halls
                  .map(
                    (p) => (
                      p.id,
                      p.name,
                      '${p.hourlyEnabled ? 'Hourly · ' : ''}${p.sessions.where((s) => s.enabled).length} sessions${p.fullDay.enabled ? ' · Full day' : ''}${p.enabled ? '' : ' · disabled'}',
                    ),
                  )
                  .toList(),
              addLabel: '',
              add: null,
              select: (id) => cubit.open(HallSection.pricing, id: id),
              enabled: !disabled,
            );
    }
    if (model.selectedOption == 'hourly') {
      return HallHourlyEditor(
        hall: p,
        cubit: cubit,
        disabled: disabled,
        currency: model.currency,
      );
    }
    final option = [
      p.fullDay,
      ...p.sessions,
    ].where((o) => o.id == model.selectedOption).firstOrNull;
    if (option != null) {
      return HallPackageEditor(
        hall: p,
        option: option,
        cubit: cubit,
        disabled: disabled,
        currency: model.currency,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(p.name, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hall opening hours',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'All booking options must fit these hours. Cleanup does not block bookings.',
              ),
              const SizedBox(height: 12),
              HallHoursEditor(
                hours: p.hours,
                enabled: !disabled,
                onChanged: (h) =>
                    cubit.updateHall(p.id, (p) => p.copyWith(hours: h)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offer hourly bookings'),
                value: p.hourlyEnabled,
                onChanged: disabled
                    ? null
                    : (v) => cubit.updateHall(
                        p.id,
                        (p) => p.copyWith(hourlyEnabled: v),
                      ),
              ),
              AppButton(
                label: 'Configure hourly pricing',
                secondary: true,
                onPressed: disabled ? null : () => cubit.selectOption('hourly'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Morning / evening sessions',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        for (final o in p.sessions) ...[
          AppCard(
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Offer ${o.name} session'),
                  value: o.enabled,
                  onChanged: disabled
                      ? null
                      : (v) => cubit.enablePackage(p.id, o.id, v),
                ),
                AppButton(
                  label: 'Configure ${o.name}',
                  secondary: true,
                  onPressed: disabled ? null : () => cubit.selectOption(o.id),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add session'),
          onPressed: disabled || p.sessions.length >= 12
              ? null
              : () => cubit.addSession(p.id),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Offer full-day package'),
                value: p.fullDay.enabled,
                onChanged: disabled
                    ? null
                    : (v) => cubit.enablePackage(p.id, p.fullDay.id, v),
              ),
              AppButton(
                label: 'Configure full-day package',
                secondary: true,
                onPressed: disabled
                    ? null
                    : () => cubit.selectOption(p.fullDay.id),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preparation and cleanup (informational)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Text(
                'Internal only. Does not block back-to-back bookings.',
              ),
              const SizedBox(height: 12),
              for (final v in [
                (true, p.before, 'Preparation before booking'),
                (false, p.after, 'Cleanup after booking'),
              ]) ...[
                AppPicker(
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
                  onChanged: (x) => cubit.updateHall(
                    p.id,
                    (p) => p.copyWith(
                      before: v.$1 ? int.parse(x) : null,
                      after: v.$1 ? null : int.parse(x),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
        if (model.halls.length > 1)
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined),
            label: const Text(
              'Copy booking options and pricing to other halls',
            ),
            onPressed: disabled ? null : () => copy(context, p),
          ),
      ],
    );
  }
}
