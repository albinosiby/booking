import '../../../utils/helpers/pricing_time_bounds.dart';
import '../../../utils/helpers/pricing_days.dart';
import '../../../utils/helpers/operating_window.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/models/workspace.dart';
import 'court_coaching.dart';
export 'court_coaching.dart';

int courtMinute(String value) =>
    int.parse(value.split(':')[0]) * 60 + int.parse(value.split(':')[1]);
bool courtDateValid(String value) {
  final parsed = DateTime.tryParse(value);
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      parsed != null &&
      parsed.toIso8601String().startsWith(value);
}

String courtMoney(dynamic value) =>
    value == null ? '' : ((value as num) / 100).toStringAsFixed(2);

class CourtHours extends Equatable {
  CourtHours({
    Iterable<int> days = const [1, 2, 3, 4, 5, 6, 7],
    this.opens = '06:00',
    this.closes = '23:00',
    this.allDay = false,
    this.dateFrom,
    this.dateUntil,
  }) : days = List.unmodifiable(days);
  final List<int> days;
  final String opens, closes;
  final bool allDay;
  final String? dateFrom, dateUntil;
  int get span =>
      allDay ? 1440 : (courtMinute(closes) - courtMinute(opens) + 1440) % 1440;
  bool get dated => dateFrom != null;
  CourtHours copyWith({
    Iterable<int>? days,
    String? opens,
    String? closes,
    bool? allDay,
    String? dateFrom,
    String? dateUntil,
    bool clearDates = false,
  }) => CourtHours(
    days: days ?? this.days,
    opens: opens ?? this.opens,
    closes: closes ?? this.closes,
    allDay: allDay ?? this.allDay,
    dateFrom: clearDates ? null : dateFrom ?? this.dateFrom,
    dateUntil: clearDates ? null : dateUntil ?? this.dateUntil,
  );
  String? validate() {
    if (days.isEmpty ||
        days.toSet().length != days.length ||
        days.any((d) => d < 1 || d > 7) ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(opens) ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(closes) ||
        (allDay ? opens != '00:00' || closes != '00:00' : opens == closes)) {
      return 'Choose weekdays and valid hours. For 24 hours use midnight boundaries.';
    }
    if ((dateFrom == null) != (dateUntil == null) ||
        (dated &&
            (!courtDateValid(dateFrom!) ||
                !courtDateValid(dateUntil!) ||
                dateFrom!.compareTo(dateUntil!) > 0))) {
      return 'Choose a valid start and end date.';
    }
    return null;
  }

  OperatingWindow get window => OperatingWindow(
    days: days,
    opens: opens,
    closes: closes,
    allDay: allDay,
    dateFrom: dateFrom,
    dateUntil: dateUntil,
  );
  bool within(CourtHours parent) =>
      validate() == null &&
      parent.validate() == null &&
      window.within(parent.window);
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'days': [...days]..sort(),
    'opens_at': opens,
    'closes_at': closes,
    if (allDay) 'all_day': true,
    'date_from': dateFrom,
    'date_until': dateUntil,
  };
  factory CourtHours.fromJson(Map<String, dynamic> v) => CourtHours(
    days: List<int>.from(v['days']),
    opens: v['opens_at'],
    closes: v['closes_at'],
    allDay: v['all_day'] == true,
    dateFrom: v['date_from'],
    dateUntil: v['date_until'],
  );
  @override
  List<Object?> get props => [days, opens, closes, allDay, dateFrom, dateUntil];
}

class CourtRate extends Equatable {
  const CourtRate(this.minutes, this.price);
  final int minutes;
  final String price;
  int? get minor => Validation.priceMinor(price);
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft) '_local': {'price': price},
    'duration_minutes': minutes,
    'price_minor': minor,
  };
  factory CourtRate.fromJson(Map<String, dynamic> v) => CourtRate(
    v['duration_minutes'],
    v['_local']?['price'] ?? courtMoney(v['price_minor']),
  );
  @override
  List<Object?> get props => [minutes, price];
}

