import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/review_format.dart';
import '../models/court_configuration.dart';
import '../models/court_screen_models.dart';

String courtSchedule(CourtHours h) => reviewSchedule(
  days: h.days,
  opens: h.opens,
  closes: h.closes,
  allDay: h.allDay,
  dateFrom: h.dateFrom,
  dateUntil: h.dateUntil,
);

class CourtReviewScreen extends StatelessWidget {
  const CourtReviewScreen({
    super.key,
    required this.model,
    this.businessName = 'Your courts',
    this.onEditCourt,
    this.onEditPricing,
  });
  final CourtReviewModel model;
  final String businessName;
  final ValueChanged<String>? onEditCourt, onEditPricing;
  @override
  Widget build(BuildContext context) {
    final c = model.configuration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReviewHeader(
          name: businessName,
          summary:
              '${reviewCount(c.courts.where((p) => p.enabled).length, 'court')} enabled · Each court books independently',
          error: c.validate(complete: true),
        ),
        for (final p in c.courts)
          ReviewSpaceCard(
            name: p.name,
            icon: Icons.sports_tennis,
            enabled: p.enabled,
            subtitle: [
              p.environment,
              if (p.surface.isNotEmpty) p.surface,
            ].join(' · '),
            onEdit: onEditCourt == null ? null : () => onEditCourt!(p.id),
            children: [
              ReviewDetail(
                label: 'Opening hours',
                value: courtSchedule(p.hours),
                onEdit: onEditPricing == null
                    ? null
                    : () => onEditPricing!(p.id),
              ),
              if (p.enabled) ...[
                const ReviewTag('Price per court'),
                for (final t in p.tariffs)
                  ReviewPricingGroup(
                    schedule: courtSchedule(t.hours),
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
                  const ReviewNote('No prices configured.'),
              ],
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
        const ReviewNote(
          'Prices follow the booking start time. Seasonal prices take priority on their selected dates.',
        ),
        const ReviewNote('Save or Activate applies this configuration online.'),
      ],
    );
  }
}
