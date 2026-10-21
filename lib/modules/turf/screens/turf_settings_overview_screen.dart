import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/turf_step_models.dart';
import '../cubit/turf_setup_cubit.dart';

/// Turf settings areas, in step order, shared by the overview list and the
/// desktop rail.
List<(String, String, IconData)> turfSettingsAreas(
  TurfSettingsOverviewModel model,
) {
  final config = model.configuration;
  return [
    ('Sports', 'Choose Football, Cricket or both', Icons.sports_soccer),
    (
      'Grounds',
      '${config.grounds.length} physical grounds · shared or independent',
      Icons.landscape_outlined,
    ),
    (
      'Spaces',
      'Half A, Half B and Full Ground names',
      Icons.grid_view_outlined,
    ),
    (
      'Sports & formats',
      'Enable sports and edit offering names and formats',
      Icons.tune,
    ),
    (
      'Timing & pricing',
      'Durations, weekday/time rates, opening hours and preparation/cleanup times',
      Icons.payments_outlined,
    ),
    (
      'Review & activation',
      model.ready
          ? 'Review your complete configuration'
          : 'Check requirements and activate your turf',
      Icons.fact_check_outlined,
    ),
  ];
}

class TurfSettingsOverviewScreen extends StatelessWidget {
  const TurfSettingsOverviewScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final TurfSettingsOverviewModel model;
  final TurfSetupCubit cubit;
  final bool disabled;
  Widget tile((int, (String, String, IconData)) entry) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: AppCard(
      padding: const EdgeInsets.all(6),
      child: ListTile(
        key: ValueKey('turf-settings-section-${entry.$1}'),
        leading: Icon(entry.$2.$3, color: AppColors.lime),
        title: Text(entry.$2.$1),
        subtitle: Text(entry.$2.$2),
        trailing: const Icon(Icons.chevron_right),
        onTap: disabled ? null : () => cubit.openSettingsSection(entry.$1),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final areas = turfSettingsAreas(model);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Text(
            model.dirty
                ? 'You have unsaved changes. Open the relevant section to save them.'
                : model.ready
                ? 'Your turf is ready. Edit any section directly.'
                : 'This turf is not activated. You can edit any section and activate when ready.',
          ),
        ),
        const SizedBox(height: 20),
        if (isDesktopWidth(context))
          AppGrid(
            minTileWidth: 280,
            maxColumns: 2,
            children: [for (final entry in areas.indexed) tile(entry)],
          )
        else
          ...areas.indexed.map(tile),
      ],
    );
  }
}
