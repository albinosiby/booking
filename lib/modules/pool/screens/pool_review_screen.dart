import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/review_format.dart';
import '../models/pool_configuration.dart';
import '../models/pool_screen_models.dart';

String poolSchedule(PoolHours h) => reviewSchedule(
  days: h.days,
  opens: h.opens,
  closes: h.closes,
  allDay: h.allDay,
  dateFrom: h.dateFrom,
  dateUntil: h.dateUntil,
);

class PoolReviewScreen extends StatelessWidget {
  const PoolReviewScreen({
    super.key,
    required this.model,
    this.businessName = 'Your pools',
    this.onEditPool,
    this.onEditPricing,
    this.onEditOffer,
    this.onEditPlan,
  });
  final PoolReviewModel model;
  final String businessName;
  final ValueChanged<String>? onEditPool,
      onEditPricing,
      onEditOffer,
      onEditPlan;
  @override
  Widget build(BuildContext context) {
    final c = model.configuration;
    String poolNames(List<String> ids) =>
        c.pools.where((p) => ids.contains(p.id)).map((p) => p.name).join(', ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReviewHeader(
          name: businessName,
          summary:
              '${reviewCount(c.pools.where((p) => p.enabled).length, 'pool')} enabled · ${reviewCount(c.offers.where((o) => o.enabled).length, 'group offer')} · ${reviewCount(c.plans.where((p) => p.enabled).length, 'plan')}',
          error: c.validate(complete: true),
        ),
        for (final p in c.pools)
          ReviewSpaceCard(
            name: p.name,
            icon: Icons.pool,
            enabled: p.enabled,
            onEdit: onEditPool == null ? null : () => onEditPool!(p.id),
            subtitle:
                '${p.capacity} people · ${p.minDepth.isEmpty || p.maxDepth.isEmpty ? 'Depth not set' : '${p.minDepth}–${p.maxDepth} ft deep'}',
            children: [
              ReviewDetail(
                label: 'Opening hours',
                value: poolSchedule(p.hours),
                onEdit: onEditPricing == null
                    ? null
                    : () => onEditPricing!(p.id),
              ),
              if (p.regularSwimming && p.enabled) ...[
                const ReviewTag('Price per person'),
                for (final t in p.tariffs)
                  ReviewPricingGroup(
                    schedule: poolSchedule(t.hours),
                    children: [
                      for (final r in t.rates.where(
                        (r) => r.minutes == p.defaultDuration,
                      ))
                        ReviewRate(
                          label: '${r.minutes} min minimum',
                          price: reviewPrice(model.currency, r.price),
                        ),
                    ],
                  ),
                if (p.tariffs.isEmpty)
                  const ReviewNote('No admission prices configured.'),
              ] else if (p.enabled)
                const ReviewTag('Plans & group offers only'),
              if (p.before > 0 || p.after > 0)
                ReviewMore(
                  title: 'Preparation & cleanup',
                  children: [
                    ReviewDetail(
                      label: 'Internal preparation & cleanup',
                      value: '${p.before} min before · ${p.after} min after',
                    ),
                  ],
                ),
            ],
          ),
        if (c.offers.isNotEmpty) ...[
          Text('Group offers', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final o in c.offers)
            ReviewSpaceCard(
              name: o.name,
              icon: Icons.groups_outlined,
              enabled: o.enabled,
              subtitle: poolNames(o.poolIds),
              onEdit: onEditOffer == null ? null : () => onEditOffer!(o.id),
              children: [
                ReviewRate(
                  label: '${o.sizeLabel} · ${o.duration} min',
                  price: '${reviewPrice(model.currency, o.price)} total',
                ),
                ReviewMore(
                  title: 'Offer availability',
                  children: [
                    ReviewDetail(
                      label: 'When this offer applies',
                      value: poolSchedule(o.hours),
                    ),
                  ],
                ),
              ],
            ),
        ],
        if (c.plans.isNotEmpty) ...[
          Text(
            'Swimming & coaching plans',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          for (final p in c.plans)
            ReviewSpaceCard(
              name: p.name,
              icon: p.coaching
                  ? Icons.sports
                  : Icons.confirmation_number_outlined,
              enabled: p.enabled,
              subtitle: poolNames(p.poolIds),
              onEdit: onEditPlan == null ? null : () => onEditPlan!(p.id),
              children: [
                ReviewRate(
                  label:
                      '${p.allowance} ${p.coaching ? 'classes' : 'attendance days'}',
                  price: reviewPrice(model.currency, p.price),
                ),
                ReviewDetail(label: 'Expiry', value: p.validityLabel),
                if (p.coaching)
                  ReviewDetail(label: 'Coach', value: c.coachLabel(p.coachId)),
                ReviewMore(
                  title: 'Plan details',
                  children: [
                    ReviewDetail(
                      label: 'Availability',
                      value: poolSchedule(p.hours),
                    ),
                    if (p.coaching)
                      ReviewDetail(
                        label: 'Coaching',
                        value:
                            '${p.classDuration} min/class · ${p.seats} students/class',
                      ),
                    const ReviewNote(
                      'Attendance allowance and expiry are separate. No automatic renewal.',
                    ),
                  ],
                ),
              ],
            ),
        ],
        const ReviewNote(
          'Regular swimmers, groups and coaching students share each pool’s capacity.',
        ),
        const ReviewNote('Save or Activate applies this configuration online.'),
      ],
    );
  }
}
