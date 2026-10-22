import '../widgets/staff_coaching_section.dart';
import '../models/staff_access_draft.dart';
import '../cubit/staff_assignment_cubit.dart';
import '../models/staff_assignment_screen_model.dart';
import '../../../di/injection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (businesses.isEmpty) {
      showMessage(context, 'Select at least one business.');
      return;
    }
    if (restricted.any(
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
      permissions: permissions,
      assignments: businesses.map(
        (b) => BusinessAssignment(
          b,
          restricted.contains(b) ? resources[b]! : <String>[],
        ),
      ),
    );
    if (widget.member != null) {
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
    String? link;
    final bool ok;
    if (widget.member == null) {
      link = await cubit.invite(data);
      ok = link != null;
    } else {
      ok = await cubit.update(widget.member!['id'], data);
    }
    if (!mounted || !ok) return;
    if (link != null) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Invitation ready'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Share this private link with the invited staff member. It expires in seven days. No email has been sent.',
              ),
              const SizedBox(height: 16),
              SelectableText(link!),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link!));
                if (c.mounted) showMessage(c, 'Invitation link copied.');
              },
              child: const Text('Copy link'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
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
      ],
      value: role,
      onChanged: (v) => cubit.selectRole(v),
    ),
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

  Widget coaching(StaffAssignmentScreenModel s) => widget.member == null
      ? const AppCard(
          child: Text(
            'After this staff member accepts their invitation, open their staff details to assign coaching plans.',
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
      label: widget.member == null ? 'Create invitation' : 'Save staff access',
      icon: Icons.check,
      busy: s.busy,
      onPressed: s.data.isOwner ? save : null,
    ),
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
        'Assign staff to one business or several. You remain the organization owner.',
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
                  ? 'They receive a private invitation link.'
                  : 'The email address cannot be changed.',
              child: AppCard(
                padding: const EdgeInsets.all(22),
                child: Column(children: identityFields()),
              ),
            ),
            AppPanel(
              title: 'Assign businesses',
              subtitle: 'Optionally restrict a business to selected resources.',
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
            AppPanel(
              title: 'Permissions',
              subtitle: 'What this person can do in assigned businesses.',
              child: permissionsCard(),
            ),
            ...submit(s),
            if (permissions.contains('coach')) ...[
              const SizedBox(height: 20),
              coaching(s),
            ],
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
                      'Assign staff to one business or several. You remain the organization owner.',
                  children: [
                    Form(
                      key: form,
                      child: Column(
                        children: [
                          ...identityFields(),
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
                          const SizedBox(height: 24),
                          ...submit(s),
                          if (permissions.contains('coach')) ...[
                            const SizedBox(height: 20),
                            coaching(s),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
        );
}
