import '../../court/models/court_configuration.dart';
import '../../pool/models/pool_configuration.dart';
import '../../hall/models/hall_configuration.dart';
import '../../turf/models/turf_configuration.dart';
import '../../workspace/models/workspace.dart';
import '../../../utils/helpers/review_format.dart';
import '../models/business_detail_model.dart';

typedef Field = BusinessDetailField;
String _label(String value) => value.isEmpty || value == 'unspecified'
    ? 'Not specified'
    : value[0].toUpperCase() + value.substring(1).replaceAll('_', ' ');
List<Field> _booking(int defaultDuration, int before, int after) => [
  Field('Minimum booking duration', '$defaultDuration min'),
  const Field(
    'Longer bookings',
    '15-minute increments; proportional start-time rate',
  ),
  Field('Preparation & cleanup', '$before min before · $after min after'),
  const Field('Pricing basis', 'Booking start time'),
];
String _courtHours(CourtHours h) => reviewSchedule(
  days: h.days,
  opens: h.opens,
  closes: h.closes,
  allDay: h.allDay,
  dateFrom: h.dateFrom,
  dateUntil: h.dateUntil,
);
String _poolHours(PoolHours h) => reviewSchedule(
  days: h.days,
  opens: h.opens,
  closes: h.closes,
  allDay: h.allDay,
  dateFrom: h.dateFrom,
  dateUntil: h.dateUntil,
);
String _hallHours(HallHours h) => reviewSchedule(
  days: h.days,
  opens: h.opens,
  closes: h.closes,
  dateFrom: h.dateFrom,
  dateUntil: h.dateUntil,
);
String _turfHours(TurfHours h) => reviewSchedule(
  days: h.days,
  opens: h.opens,
  closes: h.closes,
  allDay: h.allDay,
);

