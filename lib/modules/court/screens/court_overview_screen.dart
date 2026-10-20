import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/court_screen_models.dart';
import '../cubit/court_setup_cubit.dart';

class CourtOverviewScreen extends StatelessWidget {
  const CourtOverviewScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final CourtOverviewModel model;
  final CourtSetupCubit cubit;
  final bool disabled;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AppCard(
        child: Text(
          model.ready
              ? 'Your courts are ready. Open any section to edit directly.'
              : 'Complete one court at a time: details, timing and prices. Then add another or review and activate.',
        ),
      ),
      const SizedBox(height: 16),
      AppButton(
        label: 'Add court',
        icon: Icons.add_rounded,
        onPressed: disabled || model.configuration.courts.length >= 50
            ? null
            : cubit.addCourt,
      ),
      const SizedBox(height: 20),
      ...[
        (
          CourtSection.courts,
          'Courts',
          '${model.configuration.courts.length} separate courts',
          Icons.sports_tennis,
        ),
        (
          CourtSection.pricing,
          'Timing & pricing',
          'Individual hours, durations and prices per court',
          Icons.schedule_outlined,
        ),
        (
          CourtSection.review,
          'Review & activation',
          model.ready
              ? 'Review saved court settings'
              : 'Check requirements and activate',
          Icons.fact_check_outlined,
        ),
      ].map(
        (s) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            padding: const EdgeInsets.all(6),
            child: ListTile(
              key: ValueKey('court-section-${s.$1.name}'),
              leading: Icon(s.$4, color: AppColors.lime),
              title: Text(s.$2),
              subtitle: Text(s.$3),
              trailing: const Icon(Icons.chevron_right),
              onTap: disabled ? null : () => cubit.open(s.$1),
            ),
          ),
        ),
      ),
    ],
  );
}
