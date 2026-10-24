import '../models/team_deletion_target.dart';
import '../models/team_removal_target.dart';
import '../widgets/team_removal_dialog.dart';
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
    final target = TeamRemovalTarget.fromMember(m);
    if (!target.removable || cubit.state.busy) return;
    if (await confirmTeamRemoval(context, target) && mounted) {
      await cubit.revoke(target.id);
    }
  }

  Future<void> deletePermanently(TeamDeletionTarget target) async {
    if (!target.eligible || cubit.state.busy) return;
    if (await confirmTeamDeletion(context, target) && mounted) {
      await cubit.deletePermanently(target);
    }
  }

  Widget deleteButton(TeamState state, TeamDeletionTarget target) =>
      TextButton.icon(
        onPressed: state.busy ? null : () => deletePermanently(target),
        style: TextButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
        ),
        icon: const Icon(Icons.delete_forever_outlined, size: 18),
        label: const Text('Delete permanently'),
      );

  Future<void> cancelInvitation(Map<String, dynamic> invitation) async {
    if (await confirmAction(
          context,
          'Cancel pending access?',
          '${invitation['display_name']} will no longer be able to join using this team entry. You can add them again later.',
        ) &&
        mounted) {
      await cubit.revoke(invitation['id'], invitation: true);
    }
  }

  static String invitationStatus(Map<String, dynamic> i) {
    if (i['revoked_at'] != null) return 'Cancelled';
    if (i['join_mode'] == 'email_login') return 'Awaiting sign-in';
    final expired =
        DateTime.tryParse(
          i['expires_at']?.toString() ?? '',
        )?.isBefore(DateTime.now()) ??
        true;
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
          ? IconButton(
              tooltip: 'Edit staff for ${member['display_name']}',
              onPressed: s.busy ? null : () => edit(member),
              icon: const Icon(Icons.edit_outlined),
            )
          : null,
      actions: [
        if (TeamDeletionTarget.member(member).eligible)
          deleteButton(s, TeamDeletionTarget.member(member)),
        if (!owner && active)
          TextButton.icon(
            onPressed: s.busy ? null : () => remove(member),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            icon: const Icon(Icons.person_remove_outlined, size: 18),
            label: Text(TeamRemovalTarget.fromMember(member).label),
          ),
      ],
    );
  }

  Widget invitationTile(
    BuildContext context,
    TeamState s,
    Map<String, dynamic> invitation,
  ) {
    final colors = Theme.of(context).colorScheme;
    final status = invitationStatus(invitation);
    final emailAccess = invitation['join_mode'] == 'email_login';
    final pending = status == 'Pending' || status == 'Awaiting sign-in';
    final emailStatus = invitation['email_status'];
    return TeamPersonTile(
      name: invitation['display_name'],
      email: invitation['email'],
      muted: !pending,
      onTap: emailAccess && pending && !s.busy
          ? () => edit({...invitation, 'pending_access': true})
          : null,
      note: pending
          ? emailAccess
                ? 'Sign in with this email to open the dashboard'
                : 'Existing invitation link'
          : 'Add this person again to give access',
      chips: [
        if (invitation['role'] is String)
          TeamChip(roleLabel(invitation['role'])),
        if ((invitation['permissions'] as List? ?? []).contains('coach'))
          const TeamChip('Coach', icon: Icons.sports_outlined),
        TeamChip(
          status,
          icon: Icons.mail_outline,
          color: pending ? colors.primary : colors.onSurfaceVariant,
        ),
        if (emailAccess && pending)
          TeamChip(
            emailStatus == 'sent'
                ? 'Email sent'
                : emailStatus == 'sending'
                ? 'Sending email'
                : emailStatus == 'failed'
                ? 'Email not sent'
                : 'Email pending',
            color: emailStatus == 'failed'
                ? colors.error
                : colors.onSurfaceVariant,
          ),
      ],
      trailing: pending && emailAccess
          ? PopupMenuButton<String>(
              tooltip:
                  'Pending access actions for ${invitation['display_name']}',
              enabled: !s.busy,
              onSelected: (action) {
                if (action == 'edit') {
                  edit({...invitation, 'pending_access': true});
                }
                if (action == 'resend') cubit.resendEmail(invitation['id']);
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit access')),
                const PopupMenuItem(
                  value: 'resend',
                  child: Text('Resend access email'),
                ),
              ],
            )
          : null,
      actions: [
        if (TeamDeletionTarget.invitation(invitation).eligible)
          deleteButton(s, TeamDeletionTarget.invitation(invitation)),
        if (pending)
          TextButton.icon(
            onPressed: s.busy ? null : () => cancelInvitation(invitation),
            style: TextButton.styleFrom(foregroundColor: colors.error),
            icon: const Icon(Icons.cancel_outlined, size: 18),
            label: Text(emailAccess ? 'Cancel access' : 'Cancel invitation'),
          ),
      ],
    );
  }

  Widget page(BuildContext context, TeamState s) {
    final wide = isDesktopWidth(context);
    final active = s.members.where((m) => m['active'] == true).toList();
    final invitations = s.invitations
        .where((i) => i['accepted_at'] == null)
        .toList();
    final pending = invitations.where(
      (i) => {'Pending', 'Awaiting sign-in'}.contains(invitationStatus(i)),
    );
    final empty = s.members.isEmpty && s.invitations.isEmpty;
    return AppPage(
      back: true,
      eyebrow: 'TEAM & ACCESS',
      title: 'Your people.',
      subtitle:
          'Assign businesses and resources. Keep each person’s access clear.',
      maxWidth: 1200,
      actions: [
        IconButton(
          tooltip: 'Refresh team',
          onPressed: s.busy || s.loading ? null : cubit.load,
          icon: const Icon(Icons.refresh),
        ),
        if (wide)
          FilledButton.icon(
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Add team member'),
            onPressed: s.busy ? null : invite,
          ),
      ],
      children: [
        if (!wide) ...[
          AppButton(
            label: 'Add team member',
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
        if (s.notice != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: Semantics(liveRegion: true, child: Text(s.notice!)),
          ),
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
                label: 'Awaiting sign-in',
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
            title: 'Pending access',
            subtitle:
                'People who have not signed in yet, and invitation history',
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
