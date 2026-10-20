import '../../../utils/helpers/pricing_time_bounds.dart';
import '../../../utils/helpers/operating_window.dart';
import '../../../utils/helpers/pricing_days.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/models/workspace.dart';

int hallMinute(String value) =>
    int.parse(value.split(':')[0]) * 60 + int.parse(value.split(':')[1]);
bool hallDateValid(String value) {
  final parsed = DateTime.tryParse(value);
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      parsed != null &&
      parsed.toIso8601String().startsWith(value);
}

String hallMoney(dynamic value) =>
    value == null ? '' : ((value as num) / 100).toStringAsFixed(2);

class HallHours extends Equatable {
  HallHours({
    Iterable<int> days = const [1, 2, 3, 4, 5, 6, 7],
    this.opens = '06:00',
    this.closes = '23:00',
    this.dateFrom,
    this.dateUntil,
  }) : days = List.unmodifiable(days);
  final List<int> days;
  final String opens, closes;
  final String? dateFrom, dateUntil;
  int get span => (hallMinute(closes) - hallMinute(opens) + 1440) % 1440;
  bool get dated => dateFrom != null;
  HallHours copyWith({
    Iterable<int>? days,
    String? opens,
    String? closes,
    String? dateFrom,
    String? dateUntil,
    bool clearDates = false,
  }) => HallHours(
    days: days ?? this.days,
    opens: opens ?? this.opens,
    closes: closes ?? this.closes,
    dateFrom: clearDates ? null : dateFrom ?? this.dateFrom,
    dateUntil: clearDates ? null : dateUntil ?? this.dateUntil,
  );
  String? validate() {
    if (days.isEmpty ||
        days.toSet().length != days.length ||
        days.any((d) => d < 1 || d > 7) ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(opens) ||
        !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(closes) ||
        opens == closes) {
      return 'Choose weekdays and different opening/closing times.';
    }
    if ((dateFrom == null) != (dateUntil == null) ||
        (dated &&
            (!hallDateValid(dateFrom!) ||
                !hallDateValid(dateUntil!) ||
                dateFrom!.compareTo(dateUntil!) > 0))) {
      return 'Choose a valid start and end date.';
    }
    return null;
  }

  OperatingWindow get window =>
      OperatingWindow(days: days, opens: opens, closes: closes, allDay: false);
  bool within(HallHours other) =>
      validate() == null &&
      other.validate() == null &&
      days.every(other.days.contains) &&
      ((hallMinute(opens) - hallMinute(other.opens) + 1440) % 1440) + span <=
          other.span;
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'days': [...days]..sort(),
    'opens_at': opens,
    'closes_at': closes,
    'date_from': dateFrom,
    'date_until': dateUntil,
  };
  factory HallHours.fromJson(Map<String, dynamic> v) => HallHours(
    days: List<int>.from(v['days']),
    opens: v['opens_at'],
    closes: v['closes_at'],
    dateFrom: v['date_from'],
    dateUntil: v['date_until'],
  );
  @override
  List<Object?> get props => [days, opens, closes, dateFrom, dateUntil];
}

class HallRate extends Equatable {
  const HallRate(this.minutes, this.price);
  final int minutes;
  final String price;
  int? get minor => Validation.priceMinor(price);
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft) '_local': {'price': price},
    'duration_minutes': minutes,
    'price_minor': minor,
  };
  factory HallRate.fromJson(Map<String, dynamic> v) => HallRate(
    v['duration_minutes'],
    v['_local']?['price'] ?? hallMoney(v['price_minor']),
  );
  @override
  List<Object?> get props => [minutes, price];
}

class HallTariff extends Equatable {
  HallTariff({
    required this.id,
    required this.hours,
    required Iterable<HallRate> rates,
  }) : rates = List.unmodifiable(rates);
  final String id;
  final HallHours hours;
  final List<HallRate> rates;
  HallTariff copyWith({
    String? id,
    HallHours? hours,
    Iterable<HallRate>? rates,
  }) => HallTariff(
    id: id ?? this.id,
    hours: hours ?? this.hours,
    rates: rates ?? this.rates,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'id': id,
    'hours': hours.toJson(localDraft: localDraft),
    'rates': rates.map((r) => r.toJson(localDraft: localDraft)).toList(),
  };
  factory HallTariff.fromJson(Map<String, dynamic> v) => HallTariff(
    id: v['id'],
    hours: HallHours.fromJson(Map<String, dynamic>.from(v['hours'])),
    rates: (v['rates'] as List).map(
      (r) => HallRate.fromJson(Map<String, dynamic>.from(r)),
    ),
  );
  @override
  List<Object?> get props => [id, hours, rates];
}

