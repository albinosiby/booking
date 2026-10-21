import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/team_coaches_cubit.dart';
import '../models/team_coaches_model.dart';
import '../../pool/models/pool_configuration.dart';
import '../widgets/team_desktop_widgets.dart';

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
    if (isDesktopWidth(context)) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _CoachEditor(cubit: cubit),
            ),
          ),
        ),
      );
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        isDismissible: false,
        enableDrag: false,
        builder: (_) => _CoachEditor(cubit: cubit),
      );
    }
    cubit.closeEditor();
  }

  /// Coaches are staff: inviting one opens staff access with Coach on.
  Future<void> addCoach() async {
    await context.push('/team/invite', extra: 'coach');
    cubit.load();
  }

  Future<void> editStaff(Map<String, dynamic> member) async {
    await context.push('/team/edit', extra: member);
    cubit.load();
  }

  Future<void> ownerCoach(TeamCoachesModel s, bool coach) async {
    final plans = cubit.ownerId == null
        ? const <CoachPlan>[]
        : s.plansOf(cubit.ownerId!);
    if (!coach &&
        plans.isNotEmpty &&
        !await confirmAction(
          context,
          'Stop coaching?',
          'These plans will become Unassigned: ${plans.map((p) => p.name).join(', ')}.',
        )) {
      return;
    }
    await cubit.setOwnerCoach(coach);
  }

  Widget ownerCard(TeamCoachesModel s) => AppCard(
    padding: const EdgeInsets.all(6),
    child: SwitchListTile(
      title: const Text('I also coach'),
      subtitle: const Text(
        'Assign yourself coaching plans and mark attendance in My classes.',
      ),
      value: s.ownerCoach,
      onChanged: s.busy || s.loading ? null : (v) => ownerCoach(s, v),
    ),
  );

  Widget coachCard(
    BuildContext context,
    TeamCoachesModel s,
    CoachBusiness business,
    PoolCoach coach,
  ) {
    final member = s.member(coach.id);
    final spaces = business.spaces.where((p) => coach.poolIds.contains(p.id));
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const CircleAvatar(child: Icon(Icons.sports_outlined)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coach.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(coach.owner ? 'Owner' : 'Staff'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (spaces.length == business.spaces.length)
            Text('All ${business.spacesLabel}')
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final space in spaces) Chip(label: Text(space.name)),
              ],
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
          if (!coach.owner && member != null)
            TextButton.icon(
              onPressed: s.busy ? null : () => editStaff(member),
              icon: Icon(
                business.court ? Icons.sports_tennis : Icons.pool_outlined,
              ),
              label: Text('Change ${business.spacesLabel} in staff access'),
            ),
        ],
      ),
    );
  }

  List<Widget> businessCoaches(
    BuildContext context,
    TeamCoachesModel s,
    CoachBusiness business,
  ) => [
    if (business.coaches.isEmpty)
      const AppCard(
        child: Text(
          'No coaches here yet. Turn on Coach in a staff member’s access for this business, or switch on “I also coach”.',
        ),
      )
    else
      AppGrid(
        minTileWidth: 320,
        maxColumns: 2,
        children: [
          for (final coach in business.coaches)
            coachCard(context, s, business, coach),
        ],
      ),
    if (business.plans.isEmpty)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          'Add a coaching plan in ${business.court ? 'court' : 'pool'} settings to assign a coach.',
        ),
      ),
  ];

  List<Widget> status(TeamCoachesModel s, {bool card = true}) => [
    if (s.loading)
      AppLoadingState(
        initial: s.businesses.isEmpty,
        label: s.businesses.isEmpty ? 'Loading coaches…' : null,
      ),
    if (s.error != null && !s.editing)
      AppErrorWidget(message: s.error!, onRetry: cubit.load),
    if (!s.loading && s.businesses.isEmpty)
      AppEmptyState(
        showCard: card,
        title: 'Set up a pool or court first',
        message:
            'Save a pool or court configuration, then assign coaches here.',
      ),
  ];

  List<Widget> actions(TeamCoachesModel s, {bool wide = false}) => [
    IconButton(
      tooltip: 'Refresh coaches',
      onPressed: s.loading || s.busy ? null : cubit.load,
      icon: const Icon(Icons.refresh),
    ),
    if (cubit.authorized)
      if (wide) ...[
        const SizedBox(width: 6),
        FilledButton.icon(
          onPressed: s.busy ? null : addCoach,
          icon: const Icon(Icons.person_add_alt_outlined, size: 18),
          label: const Text('Invite coach'),
        ),
      ] else
        IconButton(
          tooltip: 'Invite coach',
          onPressed: s.busy ? null : addCoach,
          icon: const Icon(Icons.person_add_alt_outlined),
        ),
  ];

  static const subtitle =
      'Coaches are team members with Coach turned on in their staff access. Assign them coaching plans here.';

  // Wide windows: coach cards per business beside a coaching-plan summary.
  Widget desktop(BuildContext context, TeamCoachesModel s) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    return AppPage(
      back: true,
      showAppBar: true,
      title: 'Coaches',
      eyebrow: 'TEAM & ACCESS',
      subtitle: subtitle,
      maxWidth: 1200,
      actions: actions(s, wide: true),
      children: [
        if (!cubit.authorized)
          const AppErrorWidget(message: 'Only the owner can manage coaches.')
        else ...[
          ...status(s),
          if (s.businesses.isNotEmpty)
            AppTwoPane(
              secondaryWidth: 340,
              primary: [
                ownerCard(s),
                for (final business in s.businesses)
                  AppPanel(
                    title: business.name,
                    subtitle:
                        '${business.coaches.length} '
                        '${business.coaches.length == 1 ? 'coach' : 'coaches'} · '
                        '${business.spaces.length} ${business.spacesLabel}',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: businessCoaches(context, s, business),
                    ),
                  ),
              ],
              secondary: [
                AppPanel(
                  title: 'Coaching plans',
                  subtitle: 'Who coaches each plan',
                  child: AppListCard(
                    children: [
                      for (final business in s.businesses) ...[
                        if (s.businesses.length > 1)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                            child: Text(
                              business.name,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: colors.primary,
                              ),
                            ),
                          ),
                        if (business.plans.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(18),
                            child: Text('No coaching plans yet.'),
                          ),
                        for (final plan in business.plans)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.assignment_ind_outlined,
                                  size: 20,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    plan.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 150,
                                  ),
                                  child: TeamChip(
                                    business.coaches
                                            .where((c) => c.id == plan.coachId)
                                            .firstOrNull
                                            ?.name ??
                                        'Unassigned',
                                    color: plan.coachId == null
                                        ? colors.onSurfaceVariant
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<TeamCoachesCubit, TeamCoachesModel>(
        bloc: cubit,
        builder: (context, s) => isDesktopWidth(context)
            ? desktop(context, s)
            : AppPage(
                back: true,
                showAppBar: true,
                title: 'Coaches',
                compactHeader: true,
                subtitle: subtitle,
                actions: actions(s),
                children: [
                  if (!cubit.authorized)
                    const AppErrorWidget(
                      message: 'Only the owner can manage coaches.',
                    )
                  else ...[
                    ...status(s, card: false),
                    if (s.businesses.isNotEmpty) ...[
                      ownerCard(s),
                      const SizedBox(height: 20),
                    ],
                    for (final business in s.businesses) ...[
                      Text(
                        business.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      ...businessCoaches(context, s, business),
                      const SizedBox(height: 20),
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
