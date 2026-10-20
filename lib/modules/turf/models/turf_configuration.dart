import '../../../utils/helpers/pricing_time_bounds.dart';
import '../../../utils/helpers/pricing_days.dart';
import '../../../utils/helpers/operating_window.dart';
import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/helpers/validation.dart';
import '../../../utils/helpers/time_format.dart';
import '../../workspace/models/workspace.dart';

enum TurfSport {
  football,
  cricket;

  String get label => this == football ? 'Football' : 'Cricket';
}

enum TurfArrangement { split, single }

class TurfHours extends Equatable {
  TurfHours({
    this.opens = '06:00',
    this.closes = '23:00',
    this.allDay = false,
    Iterable<int> days = const [1, 2, 3, 4, 5, 6, 7],
  }) : days = List.unmodifiable(days);
  final String opens, closes;
  final bool allDay;
  final List<int> days;
  TurfHours copyWith({
    String? opens,
    String? closes,
    bool? allDay,
    Iterable<int>? days,
  }) => TurfHours(
    opens: opens ?? this.opens,
    closes: closes ?? this.closes,
    allDay: allDay ?? this.allDay,
    days: days ?? this.days,
  );
  bool get validTimes =>
      allDay ? opens == '00:00' && closes == '00:00' : opens != closes;
  int get spanMinutes {
    if (allDay) return 1440;
    int minute(String time) =>
        int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3));
    return (minute(closes) - minute(opens) + 1440) % 1440;
  }

  OperatingWindow get window =>
      OperatingWindow(days: days, opens: opens, closes: closes, allDay: allDay);
  bool within(TurfHours parent) =>
      validTimes && parent.validTimes && window.within(parent.window);
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'opens_at': opens,
    'closes_at': closes,
    if (allDay) 'all_day': true,
    'days': [...days]..sort(),
  };
  factory TurfHours.fromJson(Map<String, dynamic> v) => TurfHours(
    opens: v['opens_at'],
    closes: v['closes_at'],
    allDay: v['all_day'] == true,
    days: List<int>.from(v['days']),
  );
  @override
  List<Object?> get props => [opens, closes, allDay, days];
}

/// Proposes a closing-only extension. Weekdays and opening times stay intact.
/// Offsets are anchored to opening, so midnight and overnight periods compare correctly.
({TurfHours operating, TurfHours offering})? turfClosingExtension(
  TurfHours operating,
  TurfHours offering,
  TurfHours required,
) {
  TurfHours? extend(TurfHours current, TurfHours needed) {
    if (needed.within(current)) return current;
    if (current.spanMinutes == 0 ||
        needed.spanMinutes == 0 ||
        !needed.days.every(current.days.contains)) {
      return null;
    }
    final start =
        (turfMinute(needed.opens) - turfMinute(current.opens) + 1440) % 1440;
    final end = start + needed.spanMinutes;
    if (start >= current.spanMinutes ||
        end <= current.spanMinutes ||
        end >= 1440) {
      return null;
    }
    return current.copyWith(closes: needed.closes);
  }

  final updated = extend(offering, required);
  if (updated == null) return null;
  final shared = extend(operating, updated);
  if (shared == null || (updated == offering && shared == operating)) {
    return null;
  }
  return (operating: shared, offering: updated);
}

class TurfSection extends Equatable {
  const TurfSection(this.id, this.name);
  final String id, name;
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'id': id,
    'name': name,
  };
  factory TurfSection.fromJson(Map<String, dynamic> v) =>
      TurfSection(v['id'], v['name']);
  @override
  List<Object?> get props => [id, name];
}

