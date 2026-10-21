import 'package:equatable/equatable.dart';
import '../../../utils/helpers/validation.dart';
import 'court_configuration.dart';

/// Plan sold through Admissions. Play plans reserve the court per visit;
/// coaching batches share one court reservation per class.
class CourtPlan extends Equatable {
  CourtPlan({
    required this.id,
    this.kind = 'coaching',
    this.name = 'Coaching plan',
    Iterable<String> courtIds = const [],
    this.allowance = '12',
    this.expiryMode = 'after_months',
    this.expiryDays = '45',
    this.expiryMonths = '1',
    this.expiryYears = '1',
    this.expiryDate,
    this.price = '',
    this.enabled = true,
    CourtHours? hours,
    this.classDuration = 60,
    this.seats = '8',
    this.coachId,
  }) : courtIds = List.unmodifiable(courtIds),
       hours = hours ?? CourtHours();
  final String id, kind, name, allowance, expiryMode, expiryDays, price, seats;
  final String expiryMonths, expiryYears;
  final String? expiryDate, coachId;
  final List<String> courtIds;
  final bool enabled;
  final CourtHours hours;
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
  CourtPlan withValidityCount(String value) => switch (expiryMode) {
    'after_months' => copyWith(expiryMonths: value),
    'after_years' => copyWith(expiryYears: value),
    _ => copyWith(expiryDays: value),
  };

  String? validate(
    List<CourtResource> courts,
    List<CourtCoach> coaches, {
    bool complete = false,
    String? today,
  }) {
    final count = int.tryParse(validityCount),
        classes = int.tryParse(allowance),
        students = int.tryParse(seats);
    if (name.trim().length < 2 || name.trim().length > 100) {
      return 'Give each coaching plan a 2–100 character name.';
    }
    if (classes == null || classes < 1 || classes > 10000) {
      return 'Enter 1–10000 classes for $name.';
    }
    if (coaching && (students == null || students < 1 || students > 500)) {
      return 'Enter 1–500 students per class for $name.';
    }
    if (coaching && (classDuration < 30 || classDuration > 1440)) {
      return 'Choose a class duration for $name.';
    }
    if (expiryMode == 'fixed_date'
        ? expiryDate != null && !courtDateValid(expiryDate!)
        : count == null || count < 1 || count > validityMaximum) {
      return 'Choose a valid validity period for $name.';
    }
    if (price.isNotEmpty && Validation.priceMinor(price) == null) {
      return 'Enter a valid price for $name.';
    }
    if (courtIds.toSet().length != courtIds.length ||
        courtIds.any((id) => !courts.any((c) => c.id == id))) {
      return 'Choose existing courts for $name.';
    }
    final error = hours.validate();
    if (error != null) return '$name: $error';
    final coach = coaches.where((c) => c.id == coachId).firstOrNull;
    if (coaching &&
        coachId != null &&
        (coach == null || !courtIds.every(coach.courtIds.contains))) {
      return 'The coach of $name must be assigned to all of its courts.';
    }
    if (enabled) {
      for (final court in courts.where((c) => courtIds.contains(c.id))) {
        if (!court.enabled ||
            !hours.within(court.hours) ||
            (!hours.allDay &&
                (coaching ? classDuration : court.defaultDuration) >
                    hours.span)) {
          return 'Keep $name on enabled courts, within ${court.name} hours and long enough for a class.';
        }
      }
      if (complete &&
          (courtIds.isEmpty ||
              Validation.priceMinor(price) == null ||
              (expiryMode == 'fixed_date' &&
                  (expiryDate == null ||
                      (today != null && expiryDate!.compareTo(today) < 0))))) {
        return 'Complete courts, price and expiry for $name.';
      }
    }
    return null;
  }

  CourtPlan copyWith({
    String? name,
    Iterable<String>? courtIds,
    String? allowance,
    String? expiryMode,
    String? expiryDays,
    String? expiryMonths,
    String? expiryYears,
    String? expiryDate,
    bool clearExpiryDate = false,
    String? price,
    bool? enabled,
    CourtHours? hours,
    int? classDuration,
    String? seats,
    String? coachId,
    bool clearCoach = false,
  }) => CourtPlan(
    id: id,
    kind: kind,
    name: name ?? this.name,
    courtIds: courtIds ?? this.courtIds,
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
        'allowance': allowance,
        'expiryDays': expiryDays,
        'expiryMonths': expiryMonths,
        'expiryYears': expiryYears,
        'price': price,
        'seats': seats,
      },
    'id': id,
    'name': name.trim(),
    'kind': kind,
    'court_ids': courtIds,
    'allowance': int.tryParse(allowance),
    'expiry_mode': expiryMode,
    'expiry_days': expiryMode == 'after_start'
        ? int.tryParse(expiryDays)
        : null,
    'expiry_months': expiryMode == 'after_months'
        ? int.tryParse(expiryMonths)
        : null,
    'expiry_years': expiryMode == 'after_years'
        ? int.tryParse(expiryYears)
        : null,
    'expiry_date': expiryMode == 'fixed_date' ? expiryDate : null,
    'price_minor': Validation.priceMinor(price),
    'enabled': enabled,
    'availability': hours.toJson(localDraft: localDraft),
    'class_duration_minutes': coaching ? classDuration : null,
    'class_seats': coaching ? int.tryParse(seats) : null,
    'coach_id': coaching ? coachId : null,
    'renewal': 'none',
  };
  factory CourtPlan.fromJson(Map<String, dynamic> v) {
    final local = v['_local'] is Map
        ? Map<String, dynamic>.from(v['_local'])
        : const <String, dynamic>{};
    return CourtPlan(
      id: v['id'],
      kind: v['kind'] ?? 'coaching',
      name: v['name'],
      courtIds: List<String>.from(v['court_ids']),
      allowance: local['allowance'] ?? '${v['allowance']}',
      expiryMode: v['expiry_mode'],
      expiryDays: local['expiryDays'] ?? '${v['expiry_days'] ?? 45}',
      expiryMonths: local['expiryMonths'] ?? '${v['expiry_months'] ?? 1}',
      expiryYears: local['expiryYears'] ?? '${v['expiry_years'] ?? 1}',
      expiryDate: v['expiry_date'],
      price: local['price'] ?? courtMoney(v['price_minor']),
      enabled: v['enabled'],
      hours: CourtHours.fromJson(Map<String, dynamic>.from(v['availability'])),
      classDuration: v['class_duration_minutes'] ?? 60,
      seats: local['seats'] ?? '${v['class_seats'] ?? 8}',
      coachId: v['coach_id'],
    );
  }
  @override
  List<Object?> get props => [
    id,
    kind,
    name,
    courtIds,
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

/// Coach contact for a court business; never a login or staff member.
class CourtCoach extends Equatable {
  CourtCoach({
    required this.id,
    required this.name,
    required this.phone,
    Iterable<String> courtIds = const [],
  }) : courtIds = List.unmodifiable(courtIds);
  final String id, name, phone;
  final List<String> courtIds;
  CourtCoach withCourts(Iterable<String> ids) =>
      CourtCoach(id: id, name: name, phone: phone, courtIds: ids);
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name.trim(),
    'phone': phone.trim(),
    'court_ids': courtIds,
  };
  factory CourtCoach.fromJson(Map<String, dynamic> v) => CourtCoach(
    id: v['id'],
    name: v['name'],
    phone: v['phone'],
    courtIds: List<String>.from(v['court_ids'] ?? const []),
  );
  @override
  List<Object?> get props => [id, name, phone, courtIds];
}
