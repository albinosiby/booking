import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../cubit/coach_classes_cubit.dart';
import '../models/coach_class.dart';

/// A coach's classes for one day, with each student's attendance.
class CoachClassesScreen extends StatefulWidget {
  const CoachClassesScreen({super.key});
  @override
  State<CoachClassesScreen> createState() => _CoachClassesScreenState();
}

class _CoachClassesScreenState extends State<CoachClassesScreen> {
  late final cubit = getIt<CoachClassesCubit>()..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  DateTime day(CoachClassesState s) => DateTime.parse(s.date);

  Future<void> pick(CoachClassesState s) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: day(s),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) await cubit.show(picked);
  }

  Widget dateBar(CoachClassesState s) {
    final d = day(s);
    return Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: s.busy
              ? null
              : () => cubit.show(d.subtract(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: TextButton.icon(
            onPressed: s.busy ? null : () => pick(s),
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: Text(
              MaterialLocalizations.of(context).formatFullDate(d),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: s.busy
              ? null
              : () => cubit.show(d.add(const Duration(days: 1))),
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget student(CoachClassesState s, CoachStudent v) {
    final colors = Theme.of(context).colorScheme;
    final (label, color) = switch (v.attendance) {
      'present' => ('Present', colors.tertiary),
      'absent' => ('Absent', colors.error),
      _ => ('Not marked', colors.onSurfaceVariant),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 140),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(label, style: TextStyle(color: color, fontSize: 13)),
              ],
            ),
          ),
          if (v.markable) ...[
            OutlinedButton(
              onPressed: s.busy ? null : () => cubit.mark(v, 'present'),
              child: const Text('Present'),
            ),
            OutlinedButton(
              onPressed: s.busy ? null : () => cubit.mark(v, 'absent'),
              child: const Text('Absent'),
            ),
          ],
        ],
      ),
    );
  }

  Widget classCard(CoachClassesState s, CoachClass c) {
    final markable = c.students.where((v) => v.markable).length;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(c.planName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('${c.time} · ${c.spaceName} · ${c.businessName}'),
          const SizedBox(height: 4),
          Text(
            '${c.students.length} '
            '${c.students.length == 1 ? 'student' : 'students'} · '
            '${c.count('present')} present · ${c.count('absent')} absent',
          ),
          const Divider(height: 24),
          for (final v in c.students) student(s, v),
          if (markable > 1) ...[
            const SizedBox(height: 8),
            AppButton(
              label: 'Mark $markable present',
              icon: Icons.done_all,
              busy: s.busy,
              onPressed: s.busy ? null : () => cubit.markAll(c),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CoachClassesCubit, CoachClassesState>(
    bloc: cubit,
    builder: (context, s) => AppPage(
      back: true,
      showAppBar: true,
      title: 'My classes',
      compactHeader: true,
      subtitle:
          'Your coaching classes. Mark attendance once a class starts, until 24 hours after it ends; the owner corrects marks from the admission.',
      maxWidth: 900,
      actions: [
        IconButton(
          tooltip: 'Refresh classes',
          onPressed: s.loading || s.busy ? null : cubit.load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      children: [
        dateBar(s),
        const SizedBox(height: 12),
        if (s.loading) const AppLoadingState(),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.load),
        if (!s.loading && s.error == null && s.classes.isEmpty)
          const AppEmptyState(
            title: 'No classes on this day',
            message:
                'Classes appear here once students book the coaching plans you teach.',
          ),
        for (final c in s.classes) ...[
          classCard(s, c),
          const SizedBox(height: 12),
        ],
      ],
    ),
  );
}