class CourtTariff extends Equatable {
  CourtTariff({
    required this.id,
    required this.hours,
    required Iterable<CourtRate> rates,
  }) : rates = List.unmodifiable(rates);
  final String id;
  final CourtHours hours;
  final List<CourtRate> rates;
  CourtTariff copyWith({
    String? id,
    CourtHours? hours,
    Iterable<CourtRate>? rates,
  }) => CourtTariff(
    id: id ?? this.id,
    hours: hours ?? this.hours,
    rates: rates ?? this.rates,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'id': id,
    'hours': hours.toJson(localDraft: localDraft),
    'rates': rates.map((r) => r.toJson(localDraft: localDraft)).toList(),
  };
  factory CourtTariff.fromJson(Map<String, dynamic> v) => CourtTariff(
    id: v['id'],
    hours: CourtHours.fromJson(Map<String, dynamic>.from(v['hours'])),
    rates: (v['rates'] as List).map(
      (r) => CourtRate.fromJson(Map<String, dynamic>.from(r)),
    ),
  );
  @override
  List<Object?> get props => [id, hours, rates];
}

class CourtResource extends Equatable {
  CourtResource({
    required this.id,
    required this.name,
    this.enabled = true,
    this.environment = 'unspecified',
    this.surface = '',
    CourtHours? hours,
    Iterable<int> durations = const [60],
    this.defaultDuration = 60,
    this.before = 0,
    this.after = 5,
    Iterable<CourtTariff> tariffs = const [],
  }) : hours = hours ?? CourtHours(),
       durations = List.unmodifiable(durations),
       tariffs = List.unmodifiable(tariffs);
  final String id, name;
  final String environment, surface;
  final bool enabled;
  final CourtHours hours;
  final List<int> durations;
  final int defaultDuration, before, after;
  final List<CourtTariff> tariffs;
  String? validateDetails({bool complete = false}) {
    if (name.trim().length < 2 ||
        name.trim().length > 100 ||
        !['unspecified', 'indoor', 'outdoor'].contains(environment) ||
        surface.trim().length > 80) {
      return 'Check court name, location type and surface.';
    }
    return null;
  }

  CourtResource copyWith({
    String? name,
    bool? enabled,
    String? environment,
    String? surface,
    CourtHours? hours,
    Iterable<int>? durations,
    int? defaultDuration,
    int? before,
    int? after,
    Iterable<CourtTariff>? tariffs,
  }) => CourtResource(
    id: id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    environment: environment ?? this.environment,
    surface: surface ?? this.surface,
    hours: hours ?? this.hours,
    durations: durations ?? this.durations,
    defaultDuration: defaultDuration ?? this.defaultDuration,
    before: before ?? this.before,
    after: after ?? this.after,
    tariffs: tariffs ?? this.tariffs,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft) '_local': {'name': name},
    'id': id,
    'name': name.trim(),
    'enabled': enabled,
    'environment': environment,
    'surface': surface.trim(),
    'operating': hours.toJson(localDraft: localDraft),
    'durations': durations,
    'default_duration_minutes': defaultDuration,
    'buffer_before': before,
    'buffer_after': after,
    'pricing_basis': 'start_time',
    'tariffs': tariffs.map((t) => t.toJson(localDraft: localDraft)).toList(),
  };
  factory CourtResource.fromJson(Map<String, dynamic> v) => CourtResource(
    id: v['id'],
    name: v['_local'] is Map && (v['_local'] as Map).containsKey('name')
        ? v['_local']['name']
        : v['name'],
    enabled: v['enabled'],
    environment: v['environment'],
    surface: v['surface'],
    hours: CourtHours.fromJson(Map<String, dynamic>.from(v['operating'])),
    durations: List<int>.from(v['durations']),
    defaultDuration: v['default_duration_minutes'],
    before: v['buffer_before'],
    after: v['buffer_after'] ?? 5,
    tariffs: (v['tariffs'] as List).map(
      (t) => CourtTariff.fromJson(Map<String, dynamic>.from(t)),
    ),
  );
  @override
  List<Object?> get props => [
    id,
    name,
    enabled,
    environment,
    surface,
    hours,
    durations,
    defaultDuration,
    before,
    after,
    tariffs,
  ];
}

