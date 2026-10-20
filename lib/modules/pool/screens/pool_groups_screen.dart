import '../../../utils/helpers/pricing_days.dart';
import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/pool_screen_models.dart';
import '../cubit/pool_setup_cubit.dart';
import '../widgets/pool_editors.dart';

class PoolGroupsScreen extends StatelessWidget {
  const PoolGroupsScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final PoolGroupsModel model;
  final PoolSetupCubit cubit;
  final bool disabled;
  @override
  Widget build(BuildContext context) {
    final o = model.selected;
    if (o == null && !model.pools.any((p) => p.enabled)) {
      return Column(
        children: [
          const AppEmptyState(
            title: 'Add a pool first',
            message: 'Group offers need at least one enabled pool.',
          ),
          AppButton(
            label: 'Configure pools',
            onPressed: disabled ? null : () => cubit.open(PoolSection.pools),
          ),
        ],
      );
    }
    if (o == null) {
      return PoolItemList(
        items: model.offers
            .map(
              (o) => (
                o.id,
                o.name,
                '${o.sizeLabel} · ${o.duration} min · ${model.currency} ${o.price.isEmpty ? 'not set' : o.price}${o.enabled ? '' : ' · disabled'}',
              ),
            )
            .toList(),
        addLabel: 'Add group offer',
        add: model.pools.any((p) => p.enabled) && model.offers.length < 50
            ? cubit.addOffer
            : null,
        select: (id) => cubit.open(PoolSection.groups, id: id),
        enabled: !disabled,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigurationField(
          label: 'Group offer name',
          value: o.name,
          enabled: !disabled,
          validator: poolName,
          onChanged: (v) => cubit.updateOffer(o.id, (o) => o.copyWith(name: v)),
        ),
        const SizedBox(height: 16),
        PoolEligibilityEditor(
          pools: model.pools,
          selected: o.poolIds,
          enabled: !disabled,
          onChanged: (ids) =>
              cubit.updateOffer(o.id, (o) => o.copyWith(poolIds: ids)),
        ),
        const SizedBox(height: 16),
        AppPicker(
          label: 'Group size rule',
          value: o.mode,
          enabled: !disabled,
          items: const [
            PickerItem('exact', 'Exactly this many people'),
            PickerItem('up_to', 'Up to this many people'),
            PickerItem('at_least', 'At least this many people'),
          ],
          onChanged: (v) => cubit.updateOffer(o.id, (o) => o.copyWith(mode: v)),
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: switch (o.mode) {
            'exact' => 'Exact group size',
            'at_least' => 'Minimum group size',
            _ => 'Maximum group size',
          },
          value: o.people,
          numeric: true,
          enabled: !disabled,
          validator: poolInteger,
          onChanged: (v) =>
              cubit.updateOffer(o.id, (o) => o.copyWith(people: v)),
        ),
        const SizedBox(height: 16),
        Text(o.sizeExplanation, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 16),
        PoolDurationPicker(
          label: 'Group visit duration',
          value: o.duration,
          enabled: !disabled,
          onChanged: (v) =>
              cubit.updateOffer(o.id, (o) => o.copyWith(duration: v)),
        ),
        const SizedBox(height: 16),
        ConfigurationField(
          label: 'Total group price · ${model.currency}',
          value: o.price,
          numeric: true,
          enabled: !disabled,
          validator: (v) =>
              !o.enabled && (v ?? '').isEmpty ? null : poolPrice(v),
          onChanged: (v) =>
              cubit.updateOffer(o.id, (o) => o.copyWith(price: v)),
        ),
        const SizedBox(height: 12),
        const Text(
          'This is the total package price, not a price per person. Staff record the actual group size. Groups share capacity with other swimmers.',
        ),
        const SizedBox(height: 20),
        Text(
          'Applicable days and times',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        PoolHoursEditor(
          hours: o.hours,
          openingWindows: model.pools
              .where((pool) => o.poolIds.contains(pool.id))
              .map((pool) => pool.hours.window)
              .toList(),
          allowedDays: commonOpeningDays(
            model.pools
                .where((pool) => o.poolIds.contains(pool.id))
                .map((pool) => pool.hours.days),
          ),
          allowDates: true,
          enabled: !disabled,
          onChanged: (h) =>
              cubit.updateOffer(o.id, (o) => o.copyWith(hours: h)),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Offer enabled'),
          value: o.enabled,
          onChanged: disabled
              ? null
              : (v) => cubit.updateOffer(o.id, (o) => o.copyWith(enabled: v)),
        ),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove group offer'),
          onPressed: disabled
              ? null
              : () async {
                  if (await confirmAction(
                    context,
                    'Remove ${o.name}?',
                    'This offer will be removed from configuration.',
                  )) {
                    cubit.removeOffer(o.id);
                  }
                },
        ),
      ],
    );
  }
}
