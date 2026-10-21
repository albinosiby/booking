import '../widgets/admission_form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import '../../../design_system/design_system.dart';
import '../../../di/injection.dart';
import '../../workspace/cubit/workspace_cubit.dart';
import '../cubit/admission_cubit.dart';
import '../cubit/admission_state.dart';

class AdmissionFormScreen extends StatefulWidget {
  const AdmissionFormScreen({
    super.key,
    this.renewalId,
    this.businessId,
    this.poolId,
    this.planId,
    this.date,
    this.controller,
    this.header,
    this.fixedLocation = false,
  });
  final String? renewalId, businessId, poolId, planId, date;
  final AdmissionCubit? controller;
  final Widget? header;
  final bool fixedLocation;
  @override
  State<AdmissionFormScreen> createState() => _AdmissionFormScreenState();
}

class _AdmissionFormScreenState extends State<AdmissionFormScreen> {
  late final cubit =
      widget.controller ??
      getIt<AdmissionCubit>(param1: context.read<WorkspaceCubit>());
  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      cubit.loadForm(
        renewalId: widget.renewalId,
        businessId: widget.businessId,
        poolId: widget.poolId,
        planId: widget.planId,
        date: widget.date,
      );
    }
  }

  @override
  void dispose() {
    if (widget.controller == null) cubit.close();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => BlocConsumer<AdmissionCubit, AdmissionState>(
    bloc: cubit,
    listener: (context, s) {
      if (s.savedId != null) context.replace('/admissions/${s.savedId}');
    },
    builder: (context, s) {
      final d = s.draft, enabled = !s.busy && !s.locked;
      return PopScope(
        canPop: !s.busy && !s.locked,
        child: AppPage(
          title: s.formKind == 'swimming'
              ? 'New swimming plan'
              : s.formKind == 'play'
              ? 'New court plan'
              : s.formKind == 'coaching'
              ? 'New coaching admission'
              : widget.renewalId == null
              ? 'New admission'
              : 'Renew admission',
          back: true,
          scrollId: 'admission-form',
          subtitle: 'Purchase a swimming or court plan, or a coaching course.',
          children: [
            if (widget.header != null) widget.header!,
            if (s.loading) const AppLoadingState(initial: true),
            if (s.error != null) AppErrorWidget(message: s.error!),
            if (s.locked && !s.busy)
              AppButton(label: 'Retry confirmation', onPressed: cubit.retry),
            if (!s.loading && s.catalog.businesses.isEmpty)
              const AppEmptyState(
                title: 'No plans available',
                message:
                    'Activate a pool or court business and configure an enabled plan.',
              ),
            if (!s.loading &&
                s.catalog.businesses.isEmpty &&
                s.formKind != null &&
                s.catalog.owner &&
                widget.businessId != null)
              TextButton(
                onPressed: () =>
                    context.push('/businesses/${widget.businessId}/settings'),
                child: const Text('Configure plans'),
              ),
            if (!s.loading &&
                s.catalog.canManage &&
                s.catalog.businesses.isNotEmpty)
              if (s.formKind != null && s.availablePlans.isEmpty) ...[
                AppEmptyState(
                  showCard: false,
                  title: s.formKind == 'coaching'
                      ? 'No coaching plans'
                      : s.formKind == 'play'
                      ? 'No court plans'
                      : 'No swimming plans',
                  message:
                      'No matching plans are configured for this ${(s.business?.spaceLabel ?? 'space').toLowerCase()}.',
                ),
                if (s.catalog.owner)
                  TextButton(
                    onPressed: () => context.push(
                      '/businesses/${widget.businessId}/settings',
                    ),
                    child: const Text('Configure plans'),
                  ),
              ] else if (s.preview != null) ...[
                AdmissionReviewSummary(state: s),
                SizedBox(height: 16.h),
                AppButton(
                  label: 'Confirm admission',
                  busy: s.busy,
                  onPressed: s.busy ? null : cubit.create,
                ),
                if (!s.locked)
                  TextButton(
                    onPressed: s.busy ? null : cubit.edit,
                    child: const Text('Edit details'),
                  ),
              ] else ...[
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Customer',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: 12.h),
                      ConfigurationField(
                        label: s.business?.court == true
                            ? 'Student name'
                            : 'Swimmer name',
                        value: d.customer.name,
                        enabled: enabled && widget.renewalId == null,
                        onChanged: (v) => cubit.update(
                          d.copyWith(
                            customer: d.customer.copyWith(
                              name: v,
                              clearId: true,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 12.h),
                      ConfigurationField(
                        label: 'Phone',
                        value: d.customer.phone,
                        enabled: enabled && widget.renewalId == null,
                        onChanged: cubit.customerPhone,
                      ),
                      for (final customer in s.customers)
                        ListTile(
                          title: Text(customer.name),
                          subtitle: Text(customer.phone),
                          onTap: enabled
                              ? () => cubit.chooseCustomer(customer)
                              : null,
                        ),
                      SizedBox(height: 12.h),
                      ConfigurationField(
                        label: 'Email (optional)',
                        value: d.customer.email,
                        enabled: enabled && widget.renewalId == null,
                        onChanged: (v) => cubit.update(
                          d.copyWith(customer: d.customer.copyWith(email: v)),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 16.h),
                if (!widget.fixedLocation)
                  AppPicker(
                    label: 'Business',
                    value: d.businessId,
                    enabled: enabled && widget.renewalId == null,
                    items: s.catalog.businesses
                        .map((b) => PickerItem(b.id, b.name))
                        .toList(),
                    onChanged: cubit.business,
                  ),
                SizedBox(height: 12.h),
                if (!widget.fixedLocation)
                  AppPicker(
                    label: s.business?.spaceLabel ?? 'Pool',
                    value: d.poolId,
                    enabled: enabled,
                    items:
                        s.business?.pools
                            .map((p) => PickerItem(p.id, p.name))
                            .toList() ??
                        [],
                    onChanged: cubit.pool,
                  ),
                SizedBox(height: 12.h),
                AdmissionScheduleFields(cubit: cubit, state: s),
                SizedBox(height: 16.h),
                if (s.catalog.canCollect)
                  AppCard(
                    child: AdmissionPaymentFields(cubit: cubit, state: s),
                  ),
                SizedBox(height: 16.h),
                AppButton(
                  label: 'Review admission',
                  busy: s.busy,
                  onPressed: enabled ? cubit.review : null,
                ),
              ],
          ],
        ),
      );
    },
  );
}
