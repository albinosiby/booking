import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../models/turf_step_models.dart';
import '../models/turf_configuration.dart';
import '../../../utils/helpers/review_format.dart';
import '../widgets/football_ground_diagram.dart';
import '../widgets/cricket_ground_diagram.dart';

class TurfReviewScreen extends StatelessWidget {
  const TurfReviewScreen({
    super.key,
    required this.model,
    required this.currency,
    this.businessName = 'Your turf',
    this.onEditGrounds,
    this.onEditOffering,
  });
  final TurfReviewScreenModel model;
  final String currency, businessName;
  final VoidCallback? onEditGrounds;
  final ValueChanged<String>? onEditOffering;
  @override
  Widget build(BuildContext context) {
    final c = model.configuration;
    String schedule(TurfHours h) => reviewSchedule(
      days: h.days,
      opens: h.opens,
      closes: h.closes,
      allDay: h.allDay,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReviewHeader(
          name: businessName,
          summary:
              '${reviewCount(c.grounds.length, 'physical ground')} · ${reviewCount(c.layouts.length, 'bookable space')} · ${c.sports.map((s) => s.label).join(' & ')}',
          error: model.validation,
        ),
        for (final ground in c.grounds)
          ReviewSpaceCard(
            name: ground.name,
            icon: Icons.stadium_outlined,
            onEdit: onEditGrounds,
            subtitle: ground.arrangement == TurfArrangement.split
                ? 'Half A + Half B = Full Ground'
                : 'One independent ground',
            children: [
              for (final sport in c.sports.where(
                (s) => c.offerings.any(
                  (o) =>
                      o.enabled &&
                      o.sport == s &&
                      c.layouts.any(
                        (l) => l.id == o.layoutId && l.groundId == ground.id,
                      ),
                ),
              )) ...[
                const SizedBox(height: 6),
                Text(
                  sport.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                if (sport == TurfSport.football)
                  FootballGroundDiagram(
                    split: ground.arrangement == TurfArrangement.split,
                  )
                else
                  CricketGroundDiagram(
                    split: ground.arrangement == TurfArrangement.split,
                  ),
                const SizedBox(height: 14),
                if (sport == TurfSport.cricket && c.cricketUsesFootball)
                  const ReviewNote(
                    'Uses the same timing and pricing as Football for each matching space.',
                  )
                else
                  for (final layout in c.layouts.where(
                    (l) => l.groundId == ground.id,
                  ))
                    for (final o in c.offerings.where(
                      (o) =>
                          o.layoutId == layout.id &&
                          o.sport == sport &&
                          o.enabled,
                    )) ...[
                      ReviewDetail(
                        label: '${layout.name} · ${o.format}',
                        value: schedule(o.hoursOverride ?? c.operating),
                        onEdit: onEditOffering == null
                            ? null
                            : () => onEditOffering!(o.id),
                      ),
                      for (final band in o.pricingRules)
                        ReviewPricingGroup(
                          schedule: schedule(band.hours),
                          children: [
                            for (final r in band.rates.where(
                              (r) => r.minutes == o.defaultDuration,
                            ))
                              ReviewRate(
                                label: '${r.minutes} min minimum',
                                price: reviewPrice(currency, r.price),
                              ),
                          ],
                        ),
                      if (o.pricingRules.isEmpty)
                        const ReviewNote(
                          'No prices configured for this space.',
                        ),
                      if (o.bufferBefore > 0 || o.bufferAfter > 0)
                        ReviewMore(
                          title: 'Preparation & cleanup',
                          children: [
                            ReviewDetail(
                              label: 'Internal preparation & cleanup',
                              value:
                                  '${o.bufferBefore} min before · ${o.bufferAfter} min after',
                            ),
                          ],
                        ),
                      const SizedBox(height: 16),
                    ],
              ],
            ],
          ),
        ReviewMore(
          title: 'How shared spaces work',
          children: [
            ReviewNote(
              c.grounds.any((g) => g.arrangement == TurfArrangement.split)
                  ? 'Half A and Half B can be booked at the same time. Full Ground occupies both halves. Football and Cricket share the same physical space, so overlapping bookings on that space are blocked.'
                  : 'Each ground is independent. Football and Cricket share the same physical ground, so overlapping bookings on that ground are blocked.',
            ),
          ],
        ),
        const ReviewNote(
          'Save or Activate applies this configuration online. Until then, your draft stays on this device.',
        ),
      ],
    );
  }
}