class HallPackagePrice extends Equatable {
  HallPackagePrice({
    required this.id,
    Iterable<int> days = const [1, 2, 3, 4, 5, 6, 7],
    this.dateFrom,
    this.dateUntil,
    this.price = '',
  }) : days = List.unmodifiable(days);
  final String id, price;
  final List<int> days;
  final String? dateFrom, dateUntil;
  HallHours get window =>
      HallHours(days: days, dateFrom: dateFrom, dateUntil: dateUntil);
  HallPackagePrice copyWith({String? id, String? price, HallHours? window}) =>
      HallPackagePrice(
        id: id ?? this.id,
        price: price ?? this.price,
        days: window?.days ?? days,
        dateFrom: window == null ? dateFrom : window.dateFrom,
        dateUntil: window == null ? dateUntil : window.dateUntil,
      );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft) '_local': {'price': price},
    'id': id,
    'days': days,
    'date_from': dateFrom,
    'date_until': dateUntil,
    'price_minor': Validation.priceMinor(price),
  };
  factory HallPackagePrice.fromJson(Map<String, dynamic> v) => HallPackagePrice(
    id: v['id'],
    days: List<int>.from(v['days']),
    dateFrom: v['date_from'],
    dateUntil: v['date_until'],
    price: v['_local'] is Map && (v['_local'] as Map).containsKey('price')
        ? v['_local']['price']
        : hallMoney(v['price_minor']),
  );
  @override
  List<Object?> get props => [id, days, dateFrom, dateUntil, price];
}

class HallPackage extends Equatable {
  HallPackage({
    required this.id,
    required this.name,
    required this.hours,
    this.enabled = false,
    Iterable<HallPackagePrice> prices = const [],
  }) : prices = List.unmodifiable(prices);
  final String id, name;
  final HallHours hours;
  final bool enabled;
  final List<HallPackagePrice> prices;
  HallPackage copyWith({
    String? id,
    String? name,
    HallHours? hours,
    bool? enabled,
    Iterable<HallPackagePrice>? prices,
  }) => HallPackage(
    id: id ?? this.id,
    name: name ?? this.name,
    hours: hours ?? this.hours,
    enabled: enabled ?? this.enabled,
    prices: prices ?? this.prices,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft) '_local': {'name': name},
    'id': id,
    'name': name.trim(),
    'enabled': enabled,
    'hours': hours.toJson(localDraft: localDraft),
    'prices': prices.map((r) => r.toJson(localDraft: localDraft)).toList(),
  };
  factory HallPackage.fromJson(Map<String, dynamic> v) => HallPackage(
    id: v['id'],
    name: v['_local'] is Map && (v['_local'] as Map).containsKey('name')
        ? v['_local']['name']
        : v['name'],
    enabled: v['enabled'],
    hours: HallHours.fromJson(Map<String, dynamic>.from(v['hours'])),
    prices: (v['prices'] as List).map(
      (r) => HallPackagePrice.fromJson(Map<String, dynamic>.from(r)),
    ),
  );
  @override
  List<Object?> get props => [id, name, hours, enabled, prices];
}