class CourtConfiguration extends Equatable {
  CourtConfiguration followOpeningTimes(CourtConfiguration previous) =>
      copyWith(
        courts: courts.map((p) {
          final old = previous.courts.where((v) => v.id == p.id).firstOrNull;
          if (old == null ||
              sameOpeningTimes(old.hours.window, p.hours.window)) {
            return p;
          }
          return p.copyWith(
            tariffs: p.tariffs.map((t) {
              final before = old.tariffs.where((v) => v.id == t.id).firstOrNull;
              if (before == null ||
                  !sameOpeningTimes(before.hours.window, old.hours.window) ||
                  !sameOpeningTimes(before.hours.window, t.hours.window)) {
                return t;
              }
              return t.copyWith(
                hours: t.hours.copyWith(
                  opens: p.hours.opens,
                  closes: p.hours.closes,
                  allDay: p.hours.allDay,
                ),
              );
            }),
          );
        }),
      );

  CourtConfiguration restrictPricingDays() => copyWith(
    courts: courts.map(
      (p) => p.copyWith(
        tariffs: p.tariffs.map(
          (t) => t.copyWith(
            hours: t.hours.copyWith(
              days: pricingDays(t.hours.days, p.hours.days),
            ),
          ),
        ),
      ),
    ),
  );

  CourtConfiguration({
    Iterable<CourtResource> courts = const [],
    Iterable<CourtPlan> plans = const [],
  }) : courts = List.unmodifiable(courts),
       plans = List.unmodifiable(plans);

  final List<CourtResource> courts;
  final List<CourtPlan> plans;
  CourtConfiguration copyWith({
    Iterable<CourtResource>? courts,
    Iterable<CourtPlan>? plans,
  }) => CourtConfiguration(
    courts: courts ?? this.courts,
    plans: plans ?? this.plans,
  );