class TurfGround extends Equatable {
  TurfGround({
    required this.id,
    required this.name,
    required this.arrangement,
    required Iterable<TurfSection> sections,
  }) : sections = List.unmodifiable(sections);
  final String id, name;
  final TurfArrangement arrangement;
  final List<TurfSection> sections;
  TurfGround withName(String name) => TurfGround(
    id: id,
    name: name,
    arrangement: arrangement,
    sections: sections,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'id': id,
    'name': name,
    'arrangement': arrangement.name,
    'sections': sections.map((s) => s.toJson(localDraft: localDraft)).toList(),
  };
  factory TurfGround.fromJson(Map<String, dynamic> v) => TurfGround(
    id: v['id'],
    name: v['name'],
    arrangement: TurfArrangement.values.byName(v['arrangement']),
    sections: (v['sections'] as List).map(
      (s) => TurfSection.fromJson(Map<String, dynamic>.from(s)),
    ),
  );
  @override
  List<Object?> get props => [id, name, arrangement, sections];
}

class TurfLayout extends Equatable {
  TurfLayout({
    required this.id,
    required this.groundId,
    required this.name,
    required Iterable<String> sectionIds,
  }) : sectionIds = List.unmodifiable(sectionIds);
  final String id, groundId, name;
  final List<String> sectionIds;
  TurfLayout withName(String name) => TurfLayout(
    id: id,
    groundId: groundId,
    name: name,
    sectionIds: sectionIds,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'id': id,
    'ground_id': groundId,
    'name': name,
    'section_ids': sectionIds,
  };
  factory TurfLayout.fromJson(Map<String, dynamic> v) => TurfLayout(
    id: v['id'],
    groundId: v['ground_id'],
    name: v['name'],
    sectionIds: List<String>.from(v['section_ids']),
  );
  @override
  List<Object?> get props => [id, groundId, name, sectionIds];
}

class TurfRate extends Equatable {
  const TurfRate(this.minutes, this.price);
  final int minutes;

  /// Preserve input while editing; the persistence boundary writes integer minor units.
  final String price;
  int? get minor => Validation.priceMinor(price);
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft) '_local': {'price': price},
    'duration_minutes': minutes,
    'price_minor': minor,
  };
  factory TurfRate.fromJson(Map<String, dynamic> v) => TurfRate(
    v['duration_minutes'],
    v['_local']?['price'] ??
        (v['price_minor'] == null
            ? ''
            : ((v['price_minor'] as num) / 100).toStringAsFixed(2)),
  );
  @override
  List<Object?> get props => [minutes, price];
}

class TurfPriceBand extends Equatable {
  TurfPriceBand({
    required this.id,
    required Iterable<int> days,
    required this.opens,
    required this.closes,
    this.allDay = false,
    required Iterable<TurfRate> rates,
  }) : days = List.unmodifiable(days),
       rates = List.unmodifiable(rates);
  final String id, opens, closes;
  final bool allDay;
  final List<int> days;
  final List<TurfRate> rates;
  TurfPriceBand copyWith({
    Iterable<int>? days,
    String? opens,
    String? closes,
    bool? allDay,
    Iterable<TurfRate>? rates,
    String? id,
  }) => TurfPriceBand(
    id: id ?? this.id,
    days: days ?? this.days,
    opens: opens ?? this.opens,
    closes: closes ?? this.closes,
    allDay: allDay ?? this.allDay,
    rates: rates ?? this.rates,
  );
  TurfHours get hours =>
      TurfHours(opens: opens, closes: closes, days: days, allDay: allDay);
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'id': id,
    'days': [...days]..sort(),
    'starts_at': opens,
    'ends_at': closes,
    if (allDay) 'all_day': true,
    'rates': rates.map((r) => r.toJson(localDraft: localDraft)).toList(),
  };
  factory TurfPriceBand.fromJson(Map<String, dynamic> value) => TurfPriceBand(
    id: value['id'],
    days: List<int>.from(value['days']),
    opens: value['starts_at'],
    closes: value['ends_at'],
    allDay: value['all_day'] == true,
    rates: (value['rates'] as List).map(
      (r) => TurfRate.fromJson(Map<String, dynamic>.from(r)),
    ),
  );
  @override
  List<Object?> get props => [id, days, opens, closes, allDay, rates];
}

int turfMinute(String time) =>
    int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3));