class HallResource extends Equatable {
  HallResource({
    required this.id,
    required this.name,
    this.enabled = true,
    this.environment = 'unspecified',
    this.amenities = '',
    this.capacity = '100',
    this.seated = '100',
    this.hourlyEnabled = true,
    HallHours? hours,
    Iterable<int> durations = const [60],
    this.defaultDuration = 60,
    this.before = 0,
    this.after = 5,
    Iterable<HallTariff> tariffs = const [],
    Iterable<HallPackage>? sessions,
    HallPackage? fullDay,
  }) : hours = hours ?? HallHours(),
       durations = List.unmodifiable(durations),
       tariffs = List.unmodifiable(tariffs),
       sessions = List.unmodifiable(
         sessions ??
             [
               HallPackage(
                 id: const Uuid().v4(),
                 name: 'Morning',
                 hours: HallHours(opens: '09:00', closes: '13:00'),
               ),
               HallPackage(
                 id: const Uuid().v4(),
                 name: 'Evening',
                 hours: HallHours(opens: '17:00', closes: '22:00'),
               ),
             ],
       ),
       fullDay =
           fullDay ??
           HallPackage(
             id: const Uuid().v4(),
             name: 'Full day',
             hours: HallHours(opens: '09:00', closes: '23:00'),
           );
  final String id, name, environment, amenities, capacity, seated;
  final bool enabled, hourlyEnabled;
  final HallHours hours;
  final List<int> durations;
  final int defaultDuration, before, after;
  final List<HallTariff> tariffs;
  final List<HallPackage> sessions;
  final HallPackage fullDay;
  HallResource copyWith({
    String? name,
    String? environment,
    String? amenities,
    String? capacity,
    String? seated,
    bool? enabled,
    bool? hourlyEnabled,
    HallHours? hours,
    Iterable<int>? durations,
    int? defaultDuration,
    int? before,
    int? after,
    Iterable<HallTariff>? tariffs,
    Iterable<HallPackage>? sessions,
    HallPackage? fullDay,
  }) => HallResource(
    id: id,
    name: name ?? this.name,
    environment: environment ?? this.environment,
    amenities: amenities ?? this.amenities,
    capacity: capacity ?? this.capacity,
    seated: seated ?? this.seated,
    enabled: enabled ?? this.enabled,
    hourlyEnabled: hourlyEnabled ?? this.hourlyEnabled,
    hours: hours ?? this.hours,
    durations: durations ?? this.durations,
    defaultDuration: defaultDuration ?? this.defaultDuration,
    before: before ?? this.before,
    after: after ?? this.after,
    tariffs: tariffs ?? this.tariffs,
    sessions: sessions ?? this.sessions,
    fullDay: fullDay ?? this.fullDay,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft)
      '_local': {
        'name': name,
        'amenities': amenities,
        'capacity': capacity,
        'seated': seated,
      },
    'id': id,
    'name': name.trim(),
    'environment': environment,
    'amenities': amenities.trim(),
    'capacity': int.tryParse(capacity),
    'seated_capacity': int.tryParse(seated),
    'enabled': enabled,
    'hourly_enabled': hourlyEnabled,
    'operating': hours.toJson(localDraft: localDraft),
    'durations': durations,
    'default_duration_minutes': defaultDuration,
    'buffer_before': before,
    'buffer_after': after,
    'pricing_basis': 'start_time',
    'tariffs': tariffs.map((t) => t.toJson(localDraft: localDraft)).toList(),
    'sessions': sessions.map((s) => s.toJson(localDraft: localDraft)).toList(),
    'full_day': fullDay.toJson(localDraft: localDraft),
  };
  factory HallResource.fromJson(Map<String, dynamic> v) => HallResource(
    id: v['id'],
    name: v['_local'] is Map && (v['_local'] as Map).containsKey('name')
        ? v['_local']['name']
        : v['name'],
    environment: v['environment'],
    amenities:
        v['_local'] is Map && (v['_local'] as Map).containsKey('amenities')
        ? v['_local']['amenities']
        : v['amenities'],
    capacity: v['_local'] is Map && (v['_local'] as Map).containsKey('capacity')
        ? v['_local']['capacity']
        : '${v['capacity']}',
    seated: v['_local'] is Map && (v['_local'] as Map).containsKey('seated')
        ? v['_local']['seated']
        : '${v['seated_capacity']}',
    enabled: v['enabled'],
    hourlyEnabled: v['hourly_enabled'],
    hours: HallHours.fromJson(Map<String, dynamic>.from(v['operating'])),
    durations: List<int>.from(v['durations']),
    defaultDuration: v['default_duration_minutes'],
    before: v['buffer_before'],
    after: v['buffer_after'] ?? 5,
    tariffs: (v['tariffs'] as List).map(
      (t) => HallTariff.fromJson(Map<String, dynamic>.from(t)),
    ),
    sessions: (v['sessions'] as List).map(
      (s) => HallPackage.fromJson(Map<String, dynamic>.from(s)),
    ),
    fullDay: HallPackage.fromJson(Map<String, dynamic>.from(v['full_day'])),
  );
  @override
  List<Object?> get props => [
    id,
    name,
    environment,
    amenities,
    capacity,
    seated,
    enabled,
    hourlyEnabled,
    hours,
    durations,
    defaultDuration,
    before,
    after,
    tariffs,
    sessions,
    fullDay,
  ];
}