/// Maps saved configuration to read-only presentation data. Never adopts setup
/// defaults: an absent or unsupported configuration must not invent live prices.
BusinessDetailSummary describeBusiness(Business business, String currency) {
  final json = business.configuration;
  try {
    switch (json?['kind']) {
      case 'court_v1':
        final c = CourtConfiguration.fromJson(json!);
        return BusinessDetailSummary(
          spaceCount: c.courts.length,
          enabledCount: c.courts.where((p) => p.enabled).length,
          sections: [
            BusinessDetailSection('Courts & pricing', [
              for (final p in c.courts)
                BusinessDetailEntry(
                  id: p.id,
                  name: p.name,
                  subtitle: [
                    _label(p.environment),
                    if (p.surface.isNotEmpty) p.surface,
                  ].join(' · '),
                  enabled: p.enabled,
                  fields: [
                    Field('Opening hours', _courtHours(p.hours)),
                    Field('Environment', _label(p.environment)),
                    Field(
                      'Surface',
                      p.surface.isEmpty ? 'Not specified' : p.surface,
                    ),
                    ..._booking(p.defaultDuration, p.before, p.after),
                    const Field('Price unit', 'Per court'),
                  ],
                  prices: [
                    for (final t in p.tariffs)
                      BusinessPriceGroup(_courtHours(t.hours), [
                        for (final r in t.rates.where(
                          (r) => r.minutes == p.defaultDuration,
                        ))
                          Field(
                            '${r.minutes} min',
                            reviewPrice(currency, r.price),
                          ),
                      ]),
                  ],
                ),
            ]),
          ],
        );
      case 'pool_v1':
        final c = PoolConfiguration.fromJson(json!);
        String pools(List<String> ids) => c.pools
            .where((p) => ids.contains(p.id))
            .map((p) => p.name)
            .join(', ');
        return BusinessDetailSummary(
          spaceCount: c.pools.length,
          enabledCount: c.pools.where((p) => p.enabled).length,
          sections: [
            BusinessDetailSection('Pools & admission prices', [
              for (final p in c.pools)
                BusinessDetailEntry(
                  id: p.id,
                  name: p.name,
                  subtitle: 'Capacity ${p.capacity} people',
                  enabled: p.enabled,
                  fields: [
                    Field('Opening hours', _poolHours(p.hours)),
                    Field('Capacity', '${p.capacity} people'),
                    Field(
                      'Depth',
                      '${p.minDepth.isEmpty ? 'Not set' : '${p.minDepth} ft'} – ${p.maxDepth.isEmpty ? 'Not set' : '${p.maxDepth} ft'}',
                    ),
                    Field(
                      'Regular swimming',
                      p.regularSwimming
                          ? 'Available · price per person'
                          : 'Plans & group offers only',
                    ),
                    ..._booking(p.defaultDuration, p.before, p.after),
                  ],
                  prices: [
                    for (final t in p.tariffs)
                      BusinessPriceGroup(_poolHours(t.hours), [
                        for (final r in t.rates.where(
                          (r) => r.minutes == p.defaultDuration,
                        ))
                          Field(
                            '${r.minutes} min / person',
                            reviewPrice(currency, r.price),
                          ),
                      ]),
                  ],
                ),
            ]),
            if (c.offers.isNotEmpty)
              BusinessDetailSection('Group offers', [
                for (final o in c.offers)
                  BusinessDetailEntry(
                    id: o.id,
                    name: o.name,
                    subtitle: pools(o.poolIds),
                    enabled: o.enabled,
                    fields: [
                      Field('Pools', pools(o.poolIds)),
                      Field('Group size', o.sizeLabel),
                      Field('Duration', '${o.duration} min'),
                      Field('Availability', _poolHours(o.hours)),
                      Field('Total price', reviewPrice(currency, o.price)),
                    ],
                  ),
              ]),
            if (c.plans.isNotEmpty)
              BusinessDetailSection('Swimming & coaching plans', [
                for (final p in c.plans)
                  BusinessDetailEntry(
                    id: p.id,
                    name: p.name,
                    subtitle: p.coaching ? 'Coaching plan' : 'Swimming plan',
                    enabled: p.enabled,
                    fields: [
                      Field('Pools', pools(p.poolIds)),
                      Field(
                        'Allowance',
                        '${p.allowance} ${p.coaching ? 'classes' : 'attendance days'}',
                      ),
                      Field('Expiry', p.validityLabel),
                      Field('Availability', _poolHours(p.hours)),
                      if (p.coaching) ...[
                        Field('Class duration', '${p.classDuration} min'),
                        Field('Class capacity', '${p.seats} students'),
                        Field(
                          'Coach assignment',
                          p.coachId == null ? 'Not assigned' : 'Assigned',
                        ),
                      ],
                      Field('Plan price', reviewPrice(currency, p.price)),
                      const Field('Renewal', 'No automatic renewal'),
                    ],
                  ),
              ]),
          ],
        );
      case 'hall_v1':
        final c = HallConfiguration.fromJson(json!);
        return BusinessDetailSummary(
          spaceCount: c.halls.length,
          enabledCount: c.halls.where((p) => p.enabled).length,
          sections: [
            BusinessDetailSection('Halls & booking options', [
              for (final p in c.halls)
                BusinessDetailEntry(
                  id: p.id,
                  name: p.name,
                  subtitle: '${p.capacity} maximum guests · ${p.seated} seated',
                  enabled: p.enabled,
                  fields: [
                    Field('Opening hours', _hallHours(p.hours)),
                    Field('Maximum guests', p.capacity),
                    Field('Seated capacity', p.seated),
                    Field('Environment', _label(p.environment)),
                    Field(
                      'Amenities',
                      p.amenities.isEmpty ? 'Not specified' : p.amenities,
                    ),
                    Field(
                      'Hourly bookings',
                      p.hourlyEnabled
                          ? 'Available · price per hall'
                          : 'Not offered',
                    ),
                    ..._booking(p.defaultDuration, p.before, p.after),
                    for (final o in [...p.sessions, p.fullDay])
                      Field(
                        o.name,
                        o.enabled ? _hallHours(o.hours) : 'Not offered',
                      ),
                  ],
                  prices: [
                    for (final t in p.tariffs)
                      BusinessPriceGroup('Hourly · ${_hallHours(t.hours)}', [
                        for (final r in t.rates.where(
                          (r) => r.minutes == p.defaultDuration,
                        ))
                          Field(
                            '${r.minutes} min',
                            reviewPrice(currency, r.price),
                          ),
                      ]),
                    for (final o in [...p.sessions, p.fullDay])
                      for (final r in o.prices)
                        BusinessPriceGroup(
                          '${o.name}${o.enabled ? '' : ' · Not offered'} · ${reviewDays(r.days)}${r.dateFrom == null ? '' : ' · ${r.dateFrom} → ${r.dateUntil}'}',
                          [
                            Field(
                              'Package total',
                              reviewPrice(currency, r.price),
                            ),
                          ],
                        ),
                  ],
                ),
            ]),
          ],
        );
      case 'turf_v1':
        final c = TurfConfiguration.fromJson(json!);
        return BusinessDetailSummary(
          spaceCount: c.layouts.length,
          enabledCount: c.layouts
              .where(
                (l) => c.offerings.any((o) => o.layoutId == l.id && o.enabled),
              )
              .length,
          sections: [
            BusinessDetailSection('Grounds & shared spaces', [
              for (final g in c.grounds)
                BusinessDetailEntry(
                  id: g.id,
                  name: g.name,
                  subtitle: g.arrangement == TurfArrangement.split
                      ? 'Half A + Half B = Full Ground'
                      : 'Independent ground',
                  fields: [
                    Field('Sports', c.sports.map((s) => s.label).join(' · ')),
                    Field('Opening hours', _turfHours(c.operating)),
                    Field(
                      'Bookable spaces',
                      c.layouts
                          .where((l) => l.groundId == g.id)
                          .map((l) => l.name)
                          .join(', '),
                    ),
                    Field(
                      'Shared availability',
                      g.arrangement == TurfArrangement.split
                          ? 'Full Ground occupies both halves. Football and Cricket share availability.'
                          : 'Sports on this ground share availability.',
                    ),
                  ],
                ),
            ]),
            BusinessDetailSection('Sports, booking options & prices', [
              for (final o in c.offerings)
                BusinessDetailEntry(
                  id: o.id,
                  name: o.name,
                  subtitle: '${o.sport.label} · ${o.format}',
                  enabled: o.enabled,
                  fields: [
                    Field(
                      'Space',
                      c.layouts
                              .where((l) => l.id == o.layoutId)
                              .firstOrNull
                              ?.name ??
                          'Not available',
                    ),
                    Field(
                      'Ground',
                      c.grounds
                              .where(
                                (g) => c.layouts.any(
                                  (l) =>
                                      l.id == o.layoutId && l.groundId == g.id,
                                ),
                              )
                              .firstOrNull
                              ?.name ??
                          'Not available',
                    ),
                    Field('Sport', o.sport.label),
                    Field('Format', o.format),
                    Field(
                      'Opening hours',
                      _turfHours(o.hoursOverride ?? c.operating),
                    ),
                    ..._booking(
                      o.defaultDuration,
                      o.bufferBefore,
                      o.bufferAfter,
                    ),
                    const Field('Price unit', 'Per space'),
                    if (o.sport == TurfSport.cricket && c.cricketUsesFootball)
                      const Field(
                        'Linked pricing',
                        'Uses matching Football timing and prices',
                      ),
                  ],
                  prices: [
                    for (final t in o.pricingRules)
                      BusinessPriceGroup(_turfHours(t.hours), [
                        for (final r in t.rates.where(
                          (r) => r.minutes == o.defaultDuration,
                        ))
                          Field(
                            '${r.minutes} min',
                            reviewPrice(currency, r.price),
                          ),
                      ]),
                  ],
                ),
            ]),
          ],
        );
    }
  } on FormatException {
    return _fallback(business, invalid: true);
  } on TypeError {
    return _fallback(business, invalid: true);
  } on ArgumentError {
    return _fallback(business, invalid: true);
  }
  return _fallback(business);
}

BusinessDetailSummary _fallback(
  Business b, {
  bool invalid = false,
}) => BusinessDetailSummary(
  spaceCount: b.resources.length,
  notice: invalid
      ? 'Some saved setup details could not be displayed. Open configuration to review them.'
      : 'Open configuration to review or complete operating hours, prices and booking options.',
  sections: [
    BusinessDetailSection('Spaces', [
      for (final p in b.resources)
        BusinessDetailEntry(
          id: p.id,
          name: p.name,
          subtitle: 'Configured space',
          fields: [Field('Capacity', '${p.capacity}')],
        ),
    ]),
  ],
);