String? validateTurfOffering(
  TurfOffering offer,
  TurfHours operating, {
  bool complete = false,
}) {
  final hours = offer.hoursOverride ?? operating;
  if (!offer.rates.any((rate) => rate.minutes == offer.defaultDuration)) {
    return 'Choose an allowed default duration for ${offer.name}.';
  }
  if (complete && offer.enabled && offer.pricingRules.isEmpty) {
    return 'Add a weekday/time price rule for ${offer.name}.';
  }
  if (offer.enabled &&
      (hours.days.isEmpty || !hours.validTimes || !hours.within(operating))) {
    return 'Check the opening hours for ${offer.name}.';
  }
  if (complete &&
      offer.enabled &&
      offer.rates
          .where((r) => r.minutes == offer.defaultDuration)
          .any((rate) => !hours.allDay && rate.minutes > hours.spanMinutes)) {
    return 'Booking duration must fit ${offer.name} opening hours.';
  }
  final intervals = <({TurfPriceBand band, int start, int end})>[];
  for (final band in offer.pricingRules) {
    if (band.days.isEmpty ||
        !band.hours.validTimes ||
        (offer.enabled && !band.hours.within(hours))) {
      return '${offer.name} is open ${TimeFormat.display(hours.opens)}–${TimeFormat.display(hours.closes)}. This price rule is ${TimeFormat.display(band.opens)}–${TimeFormat.display(band.closes)}. Keep its days and times within opening hours or extend the opening hours.';
    }
    if (band.rates.map((r) => r.minutes).toSet().length != offer.rates.length ||
        !offer.rates.every(
          (r) => band.rates.any((b) => b.minutes == r.minutes),
        )) {
      return 'Enter prices for each allowed duration in ${offer.name}.';
    }
    if (band.rates.any((r) => r.price.trim().isNotEmpty && r.minor == null)) {
      return 'Use valid prices with at most two decimal places.';
    }
    if (complete &&
        offer.enabled &&
        band.rates.any(
          (r) => r.minutes == offer.defaultDuration && r.minor == null,
        )) {
      return 'Enter all time-band prices for ${offer.name}.';
    }
    final start =
        (turfMinute(band.opens) - turfMinute(hours.opens) + 1440) % 1440;
    for (final previous in intervals) {
      if (hours.allDay
          ? band.hours.window.overlaps(previous.band.hours.window)
          : band.days.any(previous.band.days.contains) &&
                start < previous.end &&
                previous.start < start + band.hours.spanMinutes) {
        return 'Pricing rules overlap for ${offer.name}. Use separate days or time ranges.';
      }
    }
    intervals.add((
      band: band,
      start: start,
      end: start + band.hours.spanMinutes,
    ));
  }
  return null;
}

