import '../../configuration_drafts/models/configuration_draft.dart';
import '../../configuration_drafts/widgets/configuration_draft_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../cubit/pool_setup_cubit.dart';
import '../models/pool_setup_state.dart';
import '../models/pool_screen_models.dart';
import 'pool_overview_screen.dart';
import 'pool_resources_screen.dart';
import 'pool_pricing_screen.dart';
import 'pool_groups_screen.dart';
import 'pool_plans_screen.dart';
import 'pool_review_screen.dart';

class PoolSetupScreen extends StatefulWidget {
  const PoolSetupScreen({super.key, required this.businessId});
  final String businessId;
  @override
  State<PoolSetupScreen> createState() => _PoolSetupScreenState();
}

class _PoolSetupScreenState extends State<PoolSetupScreen> {
  late final cubit = getIt<PoolSetupCubit>(
    param1: context.read<WorkspaceCubit>(),
    param2: widget.businessId,
  );
  final form = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    cubit.loadCoaches();
  }

  @override
  void dispose() {
    cubit.close();
    super.dispose();
  }

  Widget page(PoolSetupState s) => switch (s.section) {
    PoolSection.overview => PoolOverviewScreen(
      model: s.overviewModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    PoolSection.pools => PoolResourcesScreen(
      model: s.resourcesModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    PoolSection.pricing => PoolPricingScreen(
      model: s.pricingModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    PoolSection.groups => PoolGroupsScreen(
      model: s.groupsModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    PoolSection.coaching => PoolPlansScreen(
      model: s.plansModel,
      cubit: cubit,
      disabled: s.disabled,
      coaching: true,
    ),
    PoolSection.plans => PoolPlansScreen(
      model: s.plansModel,
      cubit: cubit,
      disabled: s.disabled,
      coaching: false,
    ),
    PoolSection.review => PoolReviewScreen(
      model: s.reviewModel,
      businessName: s.business?.name ?? 'Your pools',
      onEditPool: s.disabled
          ? null
          : (id) => cubit.open(PoolSection.pools, id: id),
      onEditPricing: s.disabled
          ? null
          : (id) => cubit.open(PoolSection.pricing, id: id),
      onEditOffer: s.disabled
          ? null
          : (id) => cubit.open(PoolSection.groups, id: id),
      onEditPlan: s.disabled
          ? null
          : (id) => cubit.open(
              s.draft.plans.firstWhere((p) => p.id == id).coaching
                  ? PoolSection.coaching
                  : PoolSection.plans,
              id: id,
            ),
    ),
  };
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<PoolSetupCubit, PoolSetupState>(
    bloc: cubit,
    builder: (context, s) {
      if (s.business?.type != BusinessType.pool || !s.data.isOwner) {
        return const AppPage(
          back: true,
          title: 'Pool settings unavailable',
          children: [
            AppErrorWidget(
              message: 'Open a swimming pool business from your owner account.',
            ),
          ],
        );
      }
      final title = switch (s.section) {
        PoolSection.overview => 'Pool settings',
        PoolSection.pools => s.selectedPool?.name ?? 'Your pools',
        PoolSection.pricing => s.selectedPool?.name ?? 'Timing & pricing',
        PoolSection.groups => s.selectedOffer?.name ?? 'Group offers',
        PoolSection.coaching => s.selectedPlan?.name ?? 'Coaching plans',
        PoolSection.plans => s.selectedPlan?.name ?? 'Swimming plans',
        PoolSection.review => 'Review your pools',
      };
      return PopScope(
        canPop:
            s.section == PoolSection.overview &&
            (!s.dirty ||
                s.allowExit ||
                s.localDraftStatus == LocalDraftStatus.saved) &&
            !s.saving &&
            !s.busy,
        onPopInvokedWithResult: (popped, result) async {
          if (popped || s.saving || s.busy) return;
          if (s.section != PoolSection.overview) {
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
          key: PageStorageKey('pool-${s.section.name}-${s.selectedId}'),
          scrollId: 'pool-${s.section.name}-${s.selectedId}',
          back: true,
          showAppBar: s.section == PoolSection.review,
          compactHeader: s.section == PoolSection.review,
          eyebrow: s.section == PoolSection.review ? null : s.business!.name,
          title: title,
          subtitle: s.section == PoolSection.review
              ? null
              : s.resourceFlow
              ? 'Complete this pool before adding the next one.'
              : 'Manage each pool and edit saved settings directly.',
          maxWidth: 760,
          children: [
            if (s.business!.configuration != null &&
                s.business!.configuration?['kind'] != 'pool_v1') ...[
              const AppCard(
                child: Text(
                  'Existing pools keep their resource IDs and capacity. Add their depths and review the imported plan. Legacy unlimited/visit plans are disabled until converted to attendance days.',
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (s.section != PoolSection.overview &&
                s.section != PoolSection.review)
              TextButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: Text(
                  s.resourceFlow && s.section == PoolSection.pricing
                      ? 'Pool details'
                      : s.selectedId != null
                      ? 'Back to list'
                      : 'All Pool settings',
                ),
                onPressed: s.disabled ? null : cubit.back,
              ),
            if (s.resourceFlow) ...[
              Text(
                s.section == PoolSection.pools
                    ? 'STEP 1 OF 2 · DETAILS'
                    : 'STEP 2 OF 2 · TIMING & PRICING',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: s.section == PoolSection.pools ? .5 : 1,
              ),
              const SizedBox(height: 22),
            ],
            Form(key: form, child: page(s)),
            if (!s.resourceFlow &&
                s.section == PoolSection.pools &&
                s.selectedId != null)
              TextButton.icon(
                icon: const Icon(Icons.schedule_outlined),
                label: const Text('Edit timing & pricing'),
                onPressed: s.disabled
                    ? null
                    : () => cubit.open(PoolSection.pricing, id: s.selectedId),
              ),
            const SizedBox(height: 22),
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
            if (s.resourceFlow && s.section == PoolSection.pools)
              AppButton(
                label: 'Continue to timing & pricing',
                icon: Icons.arrow_forward_rounded,
                onPressed: s.disabled
                    ? null
                    : () {
                        if (form.currentState?.validate() == true) {
                          cubit.continueResource();
                        }
                      },
              )
            else if (s.resourceFlow && s.section == PoolSection.pricing) ...[
              AppButton(
                label: 'Continue',
                icon: Icons.check_rounded,
                busy: s.saving,
                onPressed: s.disabled
                    ? null
                    : () async {
                        if (form.currentState?.validate() == true) {
                          await cubit.finishResource();
                        }
                      },
              ),
              const SizedBox(height: 12),
              AppButton(
                label: 'Continue & add another pool',
                icon: Icons.add_rounded,
                secondary: true,
                onPressed: s.disabled || s.draft.pools.length >= 30
                    ? null
                    : () async {
                        if (form.currentState?.validate() == true) {
                          await cubit.finishResource(addAnother: true);
                        }
                      },
              ),
            ] else
              AppButton(
                label:
                    [
                      PoolSection.overview,
                      PoolSection.review,
                    ].contains(s.section)
                    ? 'Save changes'
                    : 'Continue',
                icon: Icons.save_outlined,
                busy: s.saving,
                secondary:
                    s.section == PoolSection.review && !s.business!.ready,
                onPressed:
                    s.disabled ||
                        ([
                              PoolSection.overview,
                              PoolSection.review,
                            ].contains(s.section) &&
                            !s.dirty &&
                            s.business!.configuration?['kind'] == 'pool_v1' &&
                            (!s.editingReady || s.business!.ready))
                    ? null
                    : () async {
                        if (form.currentState?.validate() == true) {
                          if ([
                            PoolSection.overview,
                            PoolSection.review,
                          ].contains(s.section)) {
                            await cubit.saveChanges();
                          } else {
                            cubit.back();
                            cubit.checkpointLocalDraft();
                          }
                        }
                      },
              ),
            if (s.section == PoolSection.review && !s.business!.ready) ...[
              const SizedBox(height: 12),
              AppButton(
                label: 'Activate pools',
                icon: Icons.check_circle_outline,
                onPressed:
                    s.disabled || s.draft.validate(complete: true) != null
                    ? null
                    : () async {
                        if (await cubit.activate() && !cubit.isClosed) {
                          cubit.open(PoolSection.overview);
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
          ],
        ),
      );
    },
  );
}
