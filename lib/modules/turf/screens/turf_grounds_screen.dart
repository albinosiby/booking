import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/turf_configuration.dart';
import '../models/turf_step_models.dart';
import '../cubit/turf_setup_cubit.dart';
import '../widgets/turf_field.dart';
import '../widgets/turf_ground_diagram.dart';

class TurfGroundsScreen extends StatelessWidget {
  const TurfGroundsScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final TurfGroundsScreenModel model;
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
                TurfField(
                  key: ValueKey('ground-${ground.id}'),
                  label: 'Physical ground name',
                  value: ground.name,
                  validator: turfName,
                  enabled: !disabled,
                  onChanged: (name) => cubit.groundName(ground.id, name),
                ),
                const SizedBox(height: 16),
                const Text('How is this ground used?'),
                const SizedBox(height: 8),
                ...TurfArrangement.values.map(
                  (arrangement) => CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      arrangement == TurfArrangement.split
                          ? 'Two halves + combined full ground'
                          : 'One independent court / ground',
                    ),
                    subtitle: Text(
                      arrangement == TurfArrangement.split
                          ? 'Half A and Half B can operate together. Full Ground uses both.'
                          : 'This ground does not share space with other grounds.',
                    ),
                    value: ground.arrangement == arrangement,
                    onChanged: disabled
                        ? null
                        : (value) async {
                            if (value != true ||
                                ground.arrangement == arrangement) {
                              return;
                            }
                            if (await confirmAction(
                              context,
                              'Change ground arrangement?',
                              'This rebuilds the bookable spaces and resets their sport offerings, prices and timing overrides.',
                            )) {
                              cubit.arrangement(ground.id, arrangement);
                            }
                          },
                  ),
                ),
                ReviewMore(
                  title: 'Preview ground layout',
                  children: [
                    TurfGroundDiagram(ground: ground, sports: model.sports),
                  ],
                ),
                if (model.grounds.length > 1)
                  TextButton.icon(
                    onPressed: disabled
                        ? null
                        : () async {
                            if (await confirmAction(
                              context,
                              'Remove ${ground.name}?',
                              'Its spaces and offerings will be removed from this draft.',
                            )) {
                              cubit.removeGround(ground.id);
                            }
                          },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remove ground'),
                  ),
              ],
            ),
          ),
        ),
      ),
      AppButton(
        label: 'Add another physical ground',
        icon: Icons.add,
        secondary: true,
        onPressed: disabled || model.grounds.length >= 10
            ? null
            : cubit.addGround,
      ),
    ],
  );
}
