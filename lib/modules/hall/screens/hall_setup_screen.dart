import '../../configuration_drafts/models/configuration_draft.dart';
import '../../configuration_drafts/widgets/configuration_draft_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../cubit/hall_setup_cubit.dart';
import '../models/hall_setup_state.dart';
import '../models/hall_screen_models.dart';
import 'hall_overview_screen.dart';
import 'hall_resources_screen.dart';
import 'hall_pricing_screen.dart';
import 'hall_review_screen.dart';

class HallSetupScreen extends StatefulWidget {
  const HallSetupScreen({super.key, required this.businessId});
  final String businessId;
  @override
  State<HallSetupScreen> createState() => _HallSetupScreenState();
}

class _HallSetupScreenState extends State<HallSetupScreen> {
  late final cubit = getIt<HallSetupCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.businessId,
  );
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Widget page(HallSetupState s) => switch (s.section) {
    HallSection.overview => HallOverviewScreen(
      model: s.overviewModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    HallSection.halls => HallResourcesScreen(
      model: s.resourcesModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    HallSection.pricing => HallPricingScreen(
      model: s.pricingModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    HallSection.review => HallReviewScreen(
      model: s.reviewModel,
      businessName: s.business?.name ?? 'Your halls',
      onEditHall: s.disabled
          ? null
          : (id) => cubit.open(HallSection.halls, id: id),
      onEditPricing: s.disabled
          ? null
          : (id) => cubit.open(HallSection.pricing, id: id),
    ),
  };
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<HallSetupCubit, HallSetupState>(
    bloc: cubit,
    builder: (context, s) {
      if (s.business?.type != BusinessType.hall || !s.data.isOwner) {
        return const AppPage(
          back: true,
          title: 'Hall settings unavailable',
          children: [
            AppErrorWidget(
              message: 'Open a party hall business from your owner account.',
            ),
          ],
        );
      }
      final title = switch (s.section) {
        HallSection.overview => 'Hall settings',
        HallSection.halls => s.selectedHall?.name ?? 'Your halls',
        HallSection.pricing =>
          s.selectedHall?.name ?? 'Booking options & pricing',
        HallSection.review => 'Review your halls',
      };
      final desktop = isDesktopWidth(context);
      final body = <Widget>[
        if (s.business!.configuration != null &&
            s.business!.configuration?['kind'] != 'hall_v1') ...[
          const AppCard(
            child: Text(
              'Existing halls keep their resource IDs. Review the imported timing and prices before saving.',
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (s.section != HallSection.overview &&
            s.section != HallSection.review)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: Text(
                s.selectedOption != null
                    ? 'Booking options'
                    : s.selectedId != null
                    ? 'Back to list'
                    : 'All Hall settings',
              ),
              onPressed: s.disabled ? null : cubit.back,
            ),
          ),
        Form(key: form, child: page(s)),
      ];
      final footer = <Widget>[
        if (!desktop) const SizedBox(height: 22),
        if (s.message != null) ...[
          AppErrorWidget(message: s.message!),
          const SizedBox(height: 14),
        ],
        ConfigurationDraftNotice(
          status: s.localDraftStatus,
          dirty: s.dirty,
          message: s.localDraftMessage,
          onRetry: cubit.retryLocalDraft,
        ),
        const SizedBox(height: 12),
        AppButton(
          label: [HallSection.overview, HallSection.review].contains(s.section)
              ? 'Save changes'
              : 'Continue',
          icon: Icons.save_outlined,
          busy: s.saving,
          secondary: s.section == HallSection.review && !s.business!.ready,
          onPressed:
              s.disabled ||
                  ([
                        HallSection.overview,
                        HallSection.review,
                      ].contains(s.section) &&
                      !s.dirty &&
                      s.business!.configuration?['kind'] == 'hall_v1' &&
                      (!s.editingReady || s.business!.ready))
              ? null
              : () async {
                  if (form.currentState?.validate() == true) {
                    if ([
                      HallSection.overview,
                      HallSection.review,
                    ].contains(s.section)) {
                      await cubit.saveChanges();
                    } else {
                      cubit.continueSection();
                    }
                  }
                },
        ),
        if (s.section == HallSection.review && !s.business!.ready) ...[
          const SizedBox(height: 12),
          AppButton(
            label: 'Activate halls',
            icon: Icons.check_circle_outline,
            onPressed: s.disabled || s.draft.validate(complete: true) != null
                ? null
                : () async {
                    if (await cubit.activate() && !cubit.isClosed) {
                      cubit.open(HallSection.overview);
                    }
                  },
          ),
        ],
        TextButton(
          onPressed: s.disabled
              ? null
              : () async {
                  if (!s.dirty ||
                      await confirmAction(
                        context,
                        'Reload saved settings?',
                        'Your unsaved changes will be replaced with the latest saved configuration.',
                      )) {
                    await cubit.reloadSaved();
                  }
                },
          child: const Text('Reload saved settings'),
        ),
      ];
      return PopScope(
        canPop:
            s.section == HallSection.overview &&
            (!s.dirty ||
                s.allowExit ||
                s.localDraftStatus == LocalDraftStatus.saved) &&
            !s.saving &&
            !s.busy,
        onPopInvokedWithResult: (popped, result) async {
          if (popped || s.saving || s.busy) return;
          if (s.section != HallSection.overview) {
            cubit.back();
            return;
          }
          if (await confirmAction(
            context,
            'Leave setup?',
            'Your draft stays on this device. Online settings change only when you Save or Activate.',
          )) {
            cubit.allowExit();
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) Navigator.pop(context);
            });
          }
        },
        child: AppPage(
          key: PageStorageKey(
            'hall-${s.section.name}-${s.selectedId}-${s.selectedOption}',
          ),
          scrollId:
              'hall-${s.section.name}-${s.selectedId}-${s.selectedOption}',
          back: true,
          showAppBar: s.section == HallSection.review,
          compactHeader: s.section == HallSection.review,
          eyebrow: s.section == HallSection.review ? null : s.business!.name,
          title: title,
          subtitle: s.section == HallSection.review
              ? null
              : 'Hourly, sessions and full-day packages. Edit any section directly.',
          maxWidth: desktop ? 1200 : 760,
          children: desktop
              ? [
                  ConfigurationWorkspace(
                    businessName: s.business!.name,
                    ready: s.business!.ready,
                    sections: [
                      ConfigurationNavItem(
                        key: const ValueKey('hall-nav-overview'),
                        label: 'Overview',
                        icon: Icons.dashboard_outlined,
                        selected: s.section == HallSection.overview,
                        onTap: s.disabled
                            ? null
                            : () => cubit.open(HallSection.overview),
                      ),
                      for (final (section, label, subtitle, icon)
                          in hallSections(s.overviewModel))
                        ConfigurationNavItem(
                          key: ValueKey('hall-nav-${section.name}'),
                          label: label,
                          subtitle: subtitle,
                          icon: icon,
                          selected: s.section == section,
                          onTap: s.disabled ? null : () => cubit.open(section),
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
