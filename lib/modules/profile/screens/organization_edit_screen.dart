import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/organization_edit_cubit.dart';
import '../cubit/organization_edit_state.dart';

class OrganizationEditScreen extends StatefulWidget {
  const OrganizationEditScreen({super.key});
  @override
  State<OrganizationEditScreen> createState() => _OrganizationEditScreenState();
}

class _OrganizationEditScreenState extends State<OrganizationEditScreen> {
  late final cubit = getIt<OrganizationEditCubit>(
    param1: context.read<WorkspaceCubit>(),
  )..load();
  bool leaving = false;
  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Future<bool> discard({bool reload = false}) async {
    if (cubit.state.busy) return false;
    if (!cubit.state.dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(reload ? 'Reload latest details?' : 'Discard changes?'),
            content: Text(
              reload
                  ? 'Your unsaved changes will be replaced with the latest saved details.'
                  : 'Your organization changes have not been saved.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Keep editing'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(reload ? 'Reload' : 'Discard'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> exit() async {
    if (await discard() && mounted) {
      setState(() => leaving = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.pop();
      });
    }
  }

  Future<void> reload() async {
    if (await discard(reload: true)) await cubit.load();
  }

  Widget text(
    String label,
    String key,
    String value,
    ValueChanged<String> changed,
    OrganizationEditState state, {
    int max = 120,
    bool phone = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: ValueKey('${state.original?.revision}:$key'),
      initialValue: value,
      onChanged: changed,
      enabled: !state.busy && !state.loading,
      keyboardType: phone ? TextInputType.phone : TextInputType.text,
      maxLength: max,
      decoration: InputDecoration(
        labelText: label,
        errorText: state.errors[key],
        errorMaxLines: 3,
        counterText: '',
      ),
    ),
  );
  Widget pickerError(String? error) => error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            error,
            style: TextStyle(
              color: Theme.of(context).colorScheme.error,
              fontSize: 12,
            ),
          ),
        );
  // Fields of one location, in reading order. A null cell keeps its place
  // in the desktop grid when the state picker is not shown.
  List<Widget?> locationCells(OrganizationEditState s, int i) {
    final location = s.draft!.locations[i];
    final country = location.countryCode;
    return [
      text(
        'Location name',
        '${location.id}.name',
        location.name,
        (v) => cubit.locationFields(i, name: v),
        s,
      ),
      text(
        'Address line 1',
        '${location.id}.line1',
        location.line1,
        (v) => cubit.locationFields(i, line1: v),
        s,
        max: 200,
      ),
      text(
        'Address line 2 (optional)',
        '${location.id}.line2',
        location.line2,
        (v) => cubit.locationFields(i, line2: v),
        s,
        max: 200,
      ),
      text(
        'City',
        '${location.id}.city',
        location.city,
        (v) => cubit.locationFields(i, city: v),
        s,
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppPicker(
            label: 'Country',
            value: country,
            enabled: !s.busy && !s.loading,
            items: [
              const PickerItem('', 'Choose country'),
              ...s.countries.map((o) => PickerItem(o.code, o.name)),
            ],
            onChanged: (v) => cubit.country(i, v),
          ),
          pickerError(s.errors['${location.id}.country']),
          const SizedBox(height: 16),
        ],
      ),
      if (s.loadingCountries.contains(country))
        const AppRefreshIndicator(label: 'Loading states…')
      else if (s.failedCountries.contains(country))
        TextButton.icon(
          onPressed: () => cubit.loadStates(country),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry loading states'),
        )
      else if (s.states[country]?.isNotEmpty == true)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppPicker(
              label: 'State',
              value: location.stateCode,
              enabled: !s.busy && !s.loading,
              items: [
                const PickerItem('', 'Choose state'),
                ...s.states[country]!.map((o) => PickerItem(o.code, o.name)),
              ],
              onChanged: (v) => cubit.locationFields(i, stateCode: v),
            ),
            pickerError(s.errors['${location.id}.state']),
            const SizedBox(height: 16),
          ],
        )
      else
        null,
      text(
        'Pincode',
        '${location.id}.pincode',
        location.pincode,
        (v) => cubit.locationFields(i, pincode: v),
        s,
        max: 20,
      ),
      InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Timezone',
          enabled: false,
          prefixIcon: Icon(Icons.schedule),
        ),
        child: Text(location.timezone),
      ),
    ];
  }

  // Shared loading and error block above the form.
  List<Widget> status(OrganizationEditState s) => [
    if (s.loading)
      AppLoadingState(
        initial: s.draft == null,
        label: s.draft == null ? 'Loading organization details…' : null,
      ),
    if (s.error != null) ...[
      AppErrorWidget(
        message: s.error!,
        onRetry: s.draft == null ? cubit.load : null,
      ),
      if (s.conflict)
        TextButton.icon(
          onPressed: s.busy ? null : reload,
          icon: const Icon(Icons.refresh),
          label: const Text('Reload latest details'),
        ),
      const SizedBox(height: 16),
    ],
  ];

  // Wide windows: organization fields beside a two-column address form, with
  // the save action in the floating bar.
  Widget desktopPage(BuildContext c, OrganizationEditState s) {
    final draft = s.draft;
    final colors = Theme.of(c).colorScheme;
    Widget pair(Widget? a, Widget? b) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: a ?? const SizedBox.shrink()),
        const SizedBox(width: 20),
        Expanded(child: b ?? const SizedBox.shrink()),
      ],
    );
    return AppPage(
      title: 'Edit organization',
      eyebrow: 'WORKSPACE MANAGEMENT',
      subtitle: 'Update the organization name, phone number and addresses.',
      back: true,
      showAppBar: true,
      onBack: exit,
      scrollId: 'organization-edit',
      maxWidth: 1200,
      bottomBar: draft == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 14, 14),
              child: Row(
                children: [
                  Icon(
                    s.dirty ? Icons.edit_note : Icons.check_circle_outline,
                    color: s.dirty ? colors.primary : colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.dirty
                          ? 'You have unsaved changes.'
                          : 'No unsaved changes.',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                  TextButton(
                    onPressed: s.busy ? null : exit,
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 220,
                    child: AppButton(
                      label: 'Save changes',
                      busy: s.busy,
                      busyLabel: 'Saving changes…',
                      onPressed: s.canSave ? cubit.save : null,
                    ),
                  ),
                ],
              ),
            ),
      children: [
        ...status(s),
        if (draft != null)
          AppTwoPane(
            secondaryFirst: true,
            secondaryWidth: 360,
            secondary: [
              AppPanel(
                title: 'Organization information',
                child: AppCard(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 6),
                  child: Column(
                    children: [
                      text(
                        'Organization name',
                        'name',
                        draft.name,
                        (v) => cubit.fields(name: v),
                        s,
                      ),
                      text(
                        'Phone number',
                        'phone',
                        draft.phone,
                        (v) => cubit.fields(phone: v),
                        s,
                        max: 30,
                        phone: true,
                      ),
                    ],
                  ),
                ),
              ),
              AppCard(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.schedule, size: 20, color: colors.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Timezone stays unchanged so existing booking times remain correct.',
                      ),
                    ),
                  ],
                ),
              ),
            ],
            primary: [
              AppPanel(
                title: 'Locations & address',
                subtitle:
                    '${draft.locations.length} '
                    '${draft.locations.length == 1 ? 'location' : 'locations'}',
                child: Column(
                  children: [
                    for (var i = 0; i < draft.locations.length; i++)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 16),
                        child: AppCard(
                          padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                          child: Builder(
                            builder: (_) {
                              final cells = locationCells(s, i);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Location ${i + 1}',
                                    style: Theme.of(c).textTheme.titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 18),
                                  for (var k = 0; k < cells.length; k += 2)
                                    pair(
                                      cells[k],
                                      k + 1 < cells.length
                                          ? cells[k + 1]
                                          : null,
                                    ),
                                ],
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<OrganizationEditCubit, OrganizationEditState>(
    bloc: cubit,
    listener: (c, s) {
      if (s.saved) {
        showMessage(c, 'Organization details updated.');
        c.pop();
      }
    },
    builder: (c, s) {
      final draft = s.draft;
      return PopScope(
        canPop: leaving || s.saved || (!s.dirty && !s.busy),
        onPopInvokedWithResult: (popped, result) {
          if (!popped) exit();
        },
        child: isDesktopWidth(c)
            ? desktopPage(c, s)
            : AppPage(
                title: 'Edit organization',
                back: true,
                showAppBar: true,
                compactHeader: true,
                onBack: exit,
                scrollId: 'organization-edit',
                bottomBar: draft == null
                    ? null
                    : SafeArea(
                        top: false,
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            12,
                            24,
                            12 + MediaQuery.viewInsetsOf(c).bottom,
                          ),
                          child: AppButton(
                            label: 'Save changes',
                            busy: s.busy,
                            busyLabel: 'Saving changes…',
                            onPressed: s.canSave ? cubit.save : null,
                          ),
                        ),
                      ),
                children: [
                  if (s.loading)
                    AppLoadingState(
                      initial: draft == null,
                      label: draft == null
                          ? 'Loading organization details…'
                          : null,
                    ),
                  if (s.error != null) ...[
                    AppErrorWidget(
                      message: s.error!,
                      onRetry: draft == null ? cubit.load : null,
                    ),
                    if (s.conflict)
                      TextButton.icon(
                        onPressed: s.busy ? null : reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Reload latest details'),
                      ),
                    const SizedBox(height: 16),
                  ],
                  if (draft != null) ...[
                    Text(
                      'Organization information',
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    AppCard(
                      child: Column(
                        children: [
                          text(
                            'Organization name',
                            'name',
                            draft.name,
                            (v) => cubit.fields(name: v),
                            s,
                          ),
                          text(
                            'Phone number',
                            'phone',
                            draft.phone,
                            (v) => cubit.fields(phone: v),
                            s,
                            max: 30,
                            phone: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Locations & address',
                      style: Theme.of(c).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Timezone stays unchanged so existing booking times remain correct.',
                    ),
                    const SizedBox(height: 16),
                    for (var i = 0; i < draft.locations.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Location ${i + 1}',
                                style: Theme.of(c).textTheme.titleSmall,
                              ),
                              const SizedBox(height: 16),
                              ...locationCells(s, i).nonNulls,
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
      );
    },
  );
}