class TurfOffering extends Equatable {
  TurfOffering({
    required this.id,
    required this.layoutId,
    required this.sport,
    required this.name,
    required this.format,
    this.enabled = true,
    Iterable<TurfRate> rates = const [TurfRate(60, '')],
    this.bufferBefore = 0,
    this.bufferAfter = 5,
    this.hoursOverride,
    int? defaultDuration,
    Iterable<TurfPriceBand> pricingRules = const [],
  }) : rates = List.unmodifiable(rates),
       defaultDuration = defaultDuration ?? rates.first.minutes,
       pricingRules = List.unmodifiable(pricingRules);
  final String id, layoutId, name, format;
  final TurfSport sport;
  final bool enabled;
  final List<TurfRate> rates;
  final List<TurfPriceBand> pricingRules;
  final int defaultDuration;
  final int bufferBefore, bufferAfter;
  final TurfHours? hoursOverride;
  TurfOffering copyWith({
    String? name,
    String? format,
    bool? enabled,
    Iterable<TurfRate>? rates,
    int? bufferBefore,
    int? bufferAfter,
    TurfHours? hoursOverride,
    bool clearOverride = false,
    Iterable<TurfPriceBand>? pricingRules,
    int? defaultDuration,
  }) => TurfOffering(
    id: id,
    layoutId: layoutId,
    sport: sport,
    name: name ?? this.name,
    format: format ?? this.format,
    enabled: enabled ?? this.enabled,
    rates: rates ?? this.rates,
    bufferBefore: bufferBefore ?? this.bufferBefore,
    bufferAfter: bufferAfter ?? this.bufferAfter,
    hoursOverride: clearOverride ? null : hoursOverride ?? this.hoursOverride,
    pricingRules: pricingRules ?? this.pricingRules,
    defaultDuration: defaultDuration ?? this.defaultDuration,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'id': id,
    'layout_id': layoutId,
    'sport': sport.name,
    'name': name,
    'format': format,
    'enabled': enabled,
    'rates': rates.map((r) => r.toJson(localDraft: localDraft)).toList(),
    'pricing_rules': pricingRules
        .map((b) => b.toJson(localDraft: localDraft))
        .toList(),
    'pricing_basis': 'start_time',
    'default_duration_minutes': defaultDuration,
    'buffer_before': bufferBefore,
    'buffer_after': bufferAfter,
    'hours_override': hoursOverride?.toJson(localDraft: localDraft),
  };
  Map<String, dynamic> get timingAndPricing => {
    'rates': rates.map((r) => r.toJson()).toList(),
    'default_duration_minutes': defaultDuration,
    'buffer_before': bufferBefore,
    'buffer_after': bufferAfter,
    'hours_override': hoursOverride?.toJson(),
    'pricing_rules': pricingRules.map((band) {
      final json = band.toJson()..remove('id');
      return json;
    }).toList(),
  };
  bool sameTimingAndPricing(TurfOffering other) =>
      jsonEncode(timingAndPricing) == jsonEncode(other.timingAndPricing);

  factory TurfOffering.fromJson(Map<String, dynamic> v) => TurfOffering(
    id: v['id'],
    layoutId: v['layout_id'],
    sport: TurfSport.values.byName(v['sport']),
    name: v['name'],
    format: v['format'],
    enabled: v['enabled'],
    rates: (v['rates'] as List).map(
      (r) => TurfRate.fromJson(Map<String, dynamic>.from(r)),
    ),
    pricingRules: (v['pricing_rules'] as List? ?? []).map(
      (b) => TurfPriceBand.fromJson(Map<String, dynamic>.from(b)),
    ),
    defaultDuration: v['default_duration_minutes'],
    bufferBefore: v['buffer_before'],
    bufferAfter: v['buffer_after'] ?? 5,
    hoursOverride: v['hours_override'] == null
        ? null
        : TurfHours.fromJson(Map<String, dynamic>.from(v['hours_override'])),
  );
  @override
  List<Object?> get props => [
    id,
    layoutId,
    sport,
    name,
    format,
    enabled,
    rates,
    bufferBefore,
    bufferAfter,
    hoursOverride,
    pricingRules,
    defaultDuration,
  ];
}

class TurfConfiguration extends Equatable {
  TurfConfiguration followOpeningTimes(TurfConfiguration previous) => copyWith(
    offerings: offerings.map((o) {
      final old = previous.offerings.where((v) => v.id == o.id).firstOrNull;
      if (old == null) return o;
      final beforeHours = old.hoursOverride ?? previous.operating;
      final afterHours = o.hoursOverride ?? operating;
      if (sameOpeningTimes(beforeHours.window, afterHours.window)) return o;
      return o.copyWith(
        pricingRules: o.pricingRules.map((band) {
          final before = old.pricingRules
              .where((v) => v.id == band.id)
              .firstOrNull;
          if (before == null ||
              !sameOpeningTimes(before.hours.window, beforeHours.window) ||
              !sameOpeningTimes(before.hours.window, band.hours.window)) {
            return band;
          }
          return band.copyWith(
            opens: afterHours.opens,
            closes: afterHours.closes,
            allDay: afterHours.allDay,
          );
        }),
      );
    }),
  );

