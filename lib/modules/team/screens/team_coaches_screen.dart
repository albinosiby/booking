import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/team_coaches_cubit.dart';
import '../models/team_coaches_model.dart';

class TeamCoachesScreen extends StatefulWidget {
  const TeamCoachesScreen({super.key});
  @override
  State<TeamCoachesScreen> createState() => _TeamCoachesScreenState();
}

class _TeamCoachesScreenState extends State<TeamCoachesScreen> {
  late final cubit = getIt<TeamCoachesCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<void> editor() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _CoachEditor(cubit: cubit),
    );
    cubit.closeEditor();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<TeamCoachesCubit, TeamCoachesModel>(
    bloc: cubit,
    builder: (context, s) => AppPage(
      back: true,
      showAppBar: true,
      title: 'Coaches',
      compactHeader: true,
      subtitle:
          'Add coach contacts and assign them to coaching plans. Staff access is managed separately.',
      actions: [
        IconButton(
          tooltip: 'Refresh coaches',
          onPressed: s.loading || s.busy ? null : cubit.load,
          icon: const Icon(Icons.refresh),
        ),
        if (cubit.authorized)
          IconButton(
            tooltip: 'Add coach',
            onPressed: s.businesses.isEmpty || s.busy || s.loading
                ? null
                : () {
                    cubit.beginAdd();
                    editor();
                  },
            icon: const Icon(Icons.person_add_alt_outlined),
          ),
      ],
      children: [
        if (!cubit.authorized)
          const AppErrorWidget(message: 'Only the owner can manage coaches.')
        else ...[
          if (s.loading)
            AppLoadingState(
              initial: s.businesses.isEmpty,
              label: s.businesses.isEmpty ? 'Loading coaches…' : null,
            ),
          if (s.error != null && s.editor == null)
            AppErrorWidget(message: s.error!, onRetry: cubit.load),
          if (!s.loading && s.businesses.isEmpty)
            const AppEmptyState(
              showCard: false,
              title: 'Set up a pool or court first',
              message:
                  'Save a pool or court configuration, then add coaches here.',
            ),
          for (final business in s.businesses) ...[
            Text(business.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            if (business.coaches.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'No coaches added. Coaching plans remain Unassigned.',
                ),
              ),
            for (final coach in business.coaches)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const CircleAvatar(
                            child: Icon(Icons.sports_outlined),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  coach.name,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 4),
                                SelectableText(coach.phone),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (coach.poolIds.isEmpty)
                        Text('No ${business.spacesLabel} assigned')
                      else
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            for (final space in business.spaces.where(
                              (p) => coach.poolIds.contains(p.id),
                            ))
                              Chip(label: Text(space.name)),
                          ],
                        ),
                      OutlinedButton.icon(
                        onPressed: s.busy || business.spaces.isEmpty
                            ? null
                            : () {
                                cubit.beginSpaces(business.id, coach.id);
                                editor();
                              },
                        icon: Icon(
                          business.court
                              ? Icons.sports_tennis
                              : Icons.pool_outlined,
                        ),
                        label: Text('Assign ${business.spacesLabel}'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        business.plans.any((p) => p.coachId == coach.id)
                            ? business.plans
                                  .where((p) => p.coachId == coach.id)
                                  .map((p) => p.name)
                                  .join(' · ')
                            : 'No coaching plans assigned',
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: s.busy || business.plans.isEmpty
                            ? null
                            : () {
                                cubit.beginAssign(business.id, coach.id);
                                editor();
                              },
                        icon: const Icon(Icons.assignment_ind_outlined),
                        label: const Text('Assign coaching plans'),
                      ),
                    ],
                  ),
                ),
              ),
            if (business.plans.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: Text(
                  'Add a coaching plan in ${business.court ? 'court' : 'pool'} settings to assign a coach.',
                ),
              ),
          ],
        ],
      ],
    ),
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
      final adding = s.editor == CoachEditor.add;
      final spaces = s.editor == CoachEditor.spaces;
      final business = s.selectedBusiness;
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
                        adding
                            ? 'Add coach'
                            : spaces
                            ? 'Assign ${business?.spacesLabel ?? 'pool spaces'}'
                            : 'Assign coaching plans',
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
                if (adding) ...[
                  if (s.businesses.length > 1) ...[
                    AppPicker(
                      label: 'Business',
                      value: s.businessId,
                      enabled: !s.busy,
                      items: s.businesses
                          .map((b) => PickerItem(b.id, b.name))
                          .toList(),
                      onChanged: cubit.business,
                    ),
                    const SizedBox(height: 16),
                  ] else
                    Text(business?.name ?? ''),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: s.name,
                    enabled: !s.busy,
                    decoration: const InputDecoration(labelText: 'Coach name'),
                    textCapitalization: TextCapitalization.words,
                    maxLength: 100,
                    onChanged: cubit.name,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: s.phone,
                    enabled: !s.busy,
                    decoration: const InputDecoration(
                      labelText: 'Phone number',
                    ),
                    keyboardType: TextInputType.phone,
                    maxLength: 30,
                    onChanged: cubit.phone,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This adds a coach contact without a login. Assign ${business?.spacesLabel ?? 'pool spaces'}, then coaching plans after saving.',
                  ),
                ] else ...[
                  Text(
                    business?.coaches
                            .where((c) => c.id == s.coachId)
                            .firstOrNull
                            ?.name ??
                        'Coach',
                  ),
                  const SizedBox(height: 8),
                  if (spaces) ...[
                    Text(
                      'Choose one or more ${business?.spacesLabel ?? 'pool spaces'}. Clear all to leave this coach Unassigned.',
                    ),
                    for (final space in business?.spaces ?? <CoachSpace>[])
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(space.name),
                        value: s.spaceIds.contains(space.id),
                        onChanged: s.busy
                            ? null
                            : (value) =>
                                  cubit.toggleSpace(space.id, value ?? false),
                      ),
                    if (s.affectedPlans.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'These coaching-plan assignments will also be removed: ${s.affectedPlans.map((p) => p.name).join(', ')}',
                      ),
                    ],
                  ] else ...[
                    Text(
                      'Choose plans for this coach. Only plans covered by their assigned ${business?.spacesLabel ?? 'pool spaces'} are shown. Selecting a plan assigned to another coach replaces that assignment.',
                    ),
                    const SizedBox(height: 12),
                    if (s.eligiblePlans.isEmpty)
                      Text(
                        'Assign the required ${business?.spacesLabel ?? 'pool spaces'} first to make coaching plans available.',
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
                              : 'Not covered by this coach’s ${business?.spacesLabel ?? 'pool spaces'}. Untick to save, or assign the missing ${business?.spacesLabel ?? 'pool spaces'} first.',
                        ),
                        onChanged: s.busy
                            ? null
                            : (value) => cubit.toggle(plan.id, value ?? false),
                      ),
                  ],
                ],
                if (s.error != null) AppErrorWidget(message: s.error!),
                const SizedBox(height: 20),
                AppButton(
                  label: adding ? 'Save coach' : 'Save assignments',
                  busy: s.busy,
                  onPressed: s.busy
                      ? null
                      : () async {
                          var confirmed = false;
                          if (!adding && !spaces) {
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
                            if (!context.mounted) return;
                          }
                          if (spaces && cubit.state.affectedPlans.isNotEmpty) {
                            confirmed = await confirmAction(
                              context,
                              'Remove affected plan assignments?',
                              'The following plans will become Unassigned: ${cubit.state.affectedPlans.map((p) => p.name).join(', ')}. The coach’s ${business?.court == true ? 'court' : 'pool-space'} assignments will be saved at the same time.',
                            );
                            if (!confirmed || !context.mounted) return;
                          }
                          if (await cubit.saveEditor(
                                removeAffectedPlans: confirmed,
                              ) &&
                              context.mounted) {
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
