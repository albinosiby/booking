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
        child: AppPage(
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
                label: draft == null ? 'Loading organization details…' : null,
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
                        text(
                          'Location name',
                          '${draft.locations[i].id}.name',
                          draft.locations[i].name,
                          (v) => cubit.locationFields(i, name: v),
                          s,
                        ),
                        text(
                          'Address line 1',
                          '${draft.locations[i].id}.line1',
                          draft.locations[i].line1,
                          (v) => cubit.locationFields(i, line1: v),
                          s,
                          max: 200,
                        ),
                        text(
                          'Address line 2 (optional)',
                          '${draft.locations[i].id}.line2',
                          draft.locations[i].line2,
                          (v) => cubit.locationFields(i, line2: v),
                          s,
                          max: 200,
                        ),
                        text(
                          'City',
                          '${draft.locations[i].id}.city',
                          draft.locations[i].city,
                          (v) => cubit.locationFields(i, city: v),
                          s,
                        ),
                        AppPicker(
                          label: 'Country',
                          value: draft.locations[i].countryCode,
                          enabled: !s.busy && !s.loading,
                          items: [
                            const PickerItem('', 'Choose country'),
                            ...s.countries.map(
                              (o) => PickerItem(o.code, o.name),
                            ),
                          ],
                          onChanged: (v) => cubit.country(i, v),
                        ),
                        pickerError(
                          s.errors['${draft.locations[i].id}.country'],
                        ),
                        const SizedBox(height: 16),
                        if (s.loadingCountries.contains(
                          draft.locations[i].countryCode,
                        ))
                          const AppRefreshIndicator(label: 'Loading states…')
                        else if (s.failedCountries.contains(
                          draft.locations[i].countryCode,
                        ))
                          TextButton.icon(
                            onPressed: () => cubit.loadStates(
                              draft.locations[i].countryCode,
                            ),
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry loading states'),
                          )
                        else if (s
                                .states[draft.locations[i].countryCode]
                                ?.isNotEmpty ==
                            true) ...[
                          AppPicker(
                            label: 'State',
                            value: draft.locations[i].stateCode,
                            enabled: !s.busy && !s.loading,
                            items: [
                              const PickerItem('', 'Choose state'),
                              ...s.states[draft.locations[i].countryCode]!.map(
                                (o) => PickerItem(o.code, o.name),
                              ),
                            ],
                            onChanged: (v) =>
                                cubit.locationFields(i, stateCode: v),
                          ),
                          pickerError(
                            s.errors['${draft.locations[i].id}.state'],
                          ),
                          const SizedBox(height: 16),
                        ],
                        text(
                          'Pincode',
                          '${draft.locations[i].id}.pincode',
                          draft.locations[i].pincode,
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
                          child: Text(draft.locations[i].timezone),
                        ),
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
