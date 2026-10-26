import '../widgets/team_removal_dialog.dart';
import '../widgets/staff_coaching_section.dart';
import '../models/staff_access_draft.dart';
import '../cubit/staff_assignment_cubit.dart';
import '../models/staff_assignment_screen_model.dart';
import '../../../di/injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../models/staff_coaches.dart';

class StaffAssignmentScreen extends StatefulWidget {
  const StaffAssignmentScreen({super.key, this.member});
  final Map<String, dynamic>? member;
  @override
  State<StaffAssignmentScreen> createState() => _StaffAssignmentScreenState();
}

class _StaffAssignmentScreenState extends State<StaffAssignmentScreen> {
  late final cubit = getIt<StaffAssignmentCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.member,
  );
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.member?['display_name']),
      email = TextEditingController(text: widget.member?['email']);
  String get role => cubit.state.role;
  Set<String> get businesses => cubit.state.businesses;
  Set<String> get restricted => cubit.state.restricted;
  Map<String, Set<String>> get resources => cubit.state.resources;
  Set<String> get permissions => cubit.state.permissions;
  bool get isOwnerRole => role == 'owner';
  bool get pendingAccess => widget.member?['pending_access'] == true;
  static const labels = {
    'view_bookings': 'View bookings',
    'manage_bookings': 'Create and edit bookings',
    'collect_payments': 'Record collections',
    'mark_attendance': 'Mark attendance',
    'manage_subscriptions': 'Manage subscriptions',
    'record_expenses': 'Record expenses',
    'view_finance': 'View financial reports',
  };
  @override
  void dispose() {
    name.dispose();
    email.dispose();
    if (widget.member?['role'] != 'owner') cubit.close();
    super.dispose();
  }

  Future<void> remove() async {
    if (!cubit.canRemove || cubit.state.busy) return;
    final target = cubit.removalTarget!;
    if (!await confirmTeamRemoval(context, target) || !mounted) return;
    final removed = await cubit.remove();
    if (!mounted || !removed) return;
    showMessage(context, '${target.name} removed. History has been preserved.');
    Navigator.pop(context, true);
  }

  Future<void> save() async {
    if (cubit.state.busy) return;
    if (!form.currentState!.validate()) return;
    if (!isOwnerRole && businesses.isEmpty) {
      showMessage(context, 'Select at least one business.');
      return;
    }
    if (!isOwnerRole &&
        restricted.any(
          (b) => businesses.contains(b) && (resources[b]?.isEmpty ?? true),
        )) {
      showMessage(
        context,
        'Select at least one resource for restricted businesses.',
      );
      return;
    }
    final data = StaffAccessDraft(
      name: name.text.trim(),
      email: email.text.trim().toLowerCase(),
      role: role,
      permissions: isOwnerRole ? const <String>[] : permissions,
      assignments: (isOwnerRole ? <String>{} : businesses).map(
        (b) => BusinessAssignment(
          b,
          restricted.contains(b) ? resources[b]! : <String>[],
        ),
      ),
    );
    if (widget.member != null && !pendingAccess) {
      final released = releasedPlans(
        cubit.state.data.businesses,
        widget.member!['id'],
        coach: permissions.contains('coach'),
        assignments: {
          for (final a in data.assignments) a.businessId: a.resourceIds,
        },
      );
      if (released.isNotEmpty &&
          !await confirmAction(
            context,
            'Remove coaching plans?',
            'With this access ${name.text.trim()} can no longer coach: ${released.join(', ')}. Those plans become Unassigned.',
          )) {
        return;
      }
      if (!mounted) return;
    }
    final bool ok;
    if (widget.member == null || pendingAccess) {
      final result = await cubit.add(
        data,
        pendingId: pendingAccess ? widget.member!['id'] : null,
      );
      ok = result != null;
      if (mounted && result != null) {
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(
              result.sent
                  ? 'Access email sent'
                  : 'Access saved · email not sent',
            ),
            content: Text(result.message),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } else {
      ok = await cubit.update(widget.member!['id'], data);
    }
    if (!mounted || !ok) return;
    if (mounted) {
      if (widget.member == null) {
        Navigator.pop(context);
      } else {
        showMessage(context, 'Staff access saved.');
      }
    }
  }

  List<Widget> identityFields() => [
    AppTextField(
      label: 'Staff name',
      controller: name,
      validator: Validation.name,
      enabled: !cubit.state.busy,
    ),
    const SizedBox(height: 16),
    AppTextField(
      label: 'Email address',
      controller: email,
      keyboardType: TextInputType.emailAddress,
      validator: Validation.email,
      enabled: widget.member == null && !cubit.state.busy,
    ),
    const SizedBox(height: 16),
    AppPicker(
      label: 'Responsibility',
      enabled: !cubit.state.busy,
      items: const [
        PickerItem('staff', 'Staff'),
        PickerItem('manager', 'Manager'),
        PickerItem('owner', 'Owner'),
      ],
      value: role,
      onChanged: (v) => cubit.selectRole(v),
    ),
    if (!isOwnerRole) ...[
      const SizedBox(height: 12),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Also a coach'),
        subtitle: const Text(
          'Can teach assigned coaching plans. Enable attendance separately under Permissions.',
        ),
        value: permissions.contains('coach'),
        onChanged: cubit.state.busy
            ? null
            : (value) => cubit.selectPermission('coach', value),
      ),
    ],
  ];

  List<Widget> businessCards(StaffAssignmentScreenModel s) => [
    for (final b in s.data.businesses)
      AppCard(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            CheckboxListTile(
              title: Text(b.name),
              subtitle: Text(b.type.label),
              value: businesses.contains(b.id),
              onChanged: s.busy
                  ? null
                  : (v) => cubit.selectBusiness(b.id, v == true),
            ),
            if (businesses.contains(b.id)) ...[
              SwitchListTile(
                title: const Text(
                  'Restrict to selected resources',
                  style: TextStyle(fontSize: 13),
                ),
                value: restricted.contains(b.id),
                onChanged: s.busy
                    ? null
                    : (v) => cubit.restrictBusiness(b.id, v),
              ),
              if (restricted.contains(b.id))
                ...b.resources.map(
                  (r) => CheckboxListTile(
                    title: Text(r.name),
                    value: resources[b.id]?.contains(r.id) ?? false,
                    onChanged: s.busy
                        ? null
                        : (v) => cubit.selectResource(b.id, r.id, v == true),
                  ),
                ),
            ],
          ],
        ),
      ),
  ];

  Widget permissionsCard() => AppCard(
    padding: const EdgeInsets.all(6),
    child: Column(
      children: labels.entries
          .map(
            (e) => SwitchListTile(
              title: Text(e.value, style: const TextStyle(fontSize: 13)),
              value: permissions.contains(e.key),
              onChanged: cubit.state.busy
                  ? null
                  : (v) => cubit.selectPermission(e.key, v),
            ),
          )
          .toList(),
    ),
  );

  Widget coaching(StaffAssignmentScreenModel s) =>
      widget.member == null || pendingAccess
      ? const AppCard(
          child: Text(
            'After this team member signs in, open their staff details to assign coaching plans.',
          ),
        )
      : StaffCoachingSection(
          key: ValueKey('${widget.member!['id']}/${s.accessRevision}'),
          memberId: widget.member!['id'],
          enabled: !cubit.coachingAccessChanged && !s.busy,
        );

  List<Widget> submit(StaffAssignmentScreenModel s) => [
    if (s.error != null) ...[
      AppErrorWidget(message: s.error!),
      const SizedBox(height: 16),
    ],
    AppButton(
      label: widget.member == null ? 'Add team member' : 'Save staff access',
      icon: Icons.check,
      busy: s.busy && !s.removing,
      onPressed: s.data.isOwner && !s.busy && !s.removed ? save : null,
    ),
  ];

  List<Widget> removal(StaffAssignmentScreenModel s) => [
    if (cubit.canRemove) ...[
      const SizedBox(height: 24),
      if (s.removalError != null) ...[
        AppErrorWidget(message: s.removalError!),
        const SizedBox(height: 12),
      ],
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: s.busy ? null : remove,
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          icon: s.removing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.person_remove_outlined),
          label: Text(cubit.removalTarget!.label),
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'Removes organization access. Bookings, payments and attendance history are kept.',
      ),
    ],
  ];

  // Wide windows: person and businesses on the left, permissions and the
  // submit action in a side column.
  Widget desktop(BuildContext c, StaffAssignmentScreenModel s) => AppPage(
    back: true,
    eyebrow: 'TEAM & ACCESS',
    title: widget.member == null
        ? 'The right people. The right access.'
        : 'Edit staff access.',
    subtitle:
        'Assign staff to one business or several, or make them an owner with full access.',
    maxWidth: 1200,
    children: [
      Form(
        key: form,
        child: AppTwoPane(
          secondaryWidth: 400,
          primary: [
            AppPanel(
              title: 'Person',
              subtitle: widget.member == null
                  ? 'They receive an access email with app and web login links.'
                  : 'The email address cannot be changed.',
              child: AppCard(
                padding: const EdgeInsets.all(22),
                child: Column(children: identityFields()),
              ),
            ),
            if (!isOwnerRole)
              AppPanel(
                title: 'Assign businesses',
                subtitle:
                    'Optionally restrict a business to selected resources.',
                child: s.data.businesses.isEmpty
                    ? const AppEmptyState(
                        title: 'No businesses yet',
                        message: 'Add a business before assigning staff.',
                      )
                    : AppGrid(
                        minTileWidth: 300,
                        maxColumns: 2,
                        children: businessCards(s),
                      ),
              ),
          ],
          secondary: [
            if (isOwnerRole)
              const AppCard(
                child: Text(
                  'Owners have full access to every business and can add or remove other owners.',
                ),
              )
            else
              AppPanel(
                title: 'Permissions',
                subtitle: 'What this person can do in assigned businesses.',
                child: permissionsCard(),
              ),
            ...submit(s),
            if (!isOwnerRole && permissions.contains('coach')) ...[
              const SizedBox(height: 20),
              coaching(s),
            ],
            ...removal(s),
          ],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => widget.member?['role'] == 'owner'
      ? AppPage(
          back: true,
          eyebrow: 'TEAM & ACCESS',
          title: 'Your staff responsibilities.',
          children: [
            StaffCoachingSection(memberId: widget.member!['id'], owner: true),
          ],
        )
      : BlocBuilder<StaffAssignmentCubit, StaffAssignmentScreenModel>(
          bloc: cubit,
          builder: (c, s) => isDesktopWidth(c)
              ? desktop(c, s)
              : AppPage(
                  back: true,
                  eyebrow: 'TEAM & ACCESS',
                  title: widget.member == null
                      ? 'The right people.\nThe right access.'
                      : 'Edit staff access.',
                  subtitle:
                      'Assign staff to one business or several, or make them an owner with full access.',
                  children: [
                    Form(
                      key: form,
                      child: Column(
                        children: [
                          ...identityFields(),
                          if (isOwnerRole)
                            const AppCard(
                              child: Text(
                                'Owners have full access to every business and can add or remove other owners.',
                              ),
                            )
                          else ...[
                            const SizedBox(height: 24),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Assign businesses',
                                style: Theme.of(c).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 10),
                            for (final card in businessCards(s))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: card,
                              ),
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                'Permissions',
                                style: Theme.of(c).textTheme.titleMedium,
                              ),
                            ),
                            const SizedBox(height: 12),
                            permissionsCard(),
                          ],
                          const SizedBox(height: 24),
                          ...submit(s),
                          if (!isOwnerRole &&
                              permissions.contains('coach')) ...[
                            const SizedBox(height: 20),
                            coaching(s),
                          ],
                          ...removal(s),
                        ],
                      ),
                    ),
                  ],
                ),
        );
}
