import '../../configuration_drafts/models/configuration_draft.dart';
import '../../configuration_drafts/widgets/configuration_draft_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../cubit/turf_setup_cubit.dart';
import '../models/turf_setup_state.dart';
import 'turf_sports_screen.dart';
import 'turf_grounds_screen.dart';
import 'turf_spaces_screen.dart';
import 'turf_offerings_screen.dart';
import 'turf_rules_screen.dart';
import 'turf_review_screen.dart';
import 'turf_settings_overview_screen.dart';

class TurfSetupScreen extends StatefulWidget {
  const TurfSetupScreen({
    super.key,
    required this.businessId,
    this.editMode = false,
  });
  final String businessId;
  final bool editMode;
  @override
  State<TurfSetupScreen> createState() => _TurfSetupScreenState();
}

class _TurfSetupScreenState extends State<TurfSetupScreen> {
  late final cubit = getIt<TurfSetupCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.businessId,
  );
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    if (widget.editMode) cubit.beginEditing();
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  static const labels = [
    'Sports',
    'Grounds',
    'Spaces',
    'Offerings',
    'Pricing',
    'Review',
  ];

  /// Desktop rail keys, `turf-nav-<name>`, in step order.
  static const navNames = [
    'sports',
    'grounds',
    'spaces',
    'offerings',
    'pricing',
    'review',
  ];
  static const titles = [
    'Sports offered.',
    'Your physical grounds.',
    'Bookable spaces.',
    'Sports & formats.',
    'Timing & pricing.',
    'Review your turf.',
  ];
  static const descriptions = [
    'Choose football, cricket or both. Each sport will use the same ground sections.',
    'A physical ground is one independent piece of space. Your main ground has two halves that combine.',
    'Name the two halves and the combined full ground. Shared sections determine which bookings can overlap.',
    'Enable sports for each space and name their formats. Your halves support 5s football and the full ground supports 7s.',
    'Choose a sport and space, then configure booking durations and weekday/time pricing.',
    'Check the physical layout and pricing before activation.',
  ];
  Widget page(TurfSetupState state) => switch (state.step) {
    0 => TurfSportsScreen(
      model: state.sportsModel,
      cubit: cubit,
      disabled: state.disabled,
    ),
    1 => TurfGroundsScreen(
      model: state.groundsModel,
      cubit: cubit,
      disabled: state.disabled,
    ),
    2 => TurfSpacesScreen(
      model: state.spacesModel,
      cubit: cubit,
      disabled: state.disabled,
    ),
    3 => TurfOfferingsScreen(
      model: state.offeringsModel,
      cubit: cubit,
      disabled: state.disabled,
    ),
    4 => TurfRulesScreen(
      model: state.rulesModel,
      cubit: cubit,
      disabled: state.disabled,
    ),
    _ => TurfReviewScreen(
      model: state.reviewModel,
      currency: state.currency,
      businessName: state.business?.name ?? 'Your turf',
      onEditGrounds: state.disabled ? null : () => cubit.step(1),
      onEditOffering: state.disabled
          ? null
          : (id) {
              cubit.step(4);
              cubit.selectPricingOffering(id);
            },
    ),
  };
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<TurfSetupCubit, TurfSetupState>(
    bloc: cubit,
    builder: (context, state) {
      if (state.business == null ||
          state.business!.type != BusinessType.turf ||
          !state.data.isOwner) {
        return const AppPage(
          back: true,
          title: 'Turf setup unavailable',
          children: [
            AppErrorWidget(
              message: 'Open an accessible turf from your owner account.',
            ),
          ],
        );
      }
      final desktop = isDesktopWidth(context);
      final body = <Widget>[
        if (desktop && !state.editMode && state.step != 5)
          LinearProgressIndicator(
            key: const ValueKey('turf-step-progress'),
            value: (state.step + 1) / labels.length,
          )
        else if (!state.editMode && state.step != 5)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: labels
                .asMap()
                .entries
                .map(
                  (e) => ChoiceChip(
                    label: Text('${e.key + 1}. ${e.value}'),
                    selected: state.step == e.key,
                    onSelected: state.disabled || e.key > state.step
                        ? null
                        : (_) => cubit.step(e.key),
                  ),
                )
                .toList(),
          ),
        // Desktop settings start level with the rail; nothing sits above them.
        if (state.step != 5 && (!desktop || !state.editMode))
          const SizedBox(height: 20),
        if (state.business!.resources.isNotEmpty &&
            state.business!.configuration?['kind'] != 'turf_v1') ...[
          const AppCard(
            child: Text(
              'Existing resources are imported as independent grounds. Change their arrangement only if they physically share space.',
            ),
          ),
          const SizedBox(height: 18),
        ],
        if (state.editMode && !state.settingsOverview)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: state.disabled ? null : cubit.showSettingsOverview,
              icon: const Icon(Icons.arrow_back),
              label: const Text('All Turf settings'),
            ),
          ),
        if (state.editMode && state.settingsOverview)
          TurfSettingsOverviewScreen(
            model: state.settingsModel,
            cubit: cubit,
            disabled: state.disabled,
          )
        else
          Form(key: form, child: page(state)),
      ];
      final footer = <Widget>[
        if (!desktop) const SizedBox(height: 22),
        if (state.message != null) ...[
          AppErrorWidget(message: state.message!),
          const SizedBox(height: 14),
        ],
        ConfigurationDraftNotice(
          status: state.localDraftStatus,
          dirty: state.dirty,
          message: state.localDraftMessage,
          onRetry: cubit.retryLocalDraft,
        ),
        const SizedBox(height: 12),
        if (state.editMode &&
            !state.settingsOverview &&
            (state.step < 5 || state.editingReady))
          AppButton(
            label: 'Save changes',
            icon: Icons.save_outlined,
            busy: state.saving,
            onPressed:
                state.disabled ||
                    (!state.dirty &&
                        state.business!.configuration?['kind'] == 'turf_v1' &&
                        (!state.editingReady || state.business!.ready))
                ? null
                : () async {
                    if (form.currentState?.validate() == true) {
                      await cubit.saveSettings();
                    }
                  },
          )
        else if (!state.editMode && state.step < 5)
          AppButton(
            label: 'Continue',
            busy: state.saving,
            icon: Icons.arrow_forward,
            onPressed: state.disabled
                ? null
                : () async {
                    if (form.currentState?.validate() == true) {
                      await cubit.continueSetup();
                    }
                  },
          )
        else if (state.step == 5 &&
            (!state.editMode || !state.settingsOverview))
          AppButton(
            label: 'Activate turf',
            icon: Icons.check_circle_outline,
            busy: state.saving,
            onPressed: state.disabled || state.reviewModel.validation != null
                ? null
                : () async {
                    if (await cubit.activate() && context.mounted) {
                      if (state.editMode) {
                        cubit.showSettingsOverview();
                      } else {
                        context.go('/home');
                      }
                    }
                  },
          ),
        if (!state.editMode && state.step > 0)
          TextButton(
            onPressed: state.disabled ? null : () => cubit.step(state.step - 1),
            child: const Text('Previous step'),
          ),
        TextButton(
          onPressed: state.disabled
              ? null
              : () async {
                  if (!state.dirty ||
                      await confirmAction(
                        context,
                        'Reload saved configuration?',
                        'Your unsaved changes will be replaced with the latest server data.',
                      )) {
                    await cubit.refreshSaved();
                  }
                },
          child: const Text('Reload saved configuration'),
        ),
      ];
      return PopScope(
        canPop:
            (!state.editMode || state.settingsOverview) &&
            (!state.dirty ||
                state.allowExit ||
                state.localDraftStatus == LocalDraftStatus.saved) &&
            !state.saving &&
            !state.busy,
        onPopInvokedWithResult: (popped, result) async {
          if (popped || state.saving || state.busy) return;
          if (state.editMode && !state.settingsOverview) {
            cubit.showSettingsOverview();
            return;
          }
          if (await confirmAction(
            context,
            'Leave setup?',
            state.editMode
                ? 'Your draft stays on this device. Online settings change only when you Save or Activate.'
                : 'Your draft stays on this device. Continue moves to the next step; Save or Activate applies changes online.',
          )) {
            cubit.allowExit();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.pop(context);
            });
          }
        },
        child: AppPage(
          key: state.editMode
              ? ValueKey(
                  'turf-settings-${state.settingsOverview}-${state.step}-${state.pricingOfferingId}',
                )
              : null,
          back: true,
          showAppBar: state.step == 5 && !state.settingsOverview,
          compactHeader: state.step == 5 && !state.settingsOverview,
          eyebrow: state.step == 5 && !state.settingsOverview
              ? null
              : state.editMode
              ? state.business!.name
              : '${state.business!.name} · STEP ${state.step + 1} OF 6',
          title: state.editMode && state.settingsOverview
              ? 'Turf settings'
              : titles[state.step],
          subtitle: state.step == 5 && !state.settingsOverview
              ? null
              : state.editMode && state.settingsOverview
              ? 'Choose the area you want to edit. No setup steps to repeat.'
              : descriptions[state.step],
          maxWidth: desktop ? 1200 : 760,
          children: desktop
              ? [
                  ConfigurationWorkspace(
                    businessName: state.business!.name,
                    ready: state.business!.ready,
                    sections: [
                      if (state.editMode)
                        ConfigurationNavItem(
                          key: const ValueKey('turf-nav-overview'),
                          label: 'Overview',
                          icon: Icons.dashboard_outlined,
                          selected: state.settingsOverview,
                          onTap: state.disabled
                              ? null
                              : cubit.showSettingsOverview,
                        ),
                      for (final (index, (label, subtitle, icon))
                          in turfSettingsAreas(state.settingsModel).indexed)
                        ConfigurationNavItem(
                          key: ValueKey('turf-nav-${navNames[index]}'),
                          label: state.editMode
                              ? label
                              : '${index + 1}. $label',
                          subtitle: state.editMode
                              ? subtitle
                              : index < state.step
                              ? 'Done · tap to revisit'
                              : index == state.step
                              ? 'Current step'
                              : 'Up next',
                          icon: !state.editMode && index < state.step
                              ? Icons.check_circle_outline
                              : icon,
                          selected: state.editMode
                              ? !state.settingsOverview && state.step == index
                              : state.step == index,
                          onTap: state.disabled
                              ? null
                              : state.editMode
                              ? () => cubit.openSettingsSection(index)
                              : index > state.step
                              ? null
                              : () => cubit.step(index),
                        ),
                    ],
                    content: body,
                    actions: footer,
                  ),
                ]
              : [...body, ...footer],
        ),
      );
    },
  );
}
