import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/pool_configuration.dart';
import '../models/pool_screen_models.dart';
import '../cubit/pool_setup_cubit.dart';
import '../widgets/pool_editors.dart';

class PoolResourcesScreen extends StatelessWidget {
  const PoolResourcesScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final PoolResourcesModel model;
  final PoolSetupCubit cubit;
  final bool disabled;
  @override
  Widget build(BuildContext context) {
    final p = model.selected;
    if (p == null) {
      return PoolItemList(
        items: model.pools
            .map(
              (p) => (
                p.id,
                p.name,
                '${p.capacity} people · ${p.minDepth.isEmpty ? 'Depth not set' : '${p.minDepth}–${p.maxDepth} ft'} · ${model.setupStatus(p)}',
              ),
            )
            .toList(),
        addLabel: 'Add pool',
        add: model.pools.length >= 30 ? null : cubit.addPool,
        select: (id) => cubit.open(
          PoolSection.pools,
          id: id,
          resourceFlow: model.needsSetup(
            model.pools.firstWhere((p) => p.id == id),
          ),
        ),
        enabled: !disabled,
      );
    }
    void update(PoolResource Function(PoolResource) change) =>
        cubit.updatePool(p.id, change);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigurationField(
          label: 'Pool name',
          value: p.name,
          enabled: !disabled,
          validator: poolName,
          onChanged: (v) => update((p) => p.copyWith(name: v)),
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Maximum people at the same time',
          value: p.capacity,
          numeric: true,
          enabled: !disabled,
          validator: poolInteger,
          onChanged: (v) => update((p) => p.copyWith(capacity: v)),
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Minimum depth · feet',
          value: p.minDepth,
          numeric: true,
          enabled: !disabled,
          validator: (v) => !p.enabled && (v ?? '').isEmpty
              ? null
              : poolDepth(v ?? '') == null
              ? 'Enter the minimum depth'
              : null,
          onChanged: (v) => update((p) => p.copyWith(minDepth: v)),
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Maximum depth · feet',
          value: p.maxDepth,
          numeric: true,
          enabled: !disabled,
          validator: (v) => !p.enabled && (v ?? '').isEmpty
              ? null
              : poolDepth(v ?? '') == null || poolDepth(v ?? '')! <= 0
              ? 'Enter a positive maximum depth'
              : null,
          onChanged: (v) => update((p) => p.copyWith(maxDepth: v)),
        ),
        const SizedBox(height: 12),
        const Text(
          'Use the same minimum and maximum for a pool with uniform depth.',
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Pool enabled'),
          value: p.enabled,
          onChanged: disabled
              ? null
              : (v) => update((p) => p.copyWith(enabled: v)),
        ),
        const SizedBox(height: 16),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove pool'),
          onPressed: disabled
              ? null
              : () async {
                  if (await confirmAction(
                    context,
                    'Remove ${p.name}?',
                    'This pool will be removed from offers, plans and coach space assignments. Staff-assigned pools cannot be deleted.',
                  )) {
                    cubit.removePool(p.id);
                  }
                },
        ),
      ],
    );
  }
}
