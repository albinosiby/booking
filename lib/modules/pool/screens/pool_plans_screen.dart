import '../../../utils/helpers/pricing_days.dart';
import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/pool_screen_models.dart';
import '../models/pool_configuration.dart';
import '../cubit/pool_setup_cubit.dart';
import '../widgets/pool_editors.dart';

class PoolPlansScreen extends StatelessWidget {
  const PoolPlansScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
    required this.coaching,
  });
  final PoolPlansModel model;
  final PoolSetupCubit cubit;
  final bool disabled, coaching;
  @override
  Widget build(BuildContext context) {
    final p = model.selected;
    if (p == null && !model.pools.any((p) => p.enabled)) {
      return Column(
        children: [
          const AppEmptyState(
            title: 'Add a pool first',
            message: 'Plans need at least one enabled pool.',
          ),
          AppButton(
            label: 'Configure pools',
            onPressed: disabled ? null : () => cubit.open(PoolSection.pools),
          ),
        ],
      );
    }
    if (p == null) {
      return PoolItemList(
        items: model.plans
            .map(
              (p) => (
                p.id,
                p.name,
                '${p.allowance} ${coaching ? 'classes' : 'attendance days'} · ${p.validityLabel} · ${model.currency} ${p.price.isEmpty ? 'not set' : p.price}${p.enabled ? '' : ' · disabled'}',
              ),
            )
            .toList(),
        addLabel: coaching ? 'Add coaching plan' : 'Add swimming plan',
        add: model.pools.any((p) => p.enabled) && model.totalPlanCount < 50
            ? () => cubit.addPlan(coaching)
            : null,
        select: (id) => cubit.open(
          coaching ? PoolSection.coaching : PoolSection.plans,
          id: id,
        ),
        enabled: !disabled,
      );
    }
    void update(PoolPlan Function(PoolPlan) change) =>
        cubit.updatePlan(p.id, change);
    final assignedCoach = model.coaches
        .where((c) => c.id == p.coachId)
        .firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConfigurationField(
          label: coaching ? 'Coaching plan name' : 'Swimming plan name',
          value: p.name,
          enabled: !disabled,
          validator: poolName,
          onChanged: (v) => update((p) => p.copyWith(name: v)),
        ),
        const SizedBox(height: 16),
        PoolEligibilityEditor(
          pools: model.pools,
          selected: p.poolIds,
          enabled: !disabled,
          onChanged: (ids) => update((p) => p.copyWith(poolIds: ids)),
        ),
        const SizedBox(height: 16),
        if (!coaching) ...[
          Text(
            'Attendance allowance',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          ActionChip(
            label: const Text('Use 25 attendance days'),
            onPressed: disabled
                ? null
                : () => update((p) => p.copyWith(allowance: '25')),
          ),
          const SizedBox(height: 12),
        ],
        ConfigurationField(
          label: coaching
              ? 'Number of classes'
              : 'Attendance days · custom count',
          value: p.allowance,
          numeric: true,
          enabled: !disabled,
          validator: poolInteger,
          onChanged: (v) => update((p) => p.copyWith(allowance: v)),
        ),
        const SizedBox(height: 12),
        Text(
          coaching
              ? 'Each attended class uses one class from the plan.'
              : 'Multiple visits on the same day use one attendance day. Buying a plan does not reserve a time slot.',
        ),
        const SizedBox(height: 20),
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
            key: ValueKey('validity-${p.id}-${p.expiryMode}'),
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
          PoolDateButton(
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
              !p.enabled && (v ?? '').isEmpty ? null : poolPrice(v),
          onChanged: (v) => update((p) => p.copyWith(price: v)),
        ),
        const SizedBox(height: 20),
        if (coaching) ...[
          PoolDurationPicker(
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
            validator: poolInteger,
            onChanged: (v) => update((p) => p.copyWith(seats: v)),
          ),
          const SizedBox(height: 16),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Coach',
              prefixIcon: Icon(Icons.sports_outlined),
            ),
            child: Text(
              p.coachId == null
                  ? 'Unassigned'
                  : assignedCoach?.name ?? 'Assigned coach',
            ),
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
            'Add coaches and assign them to this plan from Team management → Coaches. Changing this plan’s pools needs a coach assigned to all of them.',
          ),
          const SizedBox(height: 12),
          const Text(
            'Coaching students share the pool capacity. Class reservations and attendance will be managed in the booking module.',
          ),
          const SizedBox(height: 20),
        ],
        Text(
          coaching
              ? 'Coaching days and available times'
              : 'Allowed swimming days and times',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        PoolHoursEditor(
          hours: p.hours,
          openingWindows: model.pools
              .where((pool) => p.poolIds.contains(pool.id))
              .map((pool) => pool.hours.window)
              .toList(),
          allowedDays: commonOpeningDays(
            model.pools
                .where((pool) => p.poolIds.contains(pool.id))
                .map((pool) => pool.hours.days),
          ),
          enabled: !disabled,
          onChanged: (h) => update((p) => p.copyWith(hours: h)),
        ),
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
                    'This plan definition will be removed.',
                  )) {
                    cubit.removePlan(p.id);
                  }
                },
        ),
      ],
    );
  }
}
