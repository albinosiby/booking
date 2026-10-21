import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/hall_screen_models.dart';
import '../cubit/hall_setup_cubit.dart';

/// Hall setup sections, shared by the overview list and the desktop rail.
List<(HallSection, String, String, IconData)> hallSections(
  HallOverviewModel model,
) => [
  (
    HallSection.halls,
    'Halls',
    '${model.configuration.halls.length} separate halls',
    Icons.sports_tennis,
  ),
  (
    HallSection.pricing,
    'Booking options & pricing',
    'Hourly, sessions and full-day prices per hall',
    Icons.schedule_outlined,
  ),
  (
    HallSection.review,
    'Review & activation',
    model.ready
        ? 'Review saved hall settings'
        : 'Check requirements and activate',
    Icons.fact_check_outlined,
  ),
];

class HallOverviewScreen extends StatelessWidget {
  const HallOverviewScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final HallOverviewModel model;
  final HallSetupCubit cubit;
  final bool disabled;
  Widget tile((HallSection, String, String, IconData) s) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      padding: const EdgeInsets.all(6),
      child: ListTile(
        key: ValueKey('hall-section-${s.$1.name}'),
        leading: Icon(s.$4, color: AppColors.lime),
        title: Text(s.$2),
        subtitle: Text(s.$3),
        trailing: const Icon(Icons.chevron_right),
        onTap: disabled ? null : () => cubit.open(s.$1),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppCard(
        child: Text(
          model.ready
              ? 'Your halls are ready. Open any section to edit directly.'
              : 'Add each separate hall, configure its prices, then review and activate.',
        ),
      ),
      const SizedBox(height: 20),
      if (isDesktopWidth(context))
        AppGrid(
          minTileWidth: 280,
          maxColumns: 2,
          children: [for (final s in hallSections(model)) tile(s)],
        )
      else
        ...hallSections(model).map(tile),
    ],
  );
}
