import '../../../utils/helpers/pricing_time_bounds.dart';
import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/validation.dart';
import '../../../utils/helpers/time_format.dart';
import '../models/turf_configuration.dart';
import '../models/turf_step_models.dart';
import '../cubit/turf_setup_cubit.dart';
import '../widgets/turf_hours_editor.dart';
import '../widgets/turf_field.dart';
import '../widgets/turf_ground_diagram.dart';

class TurfRulesScreen extends StatelessWidget {
  const TurfRulesScreen({
    super.key,
    required this.model,
    required this.cubit,
    required this.disabled,
  });
  final TurfRulesScreenModel model;
  final TurfSetupCubit cubit;
  final bool disabled;
  List<PickerItem> bufferItems(int current) {
    final values = {
      0,
      5,
      10,
      15,
      20,
      30,
      45,
      60,
      90,
      120,
      180,
      240,
      current,
    }.toList()..sort();
    return values.map((v) => PickerItem('$v', '$v minutes')).toList();
  }

  Widget bandEditor(
    BuildContext context,
    TurfOffering offer,
    TurfPriceBand band,
    int number,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Price rule $number',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Remove price rule',
                onPressed: disabled
                    ? null
                    : () => cubit.removePriceBand(offer.id, band.id),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Applies on'),
          const SizedBox(height: 8),
          AppWeekdayPicker(
            days: band.days,
            allowedDays: (offer.hoursOverride ?? model.hours).days,
            enabled: !disabled,
            onChanged: (days) => cubit.priceBand(offer.id, band.id, days: days),
          ),
          const SizedBox(height: 14),
          AppPricingTimeRange(
            opens: band.opens,
            closes: band.closes,
            allDay: band.allDay,
            bounds: PricingTimeBounds([
              (offer.hoursOverride ?? model.hours).window,
            ], band.days),
            enabled: !disabled,
            onChanged: (opens, closes, allDay) => cubit.priceBand(
              offer.id,
              band.id,
              opens: opens,
              closes: closes,
              allDay: allDay,
            ),
          ),
          if (!band.hours.within(offer.hoursOverride ?? model.hours) ||
              !(offer.hoursOverride ?? model.hours).within(model.hours)) ...[
            const SizedBox(height: 12),
            Text(
              'This space is open ${TimeFormat.display((offer.hoursOverride ?? model.hours).opens)}–${TimeFormat.display((offer.hoursOverride ?? model.hours).closes)}. This price rule runs ${TimeFormat.display(band.opens)}–${TimeFormat.display(band.closes)}. Its days and times must fit the opening hours.',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            if (band.allDay &&
                !(offer.hoursOverride ?? model.hours).allDay) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.all_inclusive_rounded),
                label: const Text('Open this space 24 hours'),
                onPressed: disabled
                    ? null
                    : () => cubit.offeringHours(
                        offer.id,
                        (offer.hoursOverride ?? model.hours).copyWith(
                          allDay: true,
                          opens: '00:00',
                          closes: '00:00',
                        ),
                      ),
              ),
              const Text(
                'Other spaces keep their hours. Linked Cricket follows Football.',
              ),
            ] else if (model.closingExtension(offer, band)
                case final change?) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: ValueKey('extend-closing-${offer.id}-${band.id}'),
                icon: const Icon(Icons.more_time_rounded),
                label: Text(
                  'Extend this space to ${TimeFormat.display(change.offering.closes)}',
                ),
                onPressed: disabled
                    ? null
                    : () => cubit.extendClosingForBand(offer.id, band.id),
              ),
              const SizedBox(height: 6),
              Text(
                model.cricketUsesFootball
                    ? 'Other spaces keep their hours. Linked Cricket follows Football.'
                    : 'Other spaces keep their current opening hours.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
          const SizedBox(height: 16),
          ...band.rates
              .where((r) => r.minutes == offer.defaultDuration)
              .map(
                (rate) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TurfField(
                    key: ValueKey(
                      'band-price-${offer.id}-${band.id}-${rate.minutes}',
                    ),
                    label:
                        '${rate.minutes}-minute booking price · ${model.currency}',
                    value: rate.price,
                    numeric: true,
                    enabled: !disabled,
                    validator: (v) => Validation.priceMinor(v ?? '') == null
                        ? 'Enter a valid booking price'
                        : null,
                    onChanged: (value) =>
                        cubit.bandPrice(offer.id, band.id, rate.minutes, value),
                  ),
                ),
              ),
        ],
      ),
    ),
  );
  Widget offeringEditor(BuildContext context, TurfOffering offer) {
    final durations = {
      30,
      60,
      90,
      120,
      180,
      240,
      ...offer.rates.map((r) => r.minutes),
    }.toList()..sort();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: disabled ? null : cubit.pricingSpaces,
          icon: const Icon(Icons.arrow_back),
          label: const Text('Choose another space'),
        ),
        Text(
          model.spaceName(offer.layoutId),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text('${offer.sport.label} · ${offer.format}'),
        ReviewMore(
          title: 'View ground layout',
          children: [
            TurfGroundDiagram(
              ground: model.grounds.firstWhere(
                (g) => model.layouts.any(
                  (l) => l.id == offer.layoutId && l.groundId == g.id,
                ),
              ),
              sports: [offer.sport],
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          (offer.hoursOverride ?? model.hours).allDay
              ? 'Open 24 hours on the selected days'
              : 'Available ${TimeFormat.display((offer.hoursOverride ?? model.hours).opens)}–${TimeFormat.display((offer.hoursOverride ?? model.hours).closes)} · bookings must finish by closing',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Opening hours',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              TurfHoursEditor(
                hours: offer.hoursOverride ?? model.hours,
                enabled: !disabled,
                onChanged: (hours) => cubit.offeringHours(offer.id, hours),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Minimum booking duration',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              const Text(
                'Longer bookings extend in 15-minute increments at a proportional price.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: durations
                    .map(
                      (minutes) => FilterChip(
                        label: Text('$minutes min'),
                        selected: offer.defaultDuration == minutes,
                        onSelected: disabled
                            ? null
                            : (value) =>
                                  cubit.duration(offer.id, minutes, value),
                      ),
                    )
                    .toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Weekday & time pricing',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        const Text(
          'Set separate rates for weekdays, weekends or any selected days. The booking start time determines its price.',
        ),
        const SizedBox(height: 16),
        ...offer.pricingRules.asMap().entries.map(
          (entry) => bandEditor(context, offer, entry.value, entry.key + 1),
        ),
        AppButton(
          label: 'Add time-based price',
          icon: Icons.add,
          secondary: true,
          onPressed: disabled || offer.pricingRules.length >= 40
              ? null
              : () => cubit.addPriceBand(offer.id),
        ),
        const SizedBox(height: 18),
        if (cubit.canCopyHalf(offer.id))
          TextButton.icon(
            onPressed: disabled ? null : () => cubit.copyToOtherHalf(offer.id),
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copy pricing to the other half'),
          ),
        AppCard(
          padding: const EdgeInsets.all(6),
          child: ExpansionTile(
            key: PageStorageKey('turf-buffers-${offer.id}'),
            title: const Text('Preparation and cleanup (informational)'),
            childrenPadding: const EdgeInsets.all(14),
            children: [
              AppPicker(
                label: 'Preparation before booking',
                items: bufferItems(offer.bufferBefore),
                value: '${offer.bufferBefore}',
                enabled: !disabled,
                onChanged: (v) => cubit.buffers(offer.id, before: int.parse(v)),
              ),
              const SizedBox(height: 12),
              AppPicker(
                label: 'Buffer after booking',
                items: bufferItems(offer.bufferAfter),
                value: '${offer.bufferAfter}',
                enabled: !disabled,
                onChanged: (v) => cubit.buffers(offer.id, after: int.parse(v)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Booking start times without a price rule are unavailable. Rules on the same day cannot overlap.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final offer = model.selectedOffering;
    if (offer != null) return offeringEditor(context, offer);
    final sport = model.sports.contains(model.selectedSport)
        ? model.selectedSport
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Choose a sport', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: model.sports
              .map(
                (s) => ChoiceChip(
                  key: ValueKey('pricing-sport-${s.name}'),
                  avatar: Icon(
                    s == TurfSport.football
                        ? Icons.sports_soccer
                        : Icons.sports_cricket,
                  ),
                  label: Text(s.label),
                  selected: sport == s,
                  onSelected: disabled
                      ? null
                      : (_) => cubit.selectPricingSport(s),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 20),
        if (model.sports.contains(TurfSport.football) &&
            model.sports.contains(TurfSport.cricket)) ...[
          AppCard(
            padding: const EdgeInsets.all(6),
            child: CheckboxListTile(
              key: const ValueKey('use-football-for-cricket'),
              title: const Text('Use the same timing and pricing for Cricket'),
              subtitle: Text(
                model.cricketUsesFootball
                    ? 'Cricket follows Football for each matching space. Uncheck to edit Cricket separately; copied values will be kept.'
                    : model.canUseFootballForCricket
                    ? 'Copy durations, weekday/time prices, opening hours and preparation/cleanup times from each Football space. Later Football edits also update Cricket.'
                    : 'Complete Football timing and pricing for all matching spaces first.',
              ),
              value: model.cricketUsesFootball,
              onChanged:
                  disabled ||
                      (!model.canUseFootballForCricket &&
                          !model.cricketUsesFootball)
                  ? null
                  : (value) => cubit.useFootballForCricket(value!),
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ),
          const SizedBox(height: 20),
        ],
        if (sport == null)
          const AppEmptyState(
            title: 'Select Football or Cricket',
            message:
                'Then choose Half A, Half B or Full Ground to configure its pricing.',
          )
        else ...[
          Text(
            '${sport.label} spaces',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          ...model.offerings.where((o) => o.sport == sport).map((o) {
            final configured =
                validateTurfOffering(o, model.hours, complete: true) == null;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AppCard(
                padding: const EdgeInsets.all(6),
                child: ListTile(
                  key: ValueKey('pricing-space-${o.layoutId}'),
                  title: Text(model.spaceName(o.layoutId)),
                  subtitle: Text(
                    '${o.format} · ${configured ? 'Configured' : 'Set pricing'}',
                  ),
                  trailing: Icon(
                    configured
                        ? Icons.check_circle_outline
                        : Icons.chevron_right,
                    color: configured ? AppColors.lime : null,
                  ),
                  onTap:
                      disabled ||
                          (o.sport == TurfSport.cricket &&
                              model.cricketUsesFootball)
                      ? null
                      : () => cubit.selectPricingOffering(o.id),
                ),
              ),
            );
          }),
        ],
        const SizedBox(height: 18),
        AppCard(
          padding: const EdgeInsets.all(6),
          child: ExpansionTile(
            key: PageStorageKey('turf-shared-hours-${cubit.state.businessId}'),
            title: const Text('Shared opening hours'),
            childrenPadding: const EdgeInsets.all(14),
            children: [
              TurfHoursEditor(
                hours: model.hours,
                enabled: !disabled,
                onChanged: cubit.hours,
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          '${model.offerings.where((o) => validateTurfOffering(o, model.hours, complete: true) == null).length} of ${model.offerings.length} offerings configured',
        ),
      ],
    );
  }
}
