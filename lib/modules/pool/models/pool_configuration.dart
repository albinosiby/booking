import '../../../utils/helpers/group_size.dart';
import '../../../utils/helpers/pricing_time_bounds.dart';
import '../../../utils/helpers/pricing_days.dart';
import '../../../utils/helpers/operating_window.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/helpers/validation.dart';
import '../../workspace/models/workspace.dart';

int poolMinute(String value) =>
    int.parse(value.split(':')[0]) * 60 + int.parse(value.split(':')[1]);
bool poolDateValid(String value) {
  final parsed = DateTime.tryParse(value);
  return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) &&
      parsed != null &&
      parsed.toIso8601String().startsWith(value);
}

String poolMoney(dynamic value) =>
    value == null ? '' : ((value as num) / 100).toStringAsFixed(2);
num? poolDepth(String value) =>
    RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value) ? num.tryParse(value) : null;

class PoolHours extends Equatable {
  PoolHours({
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
      allDay ? 1440 : (poolMinute(closes) - poolMinute(opens) + 1440) % 1440;
  bool get dated => dateFrom != null;
  PoolHours copyWith({
    Iterable<int>? days,
    String? opens,
    String? closes,
    bool? allDay,
    String? dateFrom,
    String? dateUntil,
    bool clearDates = false,
  }) => PoolHours(
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
            (!poolDateValid(dateFrom!) ||
                !poolDateValid(dateUntil!) ||
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
  bool within(PoolHours parent) =>
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
  factory PoolHours.fromJson(Map<String, dynamic> v) => PoolHours(
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

class PoolRate extends Equatable {
  const PoolRate(this.minutes, this.price);
  final int minutes;
  final String price;
  int? get minor => Validation.priceMinor(price);
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft) '_local': {'price': price},
    'duration_minutes': minutes,
    'price_minor': minor,
  };
  factory PoolRate.fromJson(Map<String, dynamic> v) => PoolRate(
    v['duration_minutes'],
    v['_local']?['price'] ?? poolMoney(v['price_minor']),
  );
  @override
  List<Object?> get props => [minutes, price];
}

class PoolTariff extends Equatable {
  PoolTariff({
    required this.id,
    required this.hours,
    required Iterable<PoolRate> rates,
  }) : rates = List.unmodifiable(rates);
  final String id;
  final PoolHours hours;
  final List<PoolRate> rates;
  PoolTariff copyWith({
    String? id,
    PoolHours? hours,
    Iterable<PoolRate>? rates,
  }) => PoolTariff(
    id: id ?? this.id,
    hours: hours ?? this.hours,
    rates: rates ?? this.rates,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'id': id,
    'hours': hours.toJson(localDraft: localDraft),
    'rates': rates.map((r) => r.toJson(localDraft: localDraft)).toList(),
  };
  factory PoolTariff.fromJson(Map<String, dynamic> v) => PoolTariff(
    id: v['id'],
    hours: PoolHours.fromJson(Map<String, dynamic>.from(v['hours'])),
    rates: (v['rates'] as List).map(
      (r) => PoolRate.fromJson(Map<String, dynamic>.from(r)),
    ),
  );
  @override
  List<Object?> get props => [id, hours, rates];
}

class PoolResource extends Equatable {
  PoolResource({
    required this.id,
    required this.name,
    this.capacity = '20',
    this.minDepth = '',
    this.maxDepth = '',
    this.enabled = true,
    this.regularSwimming = true,
    PoolHours? hours,
    Iterable<int> durations = const [60],
    this.defaultDuration = 60,
    this.before = 0,
    this.after = 5,
    Iterable<PoolTariff> tariffs = const [],
  }) : hours = hours ?? PoolHours(),
       durations = List.unmodifiable(durations),
       tariffs = List.unmodifiable(tariffs);
  final String id, name, capacity, minDepth, maxDepth;
  final bool enabled, regularSwimming;
  final PoolHours hours;
  final List<int> durations;
  final int defaultDuration, before, after;
  final List<PoolTariff> tariffs;
  String? validateDetails({bool complete = false}) {
    final capacityValue = int.tryParse(capacity),
        lo = poolDepth(minDepth),
        hi = poolDepth(maxDepth);
    if (name.trim().length < 2 ||
        name.trim().length > 100 ||
        capacityValue == null ||
        capacityValue < 1 ||
        capacityValue > 10000) {
      return 'Enter a valid name and capacity for $name.';
    }
    if ((minDepth.isNotEmpty && lo == null) ||
        (maxDepth.isNotEmpty && hi == null) ||
        (lo != null && (lo < 0 || lo > 1000)) ||
        (hi != null && (hi <= 0 || hi > 1000)) ||
        (lo != null && hi != null && lo > hi)) {
      return 'Check minimum and maximum depth for $name.';
    }
    if (complete && enabled && (lo == null || hi == null)) {
      return 'Enter both depths for $name.';
    }
    return null;
  }

  PoolResource copyWith({
    String? name,
    String? capacity,
    String? minDepth,
    String? maxDepth,
    bool? enabled,
    bool? regularSwimming,
    PoolHours? hours,
    Iterable<int>? durations,
    int? defaultDuration,
    int? before,
    int? after,
    Iterable<PoolTariff>? tariffs,
  }) => PoolResource(
    id: id,
    name: name ?? this.name,
    capacity: capacity ?? this.capacity,
    minDepth: minDepth ?? this.minDepth,
    maxDepth: maxDepth ?? this.maxDepth,
    enabled: enabled ?? this.enabled,
    regularSwimming: regularSwimming ?? this.regularSwimming,
    hours: hours ?? this.hours,
    durations: durations ?? this.durations,
    defaultDuration: defaultDuration ?? this.defaultDuration,
    before: before ?? this.before,
    after: after ?? this.after,
    tariffs: tariffs ?? this.tariffs,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft)
      '_local': {
        'name': name,
        'capacity': capacity,
        'minDepth': minDepth,
        'maxDepth': maxDepth,
      },
    'id': id,
    'name': name.trim(),
    'capacity': int.tryParse(capacity),
    'depth_min_ft': poolDepth(minDepth),
    'depth_max_ft': poolDepth(maxDepth),
    'enabled': enabled,
    'regular_swimming': regularSwimming,
    'operating': hours.toJson(localDraft: localDraft),
    'durations': durations,
    'default_duration_minutes': defaultDuration,
    'buffer_before': before,
    'buffer_after': after,
    'pricing_basis': 'start_time',
    'tariffs': tariffs.map((t) => t.toJson(localDraft: localDraft)).toList(),
  };
  factory PoolResource.fromJson(Map<String, dynamic> v) => PoolResource(
    id: v['id'],
    name: v['_local'] is Map && (v['_local'] as Map).containsKey('name')
        ? v['_local']['name']
        : v['name'],
    capacity: v['_local'] is Map && (v['_local'] as Map).containsKey('capacity')
        ? v['_local']['capacity']
        : '${v['capacity']}',
    minDepth: v['_local'] is Map && (v['_local'] as Map).containsKey('minDepth')
        ? v['_local']['minDepth']
        : v['depth_min_ft']?.toString() ?? '',
    maxDepth: v['_local'] is Map && (v['_local'] as Map).containsKey('maxDepth')
        ? v['_local']['maxDepth']
        : v['depth_max_ft']?.toString() ?? '',
    enabled: v['enabled'],
    regularSwimming: v['regular_swimming'],
    hours: PoolHours.fromJson(Map<String, dynamic>.from(v['operating'])),
    durations: List<int>.from(v['durations']),
    defaultDuration: v['default_duration_minutes'],
    before: v['buffer_before'],
    after: v['buffer_after'] ?? 5,
    tariffs: (v['tariffs'] as List).map(
      (t) => PoolTariff.fromJson(Map<String, dynamic>.from(t)),
    ),
  );
  @override
  List<Object?> get props => [
    id,
    name,
    capacity,
    minDepth,
    maxDepth,
    enabled,
    regularSwimming,
    hours,
    durations,
    defaultDuration,
    before,
    after,
    tariffs,
  ];
}

class PoolGroupOffer extends Equatable {
  PoolGroupOffer({
    required this.id,
    this.name = 'Group offer',
    Iterable<String> poolIds = const [],
    this.mode = 'up_to',
    this.people = '15',
    this.duration = 60,
    this.price = '',
    this.enabled = true,
    PoolHours? hours,
  }) : poolIds = List.unmodifiable(poolIds),
       hours = hours ?? PoolHours();
  final String id, name, mode, people, price;
  String get sizeLabel => groupSizeLabel(mode, people);
  String get sizeExplanation => groupSizeExplanation(mode, people);
  final List<String> poolIds;
  final int duration;
  final bool enabled;
  final PoolHours hours;
  PoolGroupOffer copyWith({
    String? name,
    Iterable<String>? poolIds,
    String? mode,
    String? people,
    int? duration,
    String? price,
    bool? enabled,
    PoolHours? hours,
  }) => PoolGroupOffer(
    id: id,
    name: name ?? this.name,
    poolIds: poolIds ?? this.poolIds,
    mode: mode ?? this.mode,
    people: people ?? this.people,
    duration: duration ?? this.duration,
    price: price ?? this.price,
    enabled: enabled ?? this.enabled,
    hours: hours ?? this.hours,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft) '_local': {'name': name, 'people': people, 'price': price},
    'id': id,
    'name': name.trim(),
    'pool_ids': poolIds,
    'group_mode': mode,
    'people': int.tryParse(people),
    'duration_minutes': duration,
    'price_minor': Validation.priceMinor(price),
    'enabled': enabled,
    'availability': hours.toJson(localDraft: localDraft),
  };
  factory PoolGroupOffer.fromJson(Map<String, dynamic> v) => PoolGroupOffer(
    id: v['id'],
    name: v['_local'] is Map && (v['_local'] as Map).containsKey('name')
        ? v['_local']['name']
        : v['name'],
    poolIds: List<String>.from(v['pool_ids']),
    mode: v['group_mode'],
    people: v['_local'] is Map && (v['_local'] as Map).containsKey('people')
        ? v['_local']['people']
        : '${v['people']}',
    duration: v['duration_minutes'],
    price: v['_local'] is Map && (v['_local'] as Map).containsKey('price')
        ? v['_local']['price']
        : poolMoney(v['price_minor']),
    enabled: v['enabled'],
    hours: PoolHours.fromJson(Map<String, dynamic>.from(v['availability'])),
  );
  @override
  List<Object?> get props => [
    id,
    name,
    poolIds,
    mode,
    people,
    duration,
    price,
    enabled,
    hours,
  ];
}

class PoolPlan extends Equatable {
  PoolPlan({
    required this.id,
    required this.kind,
    this.name = 'Swimming plan',
    Iterable<String> poolIds = const [],
    this.allowance = '25',
    this.expiryMode = 'after_start',
    this.expiryDays = '45',
    this.expiryMonths = '1',
    this.expiryYears = '1',
    this.expiryDate,
    this.price = '',
    this.enabled = true,
    PoolHours? hours,
    this.classDuration = 60,
    this.seats = '10',
    this.coachId,
  }) : poolIds = List.unmodifiable(poolIds),
       hours = hours ?? PoolHours();
  final String id, kind, name, allowance, expiryMode, expiryDays, price, seats;
  final String expiryMonths, expiryYears;
  final String? expiryDate, coachId;
  final List<String> poolIds;
  final bool enabled;
  final PoolHours hours;
  final int classDuration;
  bool get coaching => kind == 'coaching';
  String get validityCount => switch (expiryMode) {
    'after_months' => expiryMonths,
    'after_years' => expiryYears,
    _ => expiryDays,
  };
  String get validityUnit => switch (expiryMode) {
    'after_months' => 'months',
    'after_years' => 'years',
    _ => 'days',
  };
  int get validityMaximum => switch (expiryMode) {
    'after_months' => 120,
    'after_years' => 10,
    _ => 3650,
  };
  String get validityLabel => expiryMode == 'fixed_date'
      ? 'Expires ${expiryDate ?? 'not set'}'
      : '$validityCount calendar $validityUnit from activation';
  PoolPlan withValidityCount(String value) => switch (expiryMode) {
    'after_months' => copyWith(expiryMonths: value),
    'after_years' => copyWith(expiryYears: value),
    _ => copyWith(expiryDays: value),
  };
  DateTime? expiryFrom(DateTime activation) {
    if (expiryMode == 'fixed_date') return DateTime.tryParse(expiryDate ?? '');
    final count = int.tryParse(validityCount);
    if (count == null || count < 1 || count > validityMaximum) return null;
    if (expiryMode == 'after_start') {
      return DateTime(
        activation.year,
        activation.month,
        activation.day + count,
      );
    }
    final months = expiryMode == 'after_years' ? count * 12 : count;
    final target = DateTime(activation.year, activation.month + months, 1);
    final last = DateTime(target.year, target.month + 1, 0).day;
    return DateTime(
      target.year,
      target.month,
      activation.day > last ? last : activation.day,
    );
  }

  PoolPlan copyWith({
    String? name,
    Iterable<String>? poolIds,
    String? allowance,
    String? expiryMode,
    String? expiryDays,
    String? expiryMonths,
    String? expiryYears,
    String? expiryDate,
    bool clearExpiryDate = false,
    String? price,
    bool? enabled,
    PoolHours? hours,
    int? classDuration,
    String? seats,
    String? coachId,
    bool clearCoach = false,
  }) => PoolPlan(
    id: id,
    kind: kind,
    name: name ?? this.name,
    poolIds: poolIds ?? this.poolIds,
    allowance: allowance ?? this.allowance,
    expiryMode: expiryMode ?? this.expiryMode,
    expiryDays: expiryDays ?? this.expiryDays,
    expiryMonths: expiryMonths ?? this.expiryMonths,
    expiryYears: expiryYears ?? this.expiryYears,
    expiryDate: clearExpiryDate ? null : expiryDate ?? this.expiryDate,
    price: price ?? this.price,
    enabled: enabled ?? this.enabled,
    hours: hours ?? this.hours,
    classDuration: classDuration ?? this.classDuration,
    seats: seats ?? this.seats,
    coachId: clearCoach ? null : coachId ?? this.coachId,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    if (localDraft)
      '_local': {
        'name': name,
        'allowance': allowance,
        'expiryDays': expiryDays,
        'expiryMonths': expiryMonths,
        'expiryYears': expiryYears,
        'price': price,
        'seats': seats,
        'expiryDate': expiryDate,
        'coachId': coachId,
        'classDuration': classDuration,
      },
    'id': id,
    'kind': kind,
    'name': name.trim(),
    'pool_ids': poolIds,
    'allowance': int.tryParse(allowance),
    'expiry_mode': expiryMode,
    'expiry_days': expiryMode == 'after_start'
        ? int.tryParse(expiryDays)
        : null,
    if (expiryMode == 'after_months')
      'expiry_months': int.tryParse(expiryMonths),
    if (expiryMode == 'after_years') 'expiry_years': int.tryParse(expiryYears),
    'expiry_date': expiryMode == 'fixed_date' ? expiryDate : null,
    'price_minor': Validation.priceMinor(price),
    'enabled': enabled,
    'availability': hours.toJson(localDraft: localDraft),
    'class_duration_minutes': coaching ? classDuration : null,
    'class_seats': coaching ? int.tryParse(seats) : null,
    'coach_id': coaching ? coachId : null,
    'renewal': 'none',
  };
  factory PoolPlan.fromJson(Map<String, dynamic> v) => PoolPlan(
    id: v['id'],
    kind: v['kind'],
    name: v['_local'] is Map && (v['_local'] as Map).containsKey('name')
        ? v['_local']['name']
        : v['name'],
    poolIds: List<String>.from(v['pool_ids']),
    allowance:
        v['_local'] is Map && (v['_local'] as Map).containsKey('allowance')
        ? v['_local']['allowance']
        : '${v['allowance']}',
    expiryMode: v['expiry_mode'],
    expiryMonths: v['_local']?['expiryMonths'] ?? '${v['expiry_months'] ?? 1}',
    expiryYears: v['_local']?['expiryYears'] ?? '${v['expiry_years'] ?? 1}',
    expiryDays:
        v['_local'] is Map && (v['_local'] as Map).containsKey('expiryDays')
        ? v['_local']['expiryDays']
        : '${v['expiry_days'] ?? 45}',
    expiryDate:
        v['_local'] is Map && (v['_local'] as Map).containsKey('expiryDate')
        ? v['_local']['expiryDate']
        : v['expiry_date'],
    price: v['_local'] is Map && (v['_local'] as Map).containsKey('price')
        ? v['_local']['price']
        : poolMoney(v['price_minor']),
    enabled: v['enabled'],
    hours: PoolHours.fromJson(Map<String, dynamic>.from(v['availability'])),
    classDuration:
        v['_local'] is Map && (v['_local'] as Map).containsKey('classDuration')
        ? v['_local']['classDuration']
        : v['class_duration_minutes'] ?? 60,
    seats: v['_local'] is Map && (v['_local'] as Map).containsKey('seats')
        ? v['_local']['seats']
        : '${v['class_seats'] ?? 10}',
    coachId: v['_local'] is Map && (v['_local'] as Map).containsKey('coachId')
        ? v['_local']['coachId']
        : v['coach_id'],
  );
  @override
  List<Object?> get props => [
    id,
    kind,
    name,
    poolIds,
    allowance,
    expiryMode,
    expiryDays,
    expiryMonths,
    expiryYears,
    expiryDate,
    price,
    enabled,
    hours,
    classDuration,
    seats,
    coachId,
  ];
}

/// A team member who coaches: the owner or staff with the coach flag.
/// [poolIds] are the spaces of their staff assignment; empty means every
/// space of the business.
class PoolCoach extends Equatable {
  PoolCoach({
    required this.id,
    required this.name,
    this.owner = false,
    Iterable<String> poolIds = const [],
  }) : poolIds = List.unmodifiable(poolIds);
  final String id, name;
  final bool owner;
  final List<String> poolIds;
  @override
  List<Object?> get props => [id, name, owner, poolIds];
}

class PoolConfiguration extends Equatable {
  PoolConfiguration followOpeningTimes(PoolConfiguration previous) {
    final changed = pools
        .where((p) {
          final old = previous.pools.where((v) => v.id == p.id).firstOrNull;
          return old != null &&
              !sameOpeningTimes(old.hours.window, p.hours.window);
        })
        .map((p) => p.id)
        .toSet();
    PoolHours followProduct(
      PoolHours hours,
      PoolHours before,
      List<String> ids,
      List<String> oldIds,
    ) {
      if (ids.isEmpty ||
          !sameOpeningTimes(hours.window, before.window) ||
          (!ids.any(changed.contains) &&
              ids.toSet().containsAll(oldIds) &&
              oldIds.toSet().containsAll(ids))) {
        return hours;
      }
      final oldBounds = PricingTimeBounds(
        previous.pools
            .where((p) => oldIds.contains(p.id))
            .map((p) => p.hours.window),
        before.days,
      );
      final oldDefault = oldBounds.defaultRange;
      if (oldDefault == null || !sameOpeningTimes(before.window, oldDefault)) {
        return hours;
      }
      final selected = pools.where((p) => ids.contains(p.id)).toList();
      final days = pricingDays(
        hours.days,
        commonOpeningDays(selected.map((p) => p.hours.days)),
      );
      final next = PricingTimeBounds(
        selected.map((p) => p.hours.window),
        days,
      ).defaultRange;
      return next == null
          ? hours
          : hours.copyWith(
              opens: next.opens,
              closes: next.closes,
              allDay: next.allDay,
            );
    }

    return copyWith(
      pools: pools.map((p) {
        final old = previous.pools.where((v) => v.id == p.id).firstOrNull;
        if (old == null || !changed.contains(p.id)) return p;
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
      offers: offers.map((o) {
        final old = previous.offers.where((v) => v.id == o.id).firstOrNull;
        return old == null
            ? o
            : o.copyWith(
                hours: followProduct(
                  o.hours,
                  old.hours,
                  o.poolIds,
                  old.poolIds,
                ),
              );
      }),
      plans: plans.map((p) {
        final old = previous.plans.where((v) => v.id == p.id).firstOrNull;
        return old == null
            ? p
            : p.copyWith(
                hours: followProduct(
                  p.hours,
                  old.hours,
                  p.poolIds,
                  old.poolIds,
                ),
              );
      }),
    );
  }

  PoolConfiguration restrictPricingDays() {
    List<int> eligibleDays(List<String> ids) => commonOpeningDays(
      pools.where((p) => ids.contains(p.id)).map((p) => p.hours.days),
    );
    return copyWith(
      pools: pools.map(
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
      offers: offers.map(
        (o) => o.poolIds.isEmpty
            ? o
            : o.copyWith(
                hours: o.hours.copyWith(
                  days: pricingDays(o.hours.days, eligibleDays(o.poolIds)),
                ),
              ),
      ),
      plans: plans.map(
        (p) => p.poolIds.isEmpty
            ? p
            : p.copyWith(
                hours: p.hours.copyWith(
                  days: pricingDays(p.hours.days, eligibleDays(p.poolIds)),
                ),
              ),
      ),
    );
  }

  PoolConfiguration({
    Iterable<PoolResource> pools = const [],
    Iterable<PoolGroupOffer> offers = const [],
    Iterable<PoolPlan> plans = const [],
  }) : pools = List.unmodifiable(pools),
       offers = List.unmodifiable(offers),
       plans = List.unmodifiable(plans);
  final List<PoolResource> pools;
  final List<PoolGroupOffer> offers;
  final List<PoolPlan> plans;

  PoolConfiguration copyWith({
    Iterable<PoolResource>? pools,
    Iterable<PoolGroupOffer>? offers,
    Iterable<PoolPlan>? plans,
  }) => PoolConfiguration(
    pools: pools ?? this.pools,
    offers: offers ?? this.offers,
    plans: plans ?? this.plans,
  );
  Map<String, dynamic> toJson({bool localDraft = false}) => {
    'kind': 'pool_v1',
    'schema_version': 1,
    'pools': pools.map((p) => p.toJson(localDraft: localDraft)).toList(),
    'group_offers': offers
        .map((o) => o.toJson(localDraft: localDraft))
        .toList(),
    'plans': plans.map((p) => p.toJson(localDraft: localDraft)).toList(),
  };
  factory PoolConfiguration.fromJson(Map<String, dynamic> v) {
    final plans = (v['plans'] as List)
        .map((p) => PoolPlan.fromJson(Map<String, dynamic>.from(p)))
        .toList();
    // Coach contacts were replaced by team coaches; their plans are
    // Unassigned until a team coach takes them.
    final contacts = {
      for (final c in v['coaches'] as List? ?? const []) (c as Map)['id'],
    };
    return PoolConfiguration(
      pools: (v['pools'] as List).map(
        (p) => PoolResource.fromJson(Map<String, dynamic>.from(p)),
      ),
      offers: (v['group_offers'] as List).map(
        (o) => PoolGroupOffer.fromJson(Map<String, dynamic>.from(o)),
      ),
      plans: plans.map(
        (p) => contacts.contains(p.coachId) ? p.copyWith(clearCoach: true) : p,
      ),
    );
  }
  factory PoolConfiguration.initial(Business? business) {
    final old = business?.configuration;
    if (old?['kind'] == 'pool_v1') return PoolConfiguration.fromJson(old!);
    final hours = old == null
        ? PoolHours()
        : PoolHours(
            days: List<int>.from(old['days']),
            opens: old['opens_at'],
            closes: old['closes_at'],
          );
    final pools = (business?.resources ?? [])
        .map(
          (r) => PoolResource(
            id: r.id,
            name: r.name,
            capacity: '${r.capacity}',
            hours: hours,
          ),
        )
        .toList();
    final plans = <PoolPlan>[];
    if (old?['plan_name'] != null && pools.isNotEmpty) {
      // Existing visit-based/unlimited plans require deliberate conversion to attendance days.
      final attendance = old!['entitlement'] == 'attendance_days';
      plans.add(
        PoolPlan(
          id: const Uuid().v5(
            '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
            'pool-plan:${business!.id}',
          ),
          kind: 'swimming',
          name: old['plan_name'],
          poolIds: pools.map((p) => p.id),
          allowance: '${attendance ? old['visit_limit'] : 25}',
          expiryDays: '${old['validity_days']}',
          price: poolMoney(old['price_minor']),
          enabled: attendance,
          hours: hours,
        ),
      );
    }
    return PoolConfiguration(pools: pools, plans: plans);
  }
  String? validate({bool complete = false, bool requireProducts = true}) {
    if (pools.length > 30 || offers.length > 50 || plans.length > 50) {
      return 'Too many pools, offers or plans.';
    }
    if (complete && !pools.any((p) => p.enabled)) {
      return 'Enable at least one pool.';
    }
    if (pools.map((p) => p.name.trim().toLowerCase()).toSet().length !=
        pools.length) {
      return 'Give each pool a unique name.';
    }
    for (final p in pools) {
      final detailsError = p.validateDetails(complete: complete);
      if (detailsError != null) return detailsError;
      final err = p.hours.validate();
      if (err != null) return '${p.name}: $err';
      if (p.hours.dated ||
          p.durations.isEmpty ||
          p.durations.toSet().length != p.durations.length ||
          !p.durations.contains(p.defaultDuration) ||
          p.durations.any((d) => d < 30 || d > 1440) ||
          p.before < 0 ||
          p.before > 240 ||
          p.after < 0 ||
          p.after > 240) {
        return 'Check durations and preparation/cleanup times for ${p.name}.';
      }
      if (p.tariffs.length > 40) return 'Use at most 40 price rules per pool.';
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
            p.regularSwimming &&
            t.rates.any(
              (r) => r.minutes == p.defaultDuration && r.minor == null,
            )) {
          return 'Complete regular swimming prices for ${p.name}.';
        }
      }
      for (var i = 0; i < p.tariffs.length; i++) {
        for (var j = i + 1; j < p.tariffs.length; j++) {
          final a = p.tariffs[i].hours, b = p.tariffs[j].hours;
          final x =
                  (poolMinute(a.opens) - poolMinute(p.hours.opens) + 1440) %
                  1440,
              y =
                  (poolMinute(b.opens) - poolMinute(p.hours.opens) + 1440) %
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
          p.regularSwimming &&
          (p.tariffs.isEmpty ||
              p.durations
                  .where((d) => d == p.defaultDuration)
                  .any((d) => !p.hours.allDay && d > p.hours.span))) {
        return 'Complete prices and valid durations for ${p.name}.';
      }
    }
    String? eligibility(
      List<String> ids,
      PoolHours hours,
      bool enabled,
      int count,
      int duration,
    ) {
      if (ids.toSet().length != ids.length ||
          ids.any((id) => !pools.any((p) => p.id == id))) {
        return 'Select existing pools.';
      }
      if (enabled && ids.isEmpty && complete) {
        return 'Select at least one eligible pool.';
      }
      final error = hours.validate();
      if (error != null) return error;
      for (final p in pools.where((p) => ids.contains(p.id))) {
        if (enabled &&
            (!p.enabled ||
                count > int.parse(p.capacity) ||
                !hours.within(p.hours) ||
                !hours.allDay && duration > hours.span)) {
          return 'Check eligible pool capacity and opening hours.';
        }
      }
      return null;
    }

    for (final o in offers) {
      final count = int.tryParse(o.people);
      if (o.name.trim().length < 2 ||
          o.name.trim().length > 100 ||
          !['exact', 'up_to', 'at_least'].contains(o.mode) ||
          count == null ||
          count < 1 ||
          count > 10000 ||
          o.duration < 30 ||
          o.duration > 1440 ||
          (o.price.isNotEmpty && Validation.priceMinor(o.price) == null)) {
        return 'Check group offer details.';
      }
      final err = eligibility(o.poolIds, o.hours, o.enabled, count, o.duration);
      if (err != null) return '${o.name}: $err';
      if (complete && o.enabled && Validation.priceMinor(o.price) == null) {
        return 'Enter the total price for ${o.name}.';
      }
    }
    for (final p in plans) {
      final allowance = int.tryParse(p.allowance),
          expiry = int.tryParse(p.validityCount),
          seats = int.tryParse(p.seats);
      if (p.name.trim().length < 2 ||
          p.name.trim().length > 100 ||
          !['swimming', 'coaching'].contains(p.kind) ||
          allowance == null ||
          allowance < 1 ||
          allowance > 10000 ||
          ![
            'after_start',
            'after_months',
            'after_years',
            'fixed_date',
          ].contains(p.expiryMode) ||
          (p.expiryMode != 'fixed_date' &&
              (expiry == null || expiry < 1 || expiry > p.validityMaximum)) ||
          (p.expiryMode == 'fixed_date' &&
              p.expiryDate != null &&
              !poolDateValid(p.expiryDate!)) ||
          (p.price.isNotEmpty && Validation.priceMinor(p.price) == null)) {
        return 'Check plan allowance, expiry and price.';
      }
      if (p.coaching &&
          (seats == null ||
              seats < 1 ||
              seats > 10000 ||
              p.classDuration < 30 ||
              p.classDuration > 1440)) {
        return 'Check coaching seats and class duration.';
      }

      final err = eligibility(
        p.poolIds,
        p.hours,
        p.enabled,
        p.coaching ? seats! : 1,
        p.coaching ? p.classDuration : 0,
      );
      if (err != null) return '${p.name}: $err';
      if (complete &&
          p.enabled &&
          (Validation.priceMinor(p.price) == null ||
              (p.expiryMode == 'fixed_date' && p.expiryDate == null))) {
        return 'Complete price and expiry for ${p.name}.';
      }
    }
    if (complete &&
        requireProducts &&
        pools
            .where((p) => p.enabled)
            .any(
              (p) =>
                  !p.regularSwimming &&
                  !offers.any((o) => o.enabled && o.poolIds.contains(p.id)) &&
                  !plans.any((x) => x.enabled && x.poolIds.contains(p.id)),
            )) {
      return 'Each enabled pool needs regular swimming, a group offer or a plan.';
    }
    return null;
  }

  @override
  List<Object?> get props => [pools, offers, plans];
}