  TurfConfiguration restrictPricingDays() => copyWith(
    offerings: offerings.map((o) {
      final override = o.hoursOverride?.copyWith(
        days: pricingDays(o.hoursOverride!.days, operating.days),
      );
      final allowed = (override ?? operating).days;
      return o.copyWith(
        hoursOverride: override,
        pricingRules: o.pricingRules.map(
          (b) => b.copyWith(days: pricingDays(b.days, allowed)),
        ),
      );
    }),
  );

  TurfConfiguration({
    this.cricketUsesFootball = false,
    required Iterable<TurfSport> sports,
    required Iterable<TurfGround> grounds,
    required Iterable<TurfLayout> layouts,
    required Iterable<TurfOffering> offerings,
    TurfHours? operating,
  }) : sports = List.unmodifiable(sports),
       grounds = List.unmodifiable(grounds),
       layouts = List.unmodifiable(layouts),
       offerings = List.unmodifiable(offerings),
       operating = operating ?? TurfHours();
  final bool cricketUsesFootball;
  final List<TurfSport> sports;
  final List<TurfGround> grounds;
  final List<TurfLayout> layouts;
  final List<TurfOffering> offerings;
  final TurfHours operating;
  TurfConfiguration copyWith({
    bool? cricketUsesFootball,
    Iterable<TurfSport>? sports,
    Iterable<TurfGround>? grounds,
    Iterable<TurfLayout>? layouts,
    Iterable<TurfOffering>? offerings,
    TurfHours? operating,
  }) => TurfConfiguration(
    cricketUsesFootball: cricketUsesFootball ?? this.cricketUsesFootball,
    sports: sports ?? this.sports,
    grounds: grounds ?? this.grounds,
    layouts: layouts ?? this.layouts,
    offerings: offerings ?? this.offerings,
    operating: operating ?? this.operating,
  );
  bool get hasMatchingFootballSpaces {
    final football = offerings
        .where((o) => o.enabled && o.sport == TurfSport.football)
        .toList();
    final cricket = offerings
        .where((o) => o.enabled && o.sport == TurfSport.cricket)
        .toList();
    return sports.contains(TurfSport.football) &&
        sports.contains(TurfSport.cricket) &&
        football.isNotEmpty &&
        cricket.isNotEmpty &&
        cricket.every((c) => football.any((f) => f.layoutId == c.layoutId));
  }

  bool get footballPricingComplete =>
      hasMatchingFootballSpaces &&
      offerings
          .where((o) => o.enabled && o.sport == TurfSport.football)
          .every(
            (o) => validateTurfOffering(o, operating, complete: true) == null,
          );

  TurfConfiguration synchronizeCricket() {
    if (!cricketUsesFootball) return this;
    if (!hasMatchingFootballSpaces) return copyWith(cricketUsesFootball: false);
    return copyWith(
      offerings: offerings.map((target) {
        if (!target.enabled || target.sport != TurfSport.cricket) return target;
        final source = offerings.firstWhere(
          (o) =>
              o.enabled &&
              o.sport == TurfSport.football &&
              o.layoutId == target.layoutId,
        );
        if (source.sameTimingAndPricing(target)) return target;
        return target.copyWith(
          rates: source.rates,
          defaultDuration: source.defaultDuration,
          bufferBefore: source.bufferBefore,
          bufferAfter: source.bufferAfter,
          hoursOverride: source.hoursOverride,
          clearOverride: source.hoursOverride == null,
          pricingRules: source.pricingRules.indexed.map(
            (entry) => entry.$2.copyWith(
              id: entry.$1 < target.pricingRules.length
                  ? target.pricingRules[entry.$1].id
                  : const Uuid().v4(),
            ),
          ),
        );
      }),
    );
  }

