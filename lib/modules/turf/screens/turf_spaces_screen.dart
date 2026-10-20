import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/turf_step_models.dart';
import '../cubit/turf_setup_cubit.dart';
import '../widgets/turf_field.dart';
import '../widgets/turf_ground_diagram.dart';

class TurfSpacesScreen extends StatelessWidget {
  const TurfSpacesScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final TurfSpacesScreenModel model;
  final TurfSetupCubit cubit;
  final bool disabled;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ...model.grounds.map(
        (ground) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ground.name,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 18),
                TurfGroundDiagram(ground: ground, sports: model.sports),
                const SizedBox(height: 22),
                ...model.layouts
                    .where((layout) => layout.groundId == ground.id)
                    .map(
                      (layout) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: TurfField(
                          key: ValueKey('layout-${layout.id}'),
                          label: layout.sectionIds.length == 2
                              ? 'Full-ground space name'
                              : ground.sections.length == 1
                              ? 'Space name'
                              : layout.sectionIds.first ==
                                    ground.sections.first.id
                              ? 'Half A space name'
                              : 'Half B space name',
                          value: layout.name,
                          validator: turfName,
                          enabled: !disabled,
                          onChanged: (value) =>
                              cubit.spaceName(layout.id, value),
                        ),
                      ),
                    ),
                Text(
                  ground.sections.length > 1
                      ? 'Full Ground occupies both halves. These are booking choices on one physical ground.'
                      : 'This is one independent ground with a single booking space.',
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
