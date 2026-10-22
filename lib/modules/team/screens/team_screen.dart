import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../cubit/team_cubit.dart';
import '../widgets/team_desktop_widgets.dart';

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

  Future<void> invite() async {
    await context.push('/team/invite');
    cubit.load();
  }

  Future<void> edit(Map<String, dynamic> m) async {
    await context.push('/team/edit', extra: m);
    cubit.load();
  }

  Future<void> remove(Map<String, dynamic> m) async {
    if (await confirmAction(
      context,
      'Remove staff access?',
      'This person will lose organization access immediately. Coaching plans they teach become Unassigned.',
    )) {
      await cubit.revoke(m['id']);
    }
  }

  static String invitationStatus(Map<String, dynamic> i) {
    final expired = DateTime.parse(i['expires_at']).isBefore(DateTime.now());
    return i['revoked_at'] != null
        ? 'Cancelled'
        : expired
        ? 'Expired'
        : 'Pending';
  }

  Widget memberTile(
    BuildContext context,
    TeamState s,
    Map<String, dynamic> member,
  ) {
    final colors = Theme.of(context).colorScheme;
    final active = member['active'] == true;
    final owner = member['role'] == 'owner';
    return TeamPersonTile(
      name: member['display_name'],
      email: member['email'],
      muted: !active,
      onTap: active && !s.busy ? () => edit(member) : null,
      chips: [
        TeamChip(
          roleLabel(member['role']),
          icon: owner ? Icons.verified_outlined : null,
        ),
        if ((member['permissions'] as List? ?? []).contains('coach'))
          const TeamChip('Coach', icon: Icons.sports_outlined),
        TeamChip(
          active ? 'Active' : 'Access removed',
          color: active ? colors.tertiary : colors.onSurfaceVariant,
        ),
      ],
      trailing: !owner && active
          ? PopupMenuButton<String>(
              tooltip: 'Staff actions for ${member['display_name']}',
              enabled: !s.busy,
              onSelected: (action) {
                if (action == 'edit') edit(member);
                if (action == 'remove') remove(member);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit staff')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove access',
                    style: TextStyle(color: colors.error),
                  ),
                ),
              ],
            )
          : null,
    );
  }

  Widget invitationTile(
    BuildContext context,
    TeamState s,
    Map<String, dynamic> invitation,
  ) {
    final colors = Theme.of(context).colorScheme;
    final status = invitationStatus(invitation);
    return TeamPersonTile(
      name: invitation['display_name'],
      email: invitation['email'],
      muted: status != 'Pending',
      note: status == 'Pending' ? null : 'Send a new invitation to give access',
      chips: [
        if (invitation['role'] is String)
          TeamChip(roleLabel(invitation['role'])),
        if ((invitation['permissions'] as List? ?? []).contains('coach'))
          const TeamChip('Coach', icon: Icons.sports_outlined),
        TeamChip(
          status,
          icon: Icons.mail_outline,
          color: status == 'Pending' ? colors.primary : colors.onSurfaceVariant,
        ),
      ],
      trailing: status == 'Pending'
          ? IconButton(
              tooltip: 'Cancel invitation',
              onPressed: s.busy
                  ? null
                  : () => cubit.revoke(invitation['id'], invitation: true),
              icon: const Icon(Icons.close),
            )
          : null,
    );
  }

  Widget page(BuildContext context, TeamState s) {
    final wide = isDesktopWidth(context);
    final active = s.members.where((m) => m['active'] == true).toList();
    final invitations = s.invitations
        .where((i) => i['accepted_at'] == null)
        .toList();
    final pending = invitations.where((i) => invitationStatus(i) == 'Pending');
    final empty = s.members.isEmpty && s.invitations.isEmpty;
    return AppPage(
      back: true,
      eyebrow: 'TEAM & ACCESS',
      title: 'Your people.',
      subtitle:
          'Assign businesses and resources. Keep each person’s access clear.',
      maxWidth: 1200,
      actions: wide
          ? [
              FilledButton.icon(
                icon: const Icon(Icons.person_add_alt, size: 18),
                label: const Text('Invite staff'),
                onPressed: s.busy ? null : invite,
              ),
            ]
          : const [],
      children: [
        if (!wide) ...[
          AppButton(
            label: 'Invite staff',
            icon: Icons.person_add_alt,
            onPressed: s.busy ? null : invite,
          ),
          const SizedBox(height: 24),
        ],
        if (s.loading)
          AppLoadingState(
            initial: empty,
            label: empty ? 'Loading your team…' : null,
          ),
        if (s.error != null)
          AppErrorWidget(message: s.error!, onRetry: cubit.load),
        if (wide && !empty) ...[
          AppStatRow(
            children: [
              AppStatTile(
                icon: Icons.groups_outlined,
                label: 'Active people',
                value: '${active.length}',
                highlight: true,
              ),
              AppStatTile(
                icon: Icons.manage_accounts_outlined,
                label: 'Managers',
                value: '${active.where((m) => m['role'] == 'manager').length}',
              ),
              AppStatTile(
                icon: Icons.badge_outlined,
                label: 'Staff',
                value: '${active.where((m) => m['role'] == 'staff').length}',
              ),
              AppStatTile(
                icon: Icons.mark_email_unread_outlined,
                label: 'Pending invitations',
                value: '${pending.length}',
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
        if (s.members.isNotEmpty)
          AppPanel(
            title: 'Members',
            subtitle:
                '${s.members.length} ${s.members.length == 1 ? 'person' : 'people'} · ${active.length} active',
            child: AppGrid(
              minTileWidth: 340,
              maxColumns: wide ? 3 : 1,
              gap: 12,
              children: [
                for (final member in s.members) memberTile(context, s, member),
              ],
            ),
          ),
        if (invitations.isNotEmpty)
          AppPanel(
            title: 'Invitations',
            subtitle: 'Invitations that have not been accepted yet',
            child: AppGrid(
              minTileWidth: 340,
              maxColumns: wide ? 3 : 1,
              gap: 12,
              children: [
                for (final invitation in invitations)
                  invitationTile(context, s, invitation),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocBuilder<TeamCubit, TeamState>(bloc: cubit, builder: page);
}