  /// Removes references to a deleted court from plans and coach contacts.
  /// A plan left without courts also loses its coach.
  CourtConfiguration withoutCourt(String id) => copyWith(
    courts: courts.where((c) => c.id != id),
    plans: plans.map(
      (p) => p.copyWith(
        courtIds: p.courtIds.where((v) => v != id),
        clearCoach: !p.courtIds.any((v) => v != id),
      ),
    ),
  );
  // Optional keys are omitted when empty so older APIs keep accepting saves.
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'kind': 'court_v1',
    'schema_version': 1,
    'courts': courts.map((p) => p.toJson(localDraft: localDraft)).toList(),
    if (plans.isNotEmpty)
      'plans': plans.map((p) => p.toJson(localDraft: localDraft)).toList(),
  };
  factory CourtConfiguration.fromJson(Map<String, dynamic> v) {
    // Coach contacts were replaced by team coaches; their plans are
    // Unassigned until a team coach takes them.
    final contacts = {
      for (final c in v['coaches'] as List? ?? const []) (c as Map)['id'],
    };
    return CourtConfiguration(
      courts: (v['courts'] as List).map(
        (p) => CourtResource.fromJson(Map<String, dynamic>.from(p)),
      ),
      plans: ((v['plans'] as List?) ?? const []).map((p) {
        final plan = CourtPlan.fromJson(Map<String, dynamic>.from(p));
        return contacts.contains(plan.coachId)
            ? plan.copyWith(clearCoach: true)
            : plan;
      }),
    );
  }
  factory CourtConfiguration.initial(Business? b) {
    if (b?.configuration?['kind'] == 'court_v1') {
      return CourtConfiguration.fromJson(b!.configuration!);
    }
    final old = b?.configuration;
    final hours = old == null
        ? CourtHours()
        : CourtHours(
            days: List<int>.from(old['days']),
            opens: old['opens_at'],
            closes: old['closes_at'],
          );
    final duration = (old?['duration_minutes'] as int?) ?? 60;
    return CourtConfiguration(
      courts: (b?.resources ?? []).map(
        (r) => CourtResource(
          id: r.id,
          name: r.name,
          hours: hours,
          durations: [duration],
          defaultDuration: duration,
          before: old?['buffer_minutes'] ?? 0,
          tariffs: old == null
              ? []
              : [
                  CourtTariff(
                    id: const Uuid().v4(),
                    hours: hours,
                    rates: [
                      CourtRate(duration, courtMoney(old['price_minor'])),
                    ],
                  ),
                ],
        ),
      ),
    );
  }
  String? validate({bool complete = false, String? today}) {
    if (courts.length > 50) return 'Use at most 50 courts per business.';
    if (plans.length > 50) return 'Use at most 50 coaching plans.';
    final ids = [...courts.map((c) => c.id), ...plans.map((p) => p.id)];
    if (ids.toSet().length != ids.length) {
      return 'Use unique court and plan identifiers.';
    }
    if (courts.map((p) => p.id).toSet().length != courts.length ||
        courts.map((p) => p.name.trim().toLowerCase()).toSet().length !=
            courts.length) {
      return 'Use unique court names and identifiers.';
    }
    if (complete && !courts.any((p) => p.enabled)) {
      return 'Enable at least one court.';
    }
    for (final p in courts) {
      final detailsError = p.validateDetails(complete: complete);
      if (detailsError != null) return detailsError;
      final err = p.hours.validate();
      if (err != null) return '${p.name}: $err';
      if (p.hours.dated ||
          p.durations.isEmpty ||
          p.durations.length > 10 ||
          p.durations.toSet().length != p.durations.length ||
          !p.durations.contains(p.defaultDuration) ||
          p.durations.any((d) => d < 30 || d > 1440) ||
          p.before < 0 ||
          p.before > 240 ||
          p.after < 0 ||
          p.after > 240) {
        return 'Check durations and preparation/cleanup times for ${p.name}.';
      }
      if (p.tariffs.length > 40 ||
          p.tariffs.map((t) => t.id).toSet().length != p.tariffs.length) {
        return 'Use distinct price rules, up to 40 per court.';
      }
      for (final t in p.tariffs) {
        final err = t.hours.validate();
        if (err != null) return err;
        if (p.enabled && !t.hours.within(p.hours)) {
          return 'Keep price rules within ${p.name} opening hours.';
        }
        if (t.rates.length != p.durations.length ||
            t.rates.map((r) => r.minutes).toSet().length != t.rates.length ||
            t.rates.any(
              (r) =>
                  !p.durations.contains(r.minutes) ||
                  (r.price.isNotEmpty && r.minor == null),
            )) {
          return 'Enter valid prices for every allowed duration.';
        }
        if (complete &&
            p.enabled &&
            t.rates.any(
              (r) => r.minutes == p.defaultDuration && r.minor == null,
            )) {
          return 'Complete prices for ${p.name}.';
        }
      }
      for (var i = 0; i < p.tariffs.length; i++) {
        for (var j = i + 1; j < p.tariffs.length; j++) {
          final a = p.tariffs[i].hours, b = p.tariffs[j].hours;
          final x =
                  (courtMinute(a.opens) - courtMinute(p.hours.opens) + 1440) %
                  1440,
              y =
                  (courtMinute(b.opens) - courtMinute(p.hours.opens) + 1440) %
                  1440;
          final dates =
              a.dated == b.dated &&
              (!a.dated ||
                  (a.dateFrom!.compareTo(b.dateUntil!) <= 0 &&
                      b.dateFrom!.compareTo(a.dateUntil!) <= 0));
          if (a.dated == b.dated &&
              (p.hours.allDay
                  ? a.window.overlaps(b.window)
                  : dates &&
                        a.days.any(b.days.contains) &&
                        x < y + b.span &&
                        y < x + a.span)) {
            return 'Price rules overlap for ${p.name}.';
          }
        }
      }
      if (complete &&
          p.enabled &&
          (p.tariffs.isEmpty ||
              p.durations
                  .where((d) => d == p.defaultDuration)
                  .any((d) => !p.hours.allDay && d > p.hours.span))) {
        return 'Complete prices and valid durations for ${p.name}.';
      }
    }
    for (final p in plans) {
      final error = p.validate(courts, complete: complete, today: today);
      if (error != null) return error;
    }
    return null;
  }

  @override
  List<Object?> get props => [courts, plans];
}
