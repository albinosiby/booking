import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../cubit/team_cubit.dart';
import '../../../config/routes/routes.dart';

class TeamScreen extends StatefulWidget {
  const TeamScreen({super.key});
  @override
  State<TeamScreen> createState() => _TeamScreenState();
}

class _TeamScreenState extends State<TeamScreen> {
  late final cubit = getIt<TeamCubit>()..load();
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<TeamCubit, TeamState>(
    bloc: cubit,
    builder: (context, s) => AppPage(
      back: true,
      eyebrow: 'TEAM & ACCESS',
      title: 'Your people.',
      subtitle:
          'Assign businesses and resources. Keep each person’s access clear.',
      children: [
        AppButton(
          label: 'Invite staff',
          icon: Icons.person_add_alt,
          onPressed: () async {
            await context.push('/team/invite');
            cubit.load();
          },
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.sports_outlined),
          label: const Text('Coaches'),
          onPressed: () => context.push(Routes.teamCoaches),
        ),
        const SizedBox(height: 24),
        if (s.loading)
          AppLoadingState(
            initial: s.members.isEmpty && s.invitations.isEmpty,
            label: s.members.isEmpty && s.invitations.isEmpty
                ? 'Loading your team…'
                : null,
          ),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.load),
        ...s.members.map(
          (m) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m['display_name'],
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(m['email']),
                  const SizedBox(height: 8),
                  Text(
                    '${m['role']} · ${m['active'] ? 'Active' : 'Access removed'}',
                    style: const TextStyle(color: AppColors.lime, fontSize: 12),
                  ),
                  if (m['role'] != 'owner' && m['active'])
                    Wrap(
                      spacing: 10,
                      children: [
                        TextButton(
                          onPressed: s.busy
                              ? null
                              : () async {
                                  await context.push('/team/edit', extra: m);
                                  cubit.load();
                                },
                          child: const Text('Edit assignments'),
                        ),
                        TextButton(
                          onPressed: s.busy
                              ? null
                              : () async {
                                  if (await confirmAction(
                                    context,
                                    'Remove staff access?',
                                    'This person will lose organization access immediately.',
                                  )) {
                                    await cubit.revoke(m['id']);
                                  }
                                },
                          child: const Text('Remove access'),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ),
        if (s.invitations.any((i) => i['accepted_at'] == null)) ...[
          const SizedBox(height: 20),
          Text('Invitations', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          ...s.invitations.where((i) => i['accepted_at'] == null).map((i) {
            final expired = DateTime.parse(
              i['expires_at'],
            ).isBefore(DateTime.now());
            final status = i['revoked_at'] != null
                ? 'Cancelled'
                : expired
                ? 'Expired'
                : 'Pending';
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      i['display_name'],
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(i['email']),
                    Text(status, style: const TextStyle(fontSize: 12)),
                    if (status == 'Pending')
                      TextButton(
                        onPressed: s.busy
                            ? null
                            : () => cubit.revoke(i['id'], invitation: true),
                        child: const Text('Cancel invitation'),
                      ),
                  ],
                ),
              ),
            );
          }),
        ],
      ],
    ),
  );
}