  bool overlaps(String left, String right) {
    final a = layouts.firstWhere((l) => l.id == left),
        b = layouts.firstWhere((l) => l.id == right);
    return a.groundId == b.groundId && a.sectionIds.any(b.sectionIds.contains);
  }

  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'kind': 'turf_v1',
    'cricket_uses_football': cricketUsesFootball,
    'schema_version': 1,
    'sports': sports.map((s) => s.name).toList(),
    'grounds': grounds.map((g) => g.toJson(localDraft: localDraft)).toList(),
    'layouts': layouts.map((l) => l.toJson(localDraft: localDraft)).toList(),
    'offerings': offerings
        .map((o) => o.toJson(localDraft: localDraft))
        .toList(),
    'operating': operating.toJson(localDraft: localDraft),
  };
  factory TurfConfiguration.fromJson(Map<String, dynamic> value) {
    final hours = TurfHours.fromJson(
      Map<String, dynamic>.from(value['operating']),
    );
    final offers = (value['offerings'] as List).map((item) {
      final json = Map<String, dynamic>.from(item);
      var offer = TurfOffering.fromJson(json);
      if (!json.containsKey('pricing_rules')) {
        final effective = offer.hoursOverride ?? hours;
        offer = offer.copyWith(
          pricingRules: [
            TurfPriceBand(
              id: const Uuid().v5(
                '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
                'turf-tariff:${offer.id}',
              ),
              days: effective.days,
              opens: effective.opens,
              closes: effective.closes,
              allDay: effective.allDay,
              rates: offer.rates,
            ),
          ],
        );
      }
      return offer;
    });
    return TurfConfiguration(
      cricketUsesFootball: value['cricket_uses_football'] ?? false,
      sports: (value['sports'] as List).map((s) => TurfSport.values.byName(s)),
      grounds: (value['grounds'] as List).map(
        (g) => TurfGround.fromJson(Map<String, dynamic>.from(g)),
      ),
      layouts: (value['layouts'] as List).map(
        (l) => TurfLayout.fromJson(Map<String, dynamic>.from(l)),
      ),
      offerings: offers,
      operating: hours,
    );
  }

  /// Each legacy resource stays independent; importing never invents shared occupancy.
  factory TurfConfiguration.initial(Business? business) {
    if (business?.configuration?['kind'] == 'turf_v1') {
      return TurfConfiguration.fromJson(business!.configuration!);
    }
    var config = TurfConfiguration(
      sports: TurfSport.values,
      grounds: [],
      layouts: [],
      offerings: [],
    );
    if (business?.resources.isNotEmpty ?? false) {
      for (final resource in business!.resources) {
        config = config.addGround(
          resource.name,
          TurfArrangement.single,
          existingLayoutId: resource.id,
        );
      }
    } else {
      config = config.addGround('Main Ground', TurfArrangement.split);
    }
    final legacy = business?.configuration;
    if (legacy != null &&
        legacy['opens_at'] is String &&
        legacy['closes_at'] is String &&
        legacy['days'] is List) {
      config = config.copyWith(operating: TurfHours.fromJson(legacy));
    }
    return config;
  }
  TurfConfiguration addGround(
    String name,
    TurfArrangement arrangement, {
    String? groundId,
    String? existingLayoutId,
  }) {
    const uuid = Uuid();
    final sections = [
      TurfSection(uuid.v4(), 'Section A'),
      if (arrangement == TurfArrangement.split)
        TurfSection(uuid.v4(), 'Section B'),
    ];
    final ground = TurfGround(
      id: groundId ?? uuid.v4(),
      name: name,
      arrangement: arrangement,
      sections: sections,
    );
    final prefix = name.length > 75 ? name.substring(0, 75) : name;
    final spaces = arrangement == TurfArrangement.split
        ? [
            TurfLayout(
              id: uuid.v4(),
              groundId: ground.id,
              name: '$prefix · Half A',
              sectionIds: [sections[0].id],
            ),
            TurfLayout(
              id: uuid.v4(),
              groundId: ground.id,
              name: '$prefix · Half B',
              sectionIds: [sections[1].id],
            ),
            TurfLayout(
              id: uuid.v4(),
              groundId: ground.id,
              name: '$prefix · Full Ground',
              sectionIds: sections.map((s) => s.id),
            ),
          ]
        : [
            TurfLayout(
              id: existingLayoutId ?? uuid.v4(),
              groundId: ground.id,
              name: existingLayoutId == null ? '$prefix · Full Ground' : name,
              sectionIds: [sections[0].id],
            ),
          ];
    final offers = spaces.expand(
      (layout) => TurfSport.values.map(
        (sport) => TurfOffering(
          id: uuid.v4(),
          layoutId: layout.id,
          sport: sport,
          name:
              '${sport.label} · ${layout.sectionIds.length == 2
                  ? 'Full Ground'
                  : arrangement == TurfArrangement.split
                  ? (layout == spaces.first ? 'Half A' : 'Half B')
                  : 'Ground'}',
          format:
              sport == TurfSport.football &&
                  arrangement == TurfArrangement.split
              ? (layout.sectionIds.length == 2 ? '7s' : '5s')
              : (layout.sectionIds.length == 2
                    ? 'Full ground'
                    : arrangement == TurfArrangement.split
                    ? 'Half ground'
                    : 'Full ground'),
          enabled: sports.contains(sport),
        ),
      ),
    );
    return copyWith(
      grounds: [...grounds, ground],
      layouts: [...layouts, ...spaces],
      offerings: [...offerings, ...offers],
    );
  }

  String? validate({bool complete = false}) {
    if (cricketUsesFootball &&
        (!hasMatchingFootballSpaces ||
            offerings
                .where((o) => o.enabled && o.sport == TurfSport.cricket)
                .any(
                  (c) => !c.sameTimingAndPricing(
                    offerings.firstWhere(
                      (f) =>
                          f.enabled &&
                          f.sport == TurfSport.football &&
                          f.layoutId == c.layoutId,
                    ),
                  ),
                ))) {
      return 'Linked Cricket settings must match Football for each space.';
    }
    if (grounds.isEmpty ||
        grounds.any(
          (g) => g.name.trim().length < 2 || g.name.trim().length > 100,
        )) {
      return 'Enter a ground name between 2 and 100 characters.';
    }
    if (layouts.any(
          (l) => l.name.trim().length < 2 || l.name.trim().length > 100,
        ) ||
        layouts.map((l) => l.name.trim().toLowerCase()).toSet().length !=
            layouts.length) {
      return 'Give every bookable space a distinct name, using 2–100 characters.';
    }
    if (operating.days.isEmpty || !operating.validTimes) {
      return 'Choose operating days and different opening and closing times.';
    }
    for (final offer in offerings) {
      if (offer.name.trim().length < 2 ||
          offer.name.trim().length > 100 ||
          offer.format.trim().length < 2 ||
          offer.format.trim().length > 40) {
        return 'Enter valid offering names and format labels.';
      }
      if (offer.rates.any(
        (r) => r.price.trim().isNotEmpty && r.minor == null,
      )) {
        return 'Use valid prices with at most two decimal places.';
      }
      final hours = offer.hoursOverride;
      if (hours != null && (hours.days.isEmpty || !hours.validTimes)) {
        return 'Check the operating hours override for ${offer.name}.';
      }
      if (offer.enabled && hours != null && !hours.within(operating)) {
        return 'Keep ${offer.name} hours within the shared opening days and hours.';
      }
      if (complete &&
          offer.enabled &&
          offer.rates
              .where((r) => r.minutes == offer.defaultDuration)
              .any(
                (r) =>
                    !(hours ?? operating).allDay &&
                    r.minutes > (hours ?? operating).spanMinutes,
              )) {
        return 'Booking duration must fit the operating hours for ${offer.name}.';
      }
      final tariffError = validateTurfOffering(
        offer,
        operating,
        complete: complete,
      );
      if (tariffError != null) return tariffError;
    }
    if (complete &&
        (sports.isEmpty ||
            layouts.any(
              (l) => !offerings.any((o) => o.layoutId == l.id && o.enabled),
            ) ||
            sports.any(
              (s) => !offerings.any((o) => o.sport == s && o.enabled),
            ))) {
      return 'Select sports and enable at least one offering for every space.';
    }
    return null;
  }

  @override
  List<Object?> get props => [
    sports,
    grounds,
    layouts,
    offerings,
    operating,
    cricketUsesFootball,
  ];
}
