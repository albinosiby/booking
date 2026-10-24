import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../config/routes/routes.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/coach_classes_cubit.dart';
import '../models/coach_class.dart';

/// A retained Home roster using the same attendance rules as My classes.
class TodayStudentsSection extends StatefulWidget {
  const TodayStudentsSection({super.key});

  @override
  State<TodayStudentsSection> createState() => _TodayStudentsSectionState();
}

class _TodayStudentsSectionState extends State<TodayStudentsSection>
    with WidgetsBindingObserver {
  late final cubit = getIt<CoachClassesCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..refreshToday(force: true);
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => cubit.refreshToday(),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) cubit.refreshToday(force: true);
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    cubit.close();
    super.dispose();
  }

  Future<void> openClasses() async {
    await context.push(Routes.myClasses);
    if (mounted) await cubit.refreshToday(force: true);
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CoachClassesCubit, CoachClassesState>(
    bloc: cubit,
    builder: (context, state) {
      final theme = Theme.of(context);
      final classes = [...state.classes]
        ..sort((a, b) => a.localStart.compareTo(b.localStart));
      final students = [for (final c in classes) ...c.students];
      final disabled = state.busy || state.loading;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Semantics(
                header: true,
                child: Text(
                  'Today’s students',
                  style: theme.textTheme.titleLarge,
                ),
              ),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: 'Refresh today’s students',
                    onPressed: disabled
                        ? null
                        : () => cubit.refreshToday(force: true),
                    icon: const Icon(Icons.refresh),
                  ),
                  TextButton.icon(
                    onPressed: disabled ? null : openClasses,
                    icon: const Icon(Icons.sports_outlined, size: 18),
                    label: const Text('My classes'),
                  ),
                ],
              ),
            ],
          ),
          Text(
            'Mark attendance for today’s scheduled classes. Times are local to each business.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (state.loading)
            const AppLoadingState(label: 'Loading today’s students…'),
          if (state.error != null)
            AppErrorWidget(
              message: state.error!,
              onRetry: () => cubit.refreshToday(force: true),
            ),
          if (!state.loading && state.error == null && students.isEmpty)
            const AppEmptyState(
              showCard: false,
              title: 'No students scheduled today',
              message:
                  'Students booked into your assigned coaching classes will appear here.',
              icon: Icons.school_outlined,
            ),
          if (students.isNotEmpty) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                state.busy
                    ? 'Saving attendance…'
                    : '${students.length} scheduled · ${students.where((s) => s.attendance == 'present').length} present · ${students.where((s) => s.attendance == 'absent').length} absent',
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 12),
            AppGrid(
              minTileWidth: 320,
              maxColumns: 3,
              gap: 12,
              children: [
                for (final c in classes)
                  for (final student in c.students)
                    _StudentTile(
                      key: ValueKey(student.visitId),
                      session: c,
                      student: student,
                      enabled: !disabled && state.error == null,
                      onMark: (value) => cubit.mark(student, value),
                    ),
              ],
            ),
          ],
        ],
      );
    },
  );
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({
    super.key,
    required this.session,
    required this.student,
    required this.enabled,
    required this.onMark,
  });

  final CoachClass session;
  final CoachStudent student;
  final bool enabled;
  final ValueChanged<String> onMark;

  String time(BuildContext context, String local) {
    final date = DateTime.parse(local);
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay(hour: date.hour, minute: date.minute),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final (label, icon, color) = switch (student.attendance) {
      'present' => ('Present', Icons.check_circle_outline, colors.tertiary),
      'absent' => ('Absent', Icons.cancel_outlined, colors.error),
      _ => (
        'Not marked',
        Icons.radio_button_unchecked,
        colors.onSurfaceVariant,
      ),
    };
    final classTime =
        '${time(context, session.localStart)} – ${time(context, session.localEnd)}';
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: const Icon(Icons.person_outline),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  student.name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.schedule, size: 18, color: colors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  classTime,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(session.planName, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(
            '${session.spaceName} · ${session.businessName}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Row(
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.labelLarge?.copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
          if (student.markable && student.attendance == 'unmarked') ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: ValueKey('present-${student.visitId}'),
                  onPressed: enabled ? () => onMark('present') : null,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Present'),
                ),
                OutlinedButton.icon(
                  key: ValueKey('absent-${student.visitId}'),
                  onPressed: enabled ? () => onMark('absent') : null,
                  icon: const Icon(Icons.close, size: 18),
                  label: const Text('Absent'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
