import '../../../utils/helpers/pricing_days.dart';
import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/court_screen_models.dart';
import '../models/court_configuration.dart';
import '../../pool/models/pool_configuration.dart' show PoolCoach;
import '../cubit/court_setup_cubit.dart';
import '../widgets/court_editors.dart';

class CourtCoachingScreen extends StatelessWidget {
  const CourtCoachingScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
    this.coaches = const [],
  });
  final CourtCoachingModel model;
  final CourtSetupCubit cubit;
  final bool disabled;

  /// Team coaches of this business, to name assigned plan coaches.
  final List<PoolCoach> coaches;
  String coachName(CourtPlan plan) => plan.coachId == null
      ? 'Unassigned'
      : coaches.where((c) => c.id == plan.coachId).firstOrNull?.name ??
            'Assigned coach';
  @override
  Widget build(BuildContext context) {
    final p = model.selected;
    if (p == null && !model.courts.any((c) => c.enabled)) {
      return Column(
        children: [
          const AppEmptyState(
            title: 'Add a court first',
            message: 'Plans need at least one enabled court.',
          ),
          AppButton(
            label: 'Configure courts',
            onPressed: disabled ? null : () => cubit.open(CourtSection.courts),
          ),
        ],
      );
    }
    if (p == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppCard(
            child: Text(
              'Sell plans through Profile → Admissions & Coaching. A court plan gives a player a number of play days; each visit reserves the whole court. A coaching plan runs batches: students of the same plan, court and time share one court reservation.',
            ),
          ),
          const SizedBox(height: 16),
          CourtItemList(
            items: model.plans
                .map(
                  (p) => (
                    p.id,
                    p.name,
                    '${p.coaching ? 'Coaching' : 'Court plan'} · ${p.trackAttendance ? '${p.allowance} ${p.coaching ? 'classes' : 'play days'}' : 'Membership-only'} · ${p.validityLabel} · ${model.currency} ${p.price.isEmpty ? 'not set' : p.price}${p.coaching && p.trackAttendance ? ' · ${coachName(p)}' : ''}${p.enabled ? '' : ' · disabled'}',
                  ),
                )
                .toList(),
            addLabel: 'Add coaching plan',
            add: model.plans.length < 50 ? cubit.addPlan : null,
            select: (id) => cubit.open(CourtSection.coaching, id: id),
            enabled: !disabled,
          ),
          if (model.plans.length < 50) ...[
            const SizedBox(height: 12),
            AppButton(
              label: 'Add court plan',
              icon: Icons.add,
              secondary: true,
              onPressed: disabled ? null : () => cubit.addPlan(coaching: false),
            ),
          ],
        ],
      );
    }
    void update(CourtPlan Function(CourtPlan) change) =>
        cubit.updatePlan(p.id, change);
    final selectedCourts = model.courts
        .where((c) => p.courtIds.contains(c.id))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigurationField(
          label: p.coaching ? 'Coaching plan name' : 'Court plan name',
          value: p.name,
          enabled: !disabled,
          validator: courtName,
          onChanged: (v) => update((p) => p.copyWith(name: v)),
        ),
        const SizedBox(height: 16),
        Text('Courts', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final c in model.courts)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.name),
            subtitle: c.enabled ? null : const Text('Disabled'),
            value: p.courtIds.contains(c.id),
            onChanged: !disabled && (c.enabled || p.courtIds.contains(c.id))
                ? (v) {
                    final ids = {...p.courtIds};
                    v == true ? ids.add(c.id) : ids.remove(c.id);
                    update((p) => p.copyWith(courtIds: ids));
                  }
                : null,
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Track sessions & attendance'),
          subtitle: const Text(
            'Off: list members, validity, fees and renewals only. No classes or court reservations. Applies to new enrollments and renewals; existing memberships keep their mode.',
          ),
          value: p.trackAttendance,
          onChanged: disabled
              ? null
              : (value) => update(
                  (plan) => plan.copyWith(
                    trackAttendance: value,
                    allowance: int.tryParse(plan.allowance) == 0
                        ? '12'
                        : plan.allowance,
                  ),
                ),
        ),
        if (p.trackAttendance) ...[
          Text(
            p.coaching
                ? 'Each class reserves the chosen court for its full duration. Ordinary court bookings cannot use it during the class.'
                : 'Each visit reserves the whole court for the player. Ordinary court bookings cannot use it during the visit.',
          ),
          const SizedBox(height: 20),
          ConfigurationField(
            label: p.coaching ? 'Number of classes' : 'Number of play days',
            value: p.allowance,
            numeric: true,
            enabled: !disabled,
            validator: courtInteger,
            onChanged: (v) => update((p) => p.copyWith(allowance: v)),
          ),
          const SizedBox(height: 12),
          Text(
            p.coaching
                ? 'Each class uses one class from the plan.'
                : 'Each attended day uses one play day. Visits use the court minimum duration and can be extended in 30-minute steps.',
          ),
          const SizedBox(height: 20),
        ],
        AppPicker(
          label: 'Plan validity',
          value: p.expiryMode,
          enabled: !disabled,
          items: const [
            PickerItem('after_start', 'Days from activation'),
            PickerItem('after_months', 'Months from activation'),
            PickerItem('after_years', 'Years from activation'),
            PickerItem('fixed_date', 'Fixed expiry date'),
          ],
          onChanged: (v) => update(
            (p) =>
                p.copyWith(expiryMode: v, clearExpiryDate: v != 'fixed_date'),
          ),
        ),
        const SizedBox(height: 16),
        if (p.expiryMode != 'fixed_date')
          ConfigurationField(
            key: ValueKey('court-validity-${p.id}-${p.expiryMode}'),
            label: 'Number of ${p.validityUnit}',
            value: p.validityCount,
            numeric: true,
            enabled: !disabled,
            validator: (v) =>
                int.tryParse(v ?? '') == null ||
                    int.parse(v!) < 1 ||
                    int.parse(v) > p.validityMaximum
                ? 'Enter 1–${p.validityMaximum} ${p.validityUnit}'
                : null,
            onChanged: (v) => update((p) => p.withValidityCount(v)),
          )
        else
          CourtDateButton(
            label: 'Expiry date',
            value: p.expiryDate,
            enabled: !disabled,
            onChanged: (v) => update((p) => p.copyWith(expiryDate: v)),
          ),
        const SizedBox(height: 12),
        const Text(
          'The plan ends when its allowance is used or its expiry is reached. Fixed expiry dates include that day. No automatic renewal.',
        ),
        const SizedBox(height: 20),
        ConfigurationField(
          label: 'Total plan price · ${model.currency}',
          value: p.price,
          numeric: true,
          enabled: !disabled,
          validator: (v) =>
              !p.enabled && (v ?? '').isEmpty ? null : courtPrice(v),
          onChanged: (v) => update((p) => p.copyWith(price: v)),
        ),
        const SizedBox(height: 20),
        if (p.coaching && p.trackAttendance) ...[
          CourtDurationPicker(
            label: 'Duration per class',
            value: p.classDuration,
            enabled: !disabled,
            onChanged: (v) => update((p) => p.copyWith(classDuration: v)),
          ),
          const SizedBox(height: 16),
          ConfigurationField(
            label: 'Maximum students per class',
            value: p.seats,
            numeric: true,
            enabled: !disabled,
            validator: (v) =>
                int.tryParse(v ?? '') == null ||
                    int.parse(v!) < 1 ||
                    int.parse(v) > 500
                ? 'Enter 1–500'
                : null,
            onChanged: (v) => update((p) => p.copyWith(seats: v)),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Coach',
              prefixIcon: Icon(Icons.sports_outlined),
            ),
            child: Text(coachName(p)),
          ),
          if (p.coachId != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: disabled
                    ? null
                    : () => update((p) => p.copyWith(clearCoach: true)),
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Unassign coach'),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Enable Also a coach in Team & access → Edit staff, then assign this plan in their Coaching plans section. Changing this plan’s courts needs a coach assigned to all of them.',
          ),
          const SizedBox(height: 20),
        ],
        if (p.trackAttendance) ...[
          Text(
            p.coaching
                ? 'Coaching days and available times'
                : 'Allowed playing days and times',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          CourtHoursEditor(
            hours: p.hours,
            openingWindows: selectedCourts.map((c) => c.hours.window).toList(),
            allowedDays: commonOpeningDays(
              selectedCourts.map((c) => c.hours.days),
            ),
            enabled: !disabled,
            onChanged: (h) => update((p) => p.copyWith(hours: h)),
          ),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Plan enabled'),
          value: p.enabled,
          onChanged: disabled
              ? null
              : (v) => update((p) => p.copyWith(enabled: v)),
        ),
        TextButton.icon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Remove plan'),
          onPressed: disabled
              ? null
              : () async {
                  if (await confirmAction(
                    context,
                    'Remove ${p.name}?',
                    'This plan definition will be removed. Existing admissions keep their purchased plan.',
                  )) {
                    cubit.removePlan(p.id);
                  }
                },
        ),
      ],
    );
  }
}