class HallConfiguration extends Equatable {
  HallConfiguration followOpeningTimes(HallConfiguration previous) => copyWith(
    halls: halls.map((p) {
      final old = previous.halls.where((v) => v.id == p.id).firstOrNull;
      if (old == null || sameOpeningTimes(old.hours.window, p.hours.window)) {
        return p;
      }
      HallPackage follow(HallPackage option) {
        final before = [
          ...old.sessions,
          old.fullDay,
        ].where((v) => v.id == option.id).firstOrNull;
        if (before == null ||
            !sameOpeningTimes(before.hours.window, old.hours.window) ||
            !sameOpeningTimes(before.hours.window, option.hours.window)) {
          return option;
        }
        return option.copyWith(
          hours: option.hours.copyWith(
            opens: p.hours.opens,
            closes: p.hours.closes,
          ),
        );
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
            ),
          );
        }),
        sessions: p.sessions.map(follow),
        fullDay: follow(p.fullDay),
      );
    }),
  );

  HallConfiguration restrictPricingDays() => copyWith(
    halls: halls.map((p) {
      HallPackage restrict(HallPackage o) {
        final days = pricingDays(o.hours.days, p.hours.days);
        return o.copyWith(
          hours: o.hours.copyWith(days: days),
          prices: o.prices.map(
            (r) => r.copyWith(
              window: r.window.copyWith(days: pricingDays(r.days, days)),
            ),
          ),
        );
      }

      return p.copyWith(
        tariffs: p.tariffs.map(
          (t) => t.copyWith(
            hours: t.hours.copyWith(
              days: pricingDays(t.hours.days, p.hours.days),
            ),
          ),
        ),
        sessions: p.sessions.map(restrict),
        fullDay: restrict(p.fullDay),
      );
    }),
  );

  HallConfiguration({Iterable<HallResource> halls = const []})
    : halls = List.unmodifiable(halls);
  final List<HallResource> halls;
  HallConfiguration copyWith({Iterable<HallResource>? halls}) =>
      HallConfiguration(halls: halls ?? this.halls);
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'kind': 'hall_v1',
    'schema_version': 1,
    'halls': halls.map((p) => p.toJson(localDraft: localDraft)).toList(),
  };
  factory HallConfiguration.fromJson(Map<String, dynamic> v) =>
      HallConfiguration(
        halls: (v['halls'] as List).map(
          (p) => HallResource.fromJson(Map<String, dynamic>.from(p)),
        ),
      );
  factory HallConfiguration.initial(Business? b) {
    if (b?.configuration?['kind'] == 'hall_v1') {
      return HallConfiguration.fromJson(b!.configuration!);
    }
    final old = b?.configuration;
    final hours = old == null
        ? HallHours()
        : HallHours(
            days: List<int>.from(old['days']),
            opens: old['opens_at'],
            closes: old['closes_at'],
          );
    final duration = (old?['duration_minutes'] as int?) ?? 60;
    return HallConfiguration(
      halls: (b?.resources ?? []).map(
        (r) => HallResource(
          id: r.id,
          name: r.name,
          capacity: '${r.capacity}',
          seated: '${r.capacity}',
          hours: hours,
          durations: [duration],
          defaultDuration: duration,
          before: old?['buffer_minutes'] ?? 0,
          tariffs: old == null
              ? []
              : [
                  HallTariff(
                    id: const Uuid().v4(),
                    hours: hours,
                    rates: [HallRate(duration, hallMoney(old['price_minor']))],
                  ),
                ],
        ),
      ),
    );
  }
  String? validate({bool complete = false}) {
    if (halls.length > 50) return 'Use at most 50 halls per business.';
    if (halls.map((p) => p.id).toSet().length != halls.length ||
        halls.map((p) => p.name.trim().toLowerCase()).toSet().length !=
            halls.length) {
      return 'Use unique hall names and identifiers.';
    }
    if (complete && !halls.any((p) => p.enabled)) {
      return 'Enable at least one hall.';
    }
    for (final p in halls) {
      if (p.name.trim().length < 2 ||
          p.name.trim().length > 100 ||
          !['unspecified', 'indoor', 'outdoor'].contains(p.environment) ||
          p.amenities.trim().length > 1000 ||
          int.tryParse(p.capacity) == null ||
          int.parse(p.capacity) < 1 ||
          int.parse(p.capacity) > 10000 ||
          int.tryParse(p.seated) == null ||
          int.parse(p.seated) < 0 ||
          int.parse(p.seated) > int.parse(p.capacity)) {
        return 'Check hall name, location type and capacities and amenities.';
      }
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
        return 'Use distinct price rules, up to 40 per hall.';
      }
      for (final t in p.tariffs) {
        final err = t.hours.validate();
        if (err != null) return err;
        if (p.enabled && p.hourlyEnabled && !t.hours.within(p.hours)) {
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
            p.hourlyEnabled &&
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
                  (hallMinute(a.opens) - hallMinute(p.hours.opens) + 1440) %
                  1440,
              y =
                  (hallMinute(b.opens) - hallMinute(p.hours.opens) + 1440) %
                  1440;
          final dates =
              a.dated == b.dated &&
              (!a.dated ||
                  (a.dateFrom!.compareTo(b.dateUntil!) <= 0 &&
                      b.dateFrom!.compareTo(a.dateUntil!) <= 0));
          if (dates &&
              a.days.any(b.days.contains) &&
              x < y + b.span &&
              y < x + a.span) {
            return 'Price rules overlap for ${p.name}.';
          }
        }
      }
      if (complete &&
          p.enabled &&
          p.hourlyEnabled &&
          (p.tariffs.isEmpty ||
              p.durations
                  .where((d) => d == p.defaultDuration)
                  .any((d) => d > p.hours.span))) {
        return 'Complete prices and valid durations for ${p.name}.';
      }

      if (p.sessions.length > 12 ||
          [p.fullDay, ...p.sessions].map((s) => s.id).toSet().length !=
              p.sessions.length + 1 ||
          p.sessions.map((s) => s.name.trim().toLowerCase()).toSet().length !=
              p.sessions.length) {
        return 'Use distinct session names and IDs, up to 12 sessions.';
      }
      for (final option in [p.fullDay, ...p.sessions]) {
        if (option.name.trim().length < 2 ||
            option.name.trim().length > 100 ||
            option.hours.validate() != null ||
            option.hours.dated ||
            option.prices.length > 40 ||
            option.prices.map((r) => r.id).toSet().length !=
                option.prices.length) {
          return 'Check session/package details.';
        }
        if (p.enabled && option.enabled) {
          final offset =
              (hallMinute(option.hours.opens) -
                  hallMinute(p.hours.opens) +
                  1440) %
              1440;
          if (!option.hours.within(p.hours) ||
              offset < 0 ||
              offset + option.hours.span > p.hours.span) {
            return '${option.name}: keep the booking within hall opening hours.';
          }
          if (complete &&
              (option.prices.isEmpty ||
                  option.prices.any(
                    (r) => Validation.priceMinor(r.price) == null,
                  ))) {
            return 'Complete prices for ${option.name}.';
          }
        }
        for (final rule in option.prices) {
          if (rule.window.validate() != null ||
              !rule.days.every(option.hours.days.contains) ||
              (rule.price.isNotEmpty &&
                  Validation.priceMinor(rule.price) == null)) {
            return 'Check package price weekdays, dates and amount.';
          }
        }
        for (var i = 0; i < option.prices.length; i++) {
          for (var j = i + 1; j < option.prices.length; j++) {
            final a = option.prices[i].window, b = option.prices[j].window;
            if (a.dated == b.dated &&
                a.days.any(b.days.contains) &&
                (!a.dated ||
                    (a.dateFrom!.compareTo(b.dateUntil!) <= 0 &&
                        b.dateFrom!.compareTo(a.dateUntil!) <= 0))) {
              return 'Price rules overlap for ${option.name}.';
            }
          }
        }
      }
      if (complete &&
          p.enabled &&
          !p.hourlyEnabled &&
          !p.fullDay.enabled &&
          !p.sessions.any((s) => s.enabled)) {
        return 'Enable at least one booking option for ${p.name}.';
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [halls];
}
