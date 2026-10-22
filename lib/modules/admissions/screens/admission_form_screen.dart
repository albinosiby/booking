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
import '../../bookings/models/booking_models.dart' show bookingMoney;
import '../widgets/admission_cards.dart' show admissionKindIcon;

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
    this.formKind,
  });
  final String? renewalId, businessId, poolId, planId, date;
  final AdmissionCubit? controller;
  final Widget? header;
  final bool fixedLocation;
  final String? formKind;
  @override
  State<AdmissionFormScreen> createState() => _AdmissionFormScreenState();
}

class _AdmissionFormScreenState extends State<AdmissionFormScreen> {
  late final cubit =
      widget.controller ??
      getIt<AdmissionCubit>(param1: context.read<WorkspaceCubit>());

  Widget customer(AdmissionState s, bool enabled) {
    final d = s.draft;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Customer', style: Theme.of(context).textTheme.titleMedium),
          SizedBox(height: 12.h),
          ConfigurationField(
            label: s.business?.court == true || s.formKind == 'coaching'
                ? 'Student name'
                : 'Swimmer name',
            value: d.customer.name,
            enabled: enabled && widget.renewalId == null,
            onChanged: (v) => cubit.update(
              d.copyWith(customer: d.customer.copyWith(name: v, clearId: true)),
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
              onTap: enabled ? () => cubit.chooseCustomer(customer) : null,
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
    );
  }

  List<Widget> location(AdmissionState s, bool enabled) {
    final d = s.draft;
    return [
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
              s.business?.pools.map((p) => PickerItem(p.id, p.name)).toList() ??
              [],
          onChanged: cubit.pool,
        ),
      SizedBox(height: 12.h),
    ];
  }

  Widget reviewButton(AdmissionState s, bool enabled) => AppButton(
    label: 'Review admission',
    busy: s.busy,
    onPressed: enabled ? cubit.review : null,
  );

  List<Widget> confirm(AdmissionState s) => [
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
  ];

  // Desktop web: details on the left, plan total and confirmation beside them.
  Widget desktop(AdmissionState s, bool enabled) {
    final theme = Theme.of(context);
    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Text(text, style: theme.textTheme.titleMedium),
    );
    if (s.preview != null) {
      return AppTwoPane(
        primary: [AdmissionReviewSummary(state: s)],
        secondary: [
          _PlanSummaryCard(state: s),
          const SizedBox(height: 16),
          ...confirm(s),
        ],
      );
    }
    return AppTwoPane(
      primary: [
        customer(s, enabled),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading('Plan & schedule'),
              ...location(s, enabled),
              AdmissionScheduleFields(cubit: cubit, state: s),
            ],
          ),
        ),
      ],
      secondary: [
        _PlanSummaryCard(state: s),
        const SizedBox(height: 16),
        if (s.catalog.canCollect) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading('Payment'),
                AdmissionPaymentFields(cubit: cubit, state: s),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        reviewButton(s, enabled),
      ],
    );
  }

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
        formKind: widget.formKind,
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
      final enabled = !s.busy && !s.locked;
      final wide = isDesktopWidth(context);
      return PopScope(
        canPop: !s.busy && !s.locked,
        child: AppPage(
          title: s.formKind == 'plans'
              ? 'New plan admission'
              : s.formKind == 'swimming'
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
          maxWidth: wide ? 1200 : 620,
          subtitle: s.formKind == 'coaching'
              ? 'Enroll a student in a coaching plan.'
              : s.formKind == 'plans'
              ? 'Enroll a customer in a swimming or court access plan.'
              : 'Purchase a swimming or court plan, or a coaching course.',
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
                if (!widget.fixedLocation) ...location(s, enabled),
                AppEmptyState(
                  showCard: false,
                  title: s.formKind == 'coaching'
                      ? 'No coaching plans'
                      : s.formKind == 'play'
                      ? 'No court plans'
                      : s.formKind == 'plans'
                      ? 'No access plans'
                      : 'No swimming plans',
                  message:
                      'No matching plans are configured for this ${(s.business?.spaceLabel ?? 'space').toLowerCase()}.',
                ),
                if (s.catalog.owner && s.business != null)
                  TextButton(
                    onPressed: () =>
                        context.push('/businesses/${s.business!.id}/settings'),
                    child: const Text('Configure plans'),
                  ),
              ] else if (wide)
                desktop(s, enabled)
              else if (s.preview != null) ...[
                AdmissionReviewSummary(state: s),
                SizedBox(height: 16.h),
                ...confirm(s),
              ] else ...[
                customer(s, enabled),
                SizedBox(height: 16.h),
                ...location(s, enabled),
                AdmissionScheduleFields(cubit: cubit, state: s),
                SizedBox(height: 16.h),
                if (s.catalog.canCollect)
                  AppCard(
                    child: AdmissionPaymentFields(cubit: cubit, state: s),
                  ),
                SizedBox(height: 16.h),
                reviewButton(s, enabled),
              ],
          ],
        ),
      );
    },
  );
}

/// Desktop side card: the selected plan, its validity and the amount due.
class _PlanSummaryCard extends StatelessWidget {
  const _PlanSummaryCard({required this.state});
  final AdmissionState state;
  @override
  Widget build(BuildContext context) {
    final s = state, d = s.draft, p = s.plan;
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: .65);
    final currency = s.catalog.currency, entry = s.paymentEntry;
    Widget row(String label, String value, {Color? color, bool bold = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: color,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
    return AppCard(
      key: const ValueKey('admission-plan-summary'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'PLAN SUMMARY',
            style: TextStyle(
              color: scheme.primary,
              fontSize: 11,
              letterSpacing: 1.6,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          if (p == null)
            Text(
              'Choose a plan to see its validity and total.',
              style: theme.textTheme.bodyMedium?.copyWith(color: muted),
            )
          else ...[
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(admissionKindIcon(p.kind), color: scheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        [
                          s.business?.name ?? '',
                          s.pool?.name ?? '',
                        ].where((v) => v.isNotEmpty).join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            row(
              'Allowance',
              '${p.allowance} ${p.kind == 'coaching' ? 'classes' : 'days'}',
            ),
            row('Validity', p.validityLabel),
            if (p.kind == 'coaching') row('Coach', p.coach),
            row(
              'Attendance',
              d.mode == 'fixed' ? 'Fixed weekly schedule' : 'Flexible',
            ),
            row('Starts', d.start),
            row('Expires', s.expiry ?? 'Calculated at review'),
            const SizedBox(height: 8),
            Divider(color: scheme.outline.withValues(alpha: .4)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text('Total', style: theme.textTheme.titleMedium),
                ),
                Text(
                  bookingMoney(entry.total ?? p.total, currency),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            row(
              'Collecting now',
              bookingMoney(entry.received, currency),
              color: scheme.primary,
            ),
            row(
              'Balance due',
              bookingMoney(entry.remaining ?? 0, currency),
              color: (entry.remaining ?? 0) > 0 ? scheme.error : null,
              bold: true,
            ),
          ],
        ],
      ),
    );
  }
}
