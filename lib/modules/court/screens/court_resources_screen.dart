import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/court_screen_models.dart';
import '../cubit/court_setup_cubit.dart';
import '../widgets/court_editors.dart';

class CourtResourcesScreen extends StatelessWidget {
  const CourtResourcesScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final CourtResourcesModel model;
  final CourtSetupCubit cubit;
  final bool disabled;
  @override
  Widget build(BuildContext context) {
    final p = model.selected;
    if (p == null) {
      return CourtItemList(
        items: model.courts
            .map(
              (p) => (
                p.id,
                p.name,
                '${p.environment == 'unspecified' ? 'Independent court' : p.environment}${p.surface.isEmpty ? '' : ' · ${p.surface}'} · ${model.setupStatus(p)}',
              ),
            )
            .toList(),
        addLabel: 'Add court',
        add: model.courts.length >= 50 ? null : cubit.addCourt,
        select: (id) => cubit.open(
          CourtSection.courts,
          id: id,
          resourceFlow: model.needsSetup(
            model.courts.firstWhere((p) => p.id == id),
          ),
        ),
        enabled: !disabled,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigurationField(
          label: 'Court name',
          value: p.name,
          enabled: !disabled,
          validator: courtName,
          onChanged: (v) => cubit.updateCourt(p.id, (p) => p.copyWith(name: v)),
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
              cubit.updateCourt(p.id, (p) => p.copyWith(environment: v)),
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Surface type · optional',
          value: p.surface,
          enabled: !disabled,
          validator: (v) =>
              (v?.trim().length ?? 0) > 80 ? 'Use at most 80 characters' : null,
          onChanged: (v) =>
              cubit.updateCourt(p.id, (p) => p.copyWith(surface: v)),
        ),
        const SizedBox(height: 16),
        const AppCard(
          child: Text(
            'This court is a separate bookable space. A booking here leaves the other courts available.',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Court enabled'),
          value: p.enabled,
          onChanged: disabled
              ? null
              : (v) => cubit.updateCourt(p.id, (p) => p.copyWith(enabled: v)),
        ),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove court'),
          onPressed: disabled
              ? null
              : () async {
                  if (await confirmAction(
                    context,
                    'Remove ${p.name}?',
                    'Staff-assigned courts cannot be deleted.',
                  )) {
                    cubit.removeCourt(p.id);
                  }
                },
        ),
      ],
    );
  }
}
