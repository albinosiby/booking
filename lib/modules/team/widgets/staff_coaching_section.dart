import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/team_coaches_cubit.dart';
import '../models/team_coaches_model.dart';

/// Coaching responsibilities of a single team member, inside staff management.
class StaffCoachingSection extends StatefulWidget {
  const StaffCoachingSection({
    super.key,
    required this.memberId,
    this.owner = false,
    this.enabled = true,
  });
  final String memberId;
  final bool owner, enabled;
  @override
  State<StaffCoachingSection> createState() => _StaffCoachingSectionState();
}

class _StaffCoachingSectionState extends State<StaffCoachingSection> {
  late final cubit = getIt<TeamCoachesCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> edit(String businessId) async {
    cubit.beginAssign(businessId, widget.memberId);
    if (!cubit.state.editing) return;
    await showAdaptiveSheet<void>(
      context: context,
      isDismissible: false,
      showClose: false,
      builder: (_) => _CoachEditor(cubit: cubit),
    );
    cubit.closeEditor();
  }

  Future<void> setOwnerCoach(bool value) async {
    final plans = cubit.state.plansOf(widget.memberId);
    if (!value &&
        plans.isNotEmpty &&
        !await confirmAction(
          context,
          'Stop coaching?',
          'These plans become Unassigned: ${plans.map((p) => p.name).join(', ')}.',
        )) {
      return;
    }
    await cubit.setOwnerCoach(value);
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<TeamCoachesCubit, TeamCoachesModel>(
    bloc: cubit,
    builder: (context, s) {
      final businesses = s.businesses
          .where((b) => b.coaches.any((c) => c.id == widget.memberId))
          .toList();
      final enabled =
          widget.enabled && cubit.authorized && !s.busy && !s.loading;
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Coaching plans',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh coaching plans',
                  onPressed: enabled ? cubit.load : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            if (widget.owner) ...[
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Also a coach'),
                subtitle: const Text(
                  'Your owner permissions include attendance. Coach status makes you eligible to teach plans.',
                ),
                value: s.ownerCoach,
                onChanged: enabled ? setOwnerCoach : null,
              ),
            ],
            if (!widget.enabled)
              const Text(
                'Save staff access before changing coaching plans. Plans use the saved business and resource assignments.',
              ),
            if (s.loading) const AppLoadingState(initial: false),
            if (s.error != null && !s.editing)
              AppErrorWidget(message: s.error!, onRetry: cubit.load),
            if (!s.loading && businesses.isEmpty)
              Text(
                widget.owner && !s.ownerCoach
                    ? 'Enable Also a coach to assign yourself coaching plans.'
                    : 'No eligible coaching businesses. Save staff access and configure a pool or court with coaching plans.',
              ),
            for (final b in businesses) ...[
              const SizedBox(height: 12),
              Text(b.name, style: Theme.of(context).textTheme.titleSmall),
              Text(
                b.plans
                        .where((p) => p.coachId == widget.memberId)
                        .map((p) => p.name)
                        .join(' · ')
                        .isEmpty
                    ? 'No coaching plans assigned'
                    : b.plans
                          .where((p) => p.coachId == widget.memberId)
                          .map((p) => p.name)
                          .join(' · '),
              ),
              OutlinedButton.icon(
                onPressed: enabled && b.plans.isNotEmpty
                    ? () => edit(b.id)
                    : null,
                icon: const Icon(Icons.assignment_ind_outlined),
                label: const Text('Assign coaching plans'),
              ),
            ],
          ],
        ),
      );
    },
  );
}

class _CoachEditor extends StatelessWidget {
  const _CoachEditor({required this.cubit});
  final TeamCoachesCubit cubit;
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<TeamCoachesCubit, TeamCoachesModel>(
    bloc: cubit,
    builder: (context, s) {
      final business = s.selectedBusiness;
      final spaces = business?.spacesLabel ?? 'pool spaces';
      return PopScope(
        canPop: !s.busy,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              24,
              8,
              24,
              MediaQuery.viewInsetsOf(context).bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Assign coaching plans',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: s.busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(s.selectedCoach?.name ?? 'Coach'),
                const SizedBox(height: 8),
                Text(
                  'Choose plans for this coach. Only plans covered by the $spaces in their staff access are shown. Selecting a plan assigned to another coach replaces that assignment.',
                ),
                const SizedBox(height: 12),
                if (s.eligiblePlans.isEmpty)
                  Text(
                    'Add the required $spaces to this coach’s staff access to make coaching plans available.',
                  ),
                for (final plan in s.eligiblePlans)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(plan.name),
                    value: s.planIds.contains(plan.id),
                    subtitle: Text(
                      plan.coachId == null
                          ? 'Unassigned'
                          : plan.coachId != s.coachId
                          ? 'Assigned to another coach'
                          : plan.keepsCoach(s.selectedCoach?.poolIds ?? [])
                          ? 'Assigned to this coach'
                          : 'Not covered by this coach’s $spaces. Untick to save, or add the missing $spaces to their staff access first.',
                    ),
                    onChanged: s.busy
                        ? null
                        : (value) => cubit.toggle(plan.id, value ?? false),
                  ),
                if (s.error != null) AppErrorWidget(message: s.error!),
                const SizedBox(height: 20),
                AppButton(
                  label: 'Save assignments',
                  busy: s.busy,
                  onPressed: s.busy
                      ? null
                      : () async {
                          final conflicts = await cubit.assignmentConflicts();
                          if (conflicts == null || !context.mounted) return;
                          if (conflicts.isNotEmpty &&
                              !await confirmAction(
                                context,
                                'Coach has overlapping classes',
                                'After this change the coach would teach overlapping upcoming classes:\n${conflicts.join('\n')}\n\nReschedule those classes or choose another coach. Save anyway?',
                              )) {
                            return;
                          }
                          if (await cubit.saveEditor() && context.mounted) {
                            Navigator.pop(context);
                          }
                        },
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
