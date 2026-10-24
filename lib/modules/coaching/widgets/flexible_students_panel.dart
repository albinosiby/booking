import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../cubit/coach_classes_cubit.dart';
import '../models/coach_class.dart';

/// Shared flexible enrolment tiles for Home and My classes.
class FlexibleStudentsPanel extends StatelessWidget {
  const FlexibleStudentsPanel({
    super.key,
    required this.state,
    required this.onPresent,
  });
  final CoachClassesState state;
  final ValueChanged<FlexibleCoachStudent> onPresent;

  String time(BuildContext context, String value) {
    final local = DateTime.parse(value);
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: local.hour, minute: local.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (state.flexibleStudents.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context), colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 20),
        Semantics(
          header: true,
          child: Text('Flexible students', style: theme.textTheme.titleLarge),
        ),
        const SizedBox(height: 6),
        Text(
          'Mark present on arrival. Start a class with its first student, or join the class already running.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        AppGrid(
          minTileWidth: 320,
          maxColumns: 3,
          gap: 12,
          children: [
            for (final student in state.flexibleStudents)
              AppCard(
                key: ValueKey('flexible-${student.admissionId}'),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      student.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(student.planName),
                    Text(
                      '${student.spaceName} · ${student.businessName}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Flexible · ${student.remaining} days remaining',
                      style: theme.textTheme.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    if (student.localStart != null && student.localEnd != null)
                      Text(
                        'Class ${time(context, student.localStart!)} – ${time(context, student.localEnd!)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: colors.primary,
                        ),
                      )
                    else
                      Text(
                        '${student.durationMinutes}-minute class',
                        style: theme.textTheme.labelLarge,
                      ),
                    if (student.present) ...[
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          student.localMarkedAt == null
                              ? 'Present today'
                              : 'Present at ${time(context, student.localMarkedAt!)}',
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.tertiary,
                          ),
                        ),
                      ),
                    ] else if (student.canMark) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          key: ValueKey(
                            'flexible-present-${student.admissionId}',
                          ),
                          onPressed:
                              state.busy ||
                                  state.loading ||
                                  state.pendingCheckIn ||
                                  state.error != null
                              ? null
                              : () => onPresent(student),
                          icon: Icon(
                            student.action == 'start'
                                ? Icons.play_arrow
                                : Icons.check,
                            size: 18,
                          ),
                          label: Text(
                            student.action == 'start'
                                ? 'Start class & mark present'
                                : 'Mark present',
                          ),
                        ),
                      ),
                    ] else if (student.reason != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        student.reason!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}
