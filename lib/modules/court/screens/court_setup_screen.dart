import '../../configuration_drafts/models/configuration_draft.dart';
import '../../configuration_drafts/widgets/configuration_draft_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../../workspace/models/workspace.dart';
import '../cubit/court_setup_cubit.dart';
import '../models/court_setup_state.dart';
import '../models/court_screen_models.dart';
import 'court_overview_screen.dart';
import 'court_resources_screen.dart';
import 'court_pricing_screen.dart';
import 'court_review_screen.dart';

class CourtSetupScreen extends StatefulWidget {
  const CourtSetupScreen({super.key, required this.businessId});
  final String businessId;
  @override
  State<CourtSetupScreen> createState() => _CourtSetupScreenState();
}

class _CourtSetupScreenState extends State<CourtSetupScreen> {
  late final cubit = getIt<CourtSetupCubit>(
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

  Widget page(CourtSetupState s) => switch (s.section) {
    CourtSection.overview => CourtOverviewScreen(
      model: s.overviewModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    CourtSection.courts => CourtResourcesScreen(
      model: s.resourcesModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    CourtSection.pricing => CourtPricingScreen(
      model: s.pricingModel,
      cubit: cubit,
      disabled: s.disabled,
    ),
    CourtSection.review => CourtReviewScreen(
      model: s.reviewModel,
      businessName: s.business?.name ?? 'Your courts',
      onEditCourt: s.disabled
          ? null
          : (id) => cubit.open(CourtSection.courts, id: id),
      onEditPricing: s.disabled
          ? null
          : (id) => cubit.open(CourtSection.pricing, id: id),
    ),
  };
  @override
  Widget build(
    BuildContext context,
  ) => BlocBuilder<CourtSetupCubit, CourtSetupState>(
    bloc: cubit,
    builder: (context, s) {
      if (![
            BusinessType.badminton,
            BusinessType.tennis,
            BusinessType.basketball,
          ].contains(s.business?.type) ||
          !s.data.isOwner) {
        return const AppPage(
          back: true,
          title: 'Court settings unavailable',
          children: [
            AppErrorWidget(
              message:
                  'Open a badminton, tennis or basketball business from your owner account.',
            ),
          ],
        );
      }
      final title = switch (s.section) {
        CourtSection.overview => 'Court settings',
        CourtSection.courts => s.selectedCourt?.name ?? 'Your courts',
        CourtSection.pricing => s.selectedCourt?.name ?? 'Timing & pricing',
        CourtSection.review => 'Review your courts',
      };
      return PopScope(
        canPop:
            s.section == CourtSection.overview &&
            (!s.dirty ||
                s.allowExit ||
                s.localDraftStatus == LocalDraftStatus.saved) &&
            !s.saving &&
            !s.busy,
        onPopInvokedWithResult: (popped, result) async {
          if (popped || s.saving || s.busy) return;
          if (s.section != CourtSection.overview) {
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
          key: PageStorageKey('court-${s.section.name}-${s.selectedId}'),
          scrollId: 'court-${s.section.name}-${s.selectedId}',
          back: true,
          showAppBar: s.section == CourtSection.review,
          compactHeader: s.section == CourtSection.review,
          eyebrow: s.section == CourtSection.review ? null : s.business!.name,
          title: title,
          subtitle: s.section == CourtSection.review
              ? null
              : s.resourceFlow
              ? 'Complete this court before adding the next one.'
              : 'Manage each court and edit saved settings directly.',
          maxWidth: 760,
          children: [
            if (s.business!.configuration != null &&
                s.business!.configuration?['kind'] != 'court_v1') ...[
              const AppCard(
                child: Text(
                  'Existing courts keep their resource IDs. Review the imported timing and prices before saving.',
                ),
              ),
              const SizedBox(height: 16),
            ],
            if (s.section != CourtSection.overview &&
                s.section != CourtSection.review)
              TextButton.icon(
                icon: const Icon(Icons.arrow_back),
                label: Text(
                  s.resourceFlow && s.section == CourtSection.pricing
                      ? 'Court details'
                      : s.selectedId != null
                      ? 'Back to list'
                      : 'All Court settings',
                ),
                onPressed: s.disabled ? null : cubit.back,
              ),
            if (s.resourceFlow) ...[
              Text(
                s.section == CourtSection.courts
                    ? 'STEP 1 OF 2 · DETAILS'
                    : 'STEP 2 OF 2 · TIMING & PRICING',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: s.section == CourtSection.courts ? .5 : 1,
              ),
              const SizedBox(height: 22),
            ],
            Form(key: form, child: page(s)),
            if (!s.resourceFlow &&
                s.section == CourtSection.courts &&
                s.selectedId != null)
              TextButton.icon(
                icon: const Icon(Icons.schedule_outlined),
                label: const Text('Edit timing & pricing'),
                onPressed: s.disabled
                    ? null
                    : () => cubit.open(CourtSection.pricing, id: s.selectedId),
              ),
            if (s.draft.courts.isNotEmpty ||
                ![
                  CourtSection.courts,
                  CourtSection.pricing,
                ].contains(s.section)) ...[
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
              if (s.resourceFlow && s.section == CourtSection.courts)
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
              else if (s.resourceFlow && s.section == CourtSection.pricing) ...[
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
                  label: 'Continue & add another court',
                  icon: Icons.add_rounded,
                  secondary: true,
                  onPressed: s.disabled || s.draft.courts.length >= 50
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
                        CourtSection.overview,
                        CourtSection.review,
                      ].contains(s.section)
                      ? 'Save changes'
                      : 'Continue',
                  icon: Icons.save_outlined,
                  busy: s.saving,
                  secondary:
                      s.section == CourtSection.review && !s.business!.ready,
                  onPressed:
                      s.disabled ||
                          ([
                                CourtSection.overview,
                                CourtSection.review,
                              ].contains(s.section) &&
                              !s.dirty &&
                              s.business!.configuration?['kind'] ==
                                  'court_v1' &&
                              (!s.editingReady || s.business!.ready))
                      ? null
                      : () async {
                          if (form.currentState?.validate() == true) {
                            if ([
                              CourtSection.overview,
                              CourtSection.review,
                            ].contains(s.section)) {
                              await cubit.saveChanges();
                            } else {
                              cubit.back();
                              cubit.checkpointLocalDraft();
                            }
                          }
                        },
                ),
              if (s.section == CourtSection.review && !s.business!.ready) ...[
                const SizedBox(height: 12),
                AppButton(
                  label: 'Activate courts',
                  icon: Icons.check_circle_outline,
                  onPressed:
                      s.disabled || s.draft.validate(complete: true) != null
                      ? null
                      : () async {
                          if (await cubit.activate() && !cubit.isClosed) {
                            cubit.open(CourtSection.overview);
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
          ],
        ),
      );
    },
  );
}
