import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/pool_screen_models.dart';
import '../cubit/pool_setup_cubit.dart';

/// Pool setup sections, shared by the overview list and the desktop rail.
List<(PoolSection, String, String, IconData)> poolSections(
  PoolOverviewModel model,
) {
  final c = model.configuration;
  return [
    (
      PoolSection.pools,
      'Pools',
      '${c.pools.length} pools · capacity and minimum/maximum depths',
      Icons.pool,
    ),
    (
      PoolSection.pricing,
      'Timing & pricing',
      'Opening hours, visit durations and prices per person',
      Icons.schedule_outlined,
    ),
    (
      PoolSection.groups,
      'Group offers',
      '${c.offers.length} offers · exact, maximum or minimum group sizes',
      Icons.groups_outlined,
    ),
    (
      PoolSection.coaching,
      'Coaching plans',
      '${c.plans.where((p) => p.coaching).length} plans · classes, coaches and seats',
      Icons.sports_outlined,
    ),
    (
      PoolSection.plans,
      'Swimming plans',
      '${c.plans.where((p) => !p.coaching).length} plans · attendance days and separate expiry',
      Icons.confirmation_number_outlined,
    ),
    (
      PoolSection.review,
      'Review & activation',
      model.ready
          ? 'Review all saved pool settings'
          : 'Check requirements and activate',
      Icons.fact_check_outlined,
    ),
  ];
}

class PoolOverviewScreen extends StatelessWidget {
  const PoolOverviewScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final PoolOverviewModel model;
  final PoolSetupCubit cubit;
  final bool disabled;
  Widget tile((PoolSection, String, String, IconData) s) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      padding: const EdgeInsets.all(6),
      child: ListTile(
        key: ValueKey('pool-section-${s.$1.name}'),
        leading: Icon(s.$4, color: AppColors.lime),
        title: Text(s.$2),
        subtitle: Text(s.$3),
        trailing: const Icon(Icons.chevron_right),
        onTap: disabled ? null : () => cubit.open(s.$1),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Text(
            model.ready
                ? 'Your pools are ready. Open any section to edit directly.'
                : 'Complete one pool at a time: details, timing and prices. Then add another or review and activate.',
          ),
        ),
        const SizedBox(height: 16),
        AppButton(
          label: 'Add pool',
          icon: Icons.add_rounded,
          onPressed: disabled || model.configuration.pools.length >= 30
              ? null
              : cubit.addPool,
        ),
        const SizedBox(height: 20),
        if (isDesktopWidth(context))
          AppGrid(
            minTileWidth: 280,
            maxColumns: 2,
            children: [for (final s in poolSections(model)) tile(s)],
          )
        else
          ...poolSections(model).map(tile),
      ],
    );
  }
}
