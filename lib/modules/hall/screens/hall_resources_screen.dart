import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/hall_screen_models.dart';
import '../cubit/hall_setup_cubit.dart';
import '../widgets/hall_editors.dart';

class HallResourcesScreen extends StatelessWidget {
  const HallResourcesScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final HallResourcesModel model;
  final HallSetupCubit cubit;
  final bool disabled;
  @override
  Widget build(BuildContext context) {
    final p = model.selected;
    if (p == null) {
      return HallItemList(
        items: model.halls
            .map(
              (p) => (
                p.id,
                p.name,
                '${p.environment == 'unspecified' ? 'Independent hall' : p.environment}${p.amenities.isEmpty ? '' : ' · ${p.amenities}'}${p.enabled ? '' : ' · disabled'}',
              ),
            )
            .toList(),
        addLabel: 'Add hall',
        add: model.halls.length >= 50 ? null : cubit.addHall,
        select: (id) => cubit.open(HallSection.halls, id: id),
        enabled: !disabled,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigurationField(
          label: 'Hall name',
          value: p.name,
          enabled: !disabled,
          validator: hallName,
          onChanged: (v) => cubit.updateHall(p.id, (p) => p.copyWith(name: v)),
        ),

        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Maximum guests',
          value: p.capacity,
          numeric: true,
          enabled: !disabled,
          validator: hallInteger,
          onChanged: (v) =>
              cubit.updateHall(p.id, (p) => p.copyWith(capacity: v)),
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Seated capacity',
          value: p.seated,
          numeric: true,
          enabled: !disabled,
          validator: (v) => int.tryParse(v ?? '') == null || int.parse(v!) < 0
              ? 'Enter a non-negative count'
              : null,
          onChanged: (v) =>
              cubit.updateHall(p.id, (p) => p.copyWith(seated: v)),
        ),
        const SizedBox(height: 16),
        AppPicker(
          label: 'Indoor / outdoor',
          value: p.environment,
          items: const [
            PickerItem('unspecified', 'Not specified'),
            PickerItem('indoor', 'Indoor'),
            PickerItem('outdoor', 'Outdoor'),
          ],
          enabled: !disabled,
          onChanged: (v) =>
              cubit.updateHall(p.id, (p) => p.copyWith(environment: v)),
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Amenities · optional',
          value: p.amenities,
          enabled: !disabled,
          validator: (v) => (v?.trim().length ?? 0) > 1000
              ? 'Use at most 1000 characters'
              : null,
          onChanged: (v) =>
              cubit.updateHall(p.id, (p) => p.copyWith(amenities: v)),
        ),
        const SizedBox(height: 16),
        const AppCard(
          child: Text(
            'Hourly bookings, sessions and full-day packages share this hall. Other halls remain separate.',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Hall enabled'),
          value: p.enabled,
          onChanged: disabled
              ? null
              : (v) => cubit.updateHall(p.id, (p) => p.copyWith(enabled: v)),
        ),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove hall'),
          onPressed: disabled
              ? null
              : () async {
                  if (await confirmAction(
                    context,
                    'Remove ${p.name}?',
                    'Staff-assigned halls cannot be deleted.',
                  )) {
                    cubit.removeHall(p.id);
                  }
                },
        ),
      ],
    );
  }
}
