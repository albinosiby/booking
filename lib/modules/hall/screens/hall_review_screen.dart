import 'package:flutter/material.dart';
import 'package:eden_booking/design_system/design_system.dart';
import '../../../utils/helpers/review_format.dart';
import '../models/hall_configuration.dart';
import '../models/hall_screen_models.dart';

String hallSchedule(HallHours h) => reviewSchedule(
  days: h.days,
  opens: h.opens,
  closes: h.closes,
  dateFrom: h.dateFrom,
  dateUntil: h.dateUntil,
);

class HallReviewScreen extends StatelessWidget {
  const HallReviewScreen({
    super.key,
    required this.model,
    this.businessName = 'Your halls',
    this.onEditHall,
    this.onEditPricing,
  });
  final HallReviewModel model;
  final String businessName;
  final ValueChanged<String>? onEditHall, onEditPricing;
  @override
  Widget build(BuildContext context) {
    final c = model.configuration;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReviewHeader(
          name: businessName,
          summary:
              '${reviewCount(c.halls.where((p) => p.enabled).length, 'hall')} enabled · Separate prices for every booking option',
          error: c.validate(complete: true),
        ),
        for (final p in c.halls)
          ReviewSpaceCard(
            name: p.name,
            icon: Icons.celebration_outlined,
            enabled: p.enabled,
            subtitle: '${p.capacity} maximum guests · ${p.seated} seated',
            onEdit: onEditHall == null ? null : () => onEditHall!(p.id),
            children: [
              ReviewDetail(
                label: 'Opening hours',
                value: hallSchedule(p.hours),
                onEdit: onEditPricing == null
                    ? null
                    : () => onEditPricing!(p.id),
              ),
              if (p.hourlyEnabled) ...[
                const ReviewTag('Hourly · price per hall', active: true),
                for (final t in p.tariffs)
                  ReviewPricingGroup(
                    schedule: hallSchedule(t.hours),
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
                  const ReviewNote('No hourly prices configured.'),
                const SizedBox(height: 14),
              ],
              for (final o in [
                ...p.sessions,
                p.fullDay,
              ].where((o) => o.enabled)) ...[
                ReviewTag(o.name, active: true),
                const SizedBox(height: 8),
                ReviewDetail(
                  label: 'Session time',
                  value: hallSchedule(o.hours),
                ),
                for (final r in o.prices)
                  ReviewPricingGroup(
                    schedule:
                        '${reviewDays(r.days)}${r.dateFrom == null ? '' : ' · ${r.dateFrom} → ${r.dateUntil}'}',
                    children: [
                      ReviewRate(
                        label: 'Package total',
                        price: reviewPrice(model.currency, r.price),
                      ),
                    ],
                  ),
                if (o.prices.isEmpty)
                  const ReviewNote('No package prices configured.'),
                const SizedBox(height: 14),
              ],
              ReviewMore(
                title: 'Hall details & unavailable options',
                children: [
                  ReviewDetail(label: 'Environment', value: p.environment),
                  if (p.amenities.isNotEmpty)
                    ReviewDetail(label: 'Amenities', value: p.amenities),
                  ReviewDetail(
                    label: 'Preparation & cleanup',
                    value: '${p.before} min before · ${p.after} min after',
                  ),
                  if (!p.hourlyEnabled)
                    const ReviewDetail(
                      label: 'Hourly bookings',
                      value: 'Not offered',
                    ),
                  for (final o in [
                    ...p.sessions,
                    p.fullDay,
                  ].where((o) => !o.enabled))
                    ReviewDetail(label: o.name, value: 'Not offered'),
                ],
              ),
            ],
          ),
        const ReviewNote(
          'Hourly bookings, sessions and full-day packages share the same hall. Overlapping bookings are blocked.',
        ),
        const ReviewNote('Save or Activate applies this configuration online.'),
      ],
    );
  }
}
