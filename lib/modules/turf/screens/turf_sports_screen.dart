import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/turf_configuration.dart';
import '../models/turf_step_models.dart';
import '../cubit/turf_setup_cubit.dart';

class TurfSportsScreen extends StatelessWidget {
  const TurfSportsScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final TurfSportsScreenModel model;
  final TurfSetupCubit cubit;
  final bool disabled;
  @override
  Widget build(BuildContext context) => Column(
    children: [
      ...TurfSport.values.map(
        (sport) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: AppCard(
            padding: const EdgeInsets.all(6),
            child: CheckboxListTile(
              key: ValueKey('turf-sport-${sport.name}'),
              title: Text(sport.label),
              subtitle: Text(
                sport == TurfSport.football
                    ? '5s halves and a combined 7s ground'
                    : 'Half-ground and full-ground cricket',
              ),
              secondary: Icon(
                sport == TurfSport.football
                    ? Icons.sports_soccer
                    : Icons.sports_cricket,
                color: AppColors.lime,
              ),
              value: model.selected.contains(sport),
              onChanged: disabled
                  ? null
                  : (value) => cubit.sport(sport, value == true),
            ),
          ),
        ),
      ),
      const Text(
        'Both sports use the same physical sections. Changing the sport never creates extra space.',
      ),
    ],
  );
}
