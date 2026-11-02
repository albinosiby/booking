import 'package:equatable/equatable.dart';

import '../../bookings/models/slot_holder.dart';

/// A fixed weekly schedule to lay out before choosing its start time.
class SlotChartRequest extends Equatable {
  const SlotChartRequest({
    required this.businessId,
    required this.poolId,
    required this.planId,
    required this.start,
    required this.weekdays,
    required this.duration,
  });
  final String businessId, poolId, planId, start;
  final List<int> weekdays;
  final int duration;
  Map<String, dynamic> toJson() => {
    'business_id': businessId,
    'resource_id': poolId,
    'plan_id': planId,
    'starts_on': start,
    'weekdays': weekdays,
    'duration_minutes': duration,
  };
  @override
  List<Object?> get props => [
    businessId,
    poolId,
    planId,
    start,
    weekdays,
    duration,
  ];
}

/// One term date on which a weekly start time cannot be reserved.
class SlotChartClash extends Equatable {
  const SlotChartClash({
    required this.date,
    required this.label,
    required this.reason,
    this.holderCount = 0,
    this.holders = const [],
  });
  factory SlotChartClash.fromJson(Map<String, dynamic> j) => SlotChartClash(
    date: j['date'],
    label: j['label'],
    reason: j['reason'],
    holderCount: (j['holder_count'] as num? ?? 0).toInt(),
    holders: List.unmodifiable(
      (j['holders'] as List? ?? const []).map(
        (h) => SlotHolder.fromJson(Map<String, dynamic>.from(h)),
      ),
    ),
  );
  final String date, label, reason;
  final int holderCount;
  final List<SlotHolder> holders;
  @override
  List<Object?> get props => [date, label, reason, holderCount, holders];
}

/// A weekly start time checked against every session date of the term.
class SlotChartTime extends Equatable {
  const SlotChartTime({
    required this.time,
    required this.endTime,
    required this.status,
    this.capacity = 1,
    this.remaining = 0,
    this.sessionCount = 0,
    this.clashCount = 0,
    this.clashes = const [],
  });
  factory SlotChartTime.fromJson(Map<String, dynamic> j) => SlotChartTime(
    time: j['time'],
    endTime: j['end_time'],
    status: j['status'],
    capacity: (j['capacity'] as num? ?? 1).toInt(),
    remaining: (j['remaining_capacity'] as num? ?? 0).toInt(),
    sessionCount: (j['session_count'] as num? ?? 0).toInt(),
    clashCount: (j['clash_count'] as num? ?? 0).toInt(),
    clashes: List.unmodifiable(
      (j['clashes'] as List? ?? const []).map(
        (c) => SlotChartClash.fromJson(Map<String, dynamic>.from(c)),
      ),
    ),
  );
  final String time, endTime;

  /// `available`, `taken` or `past`.
  final String status;
  final int capacity, remaining, sessionCount, clashCount;
  final List<SlotChartClash> clashes;
  bool get available => status == 'available';
  bool get taken => status == 'taken';
  @override
  List<Object?> get props => [
    time,
    endTime,
    status,
    capacity,
    remaining,
    sessionCount,
    clashCount,
    clashes,
  ];
}

class AdmissionSlotChart extends Equatable {
  const AdmissionSlotChart({
    required this.expiresOn,
    this.dates = const [],
    this.times = const [],
  });
  factory AdmissionSlotChart.fromJson(Map<String, dynamic> j) =>
      AdmissionSlotChart(
        expiresOn: j['expires_on'],
        dates: List<String>.unmodifiable(j['dates'] as List? ?? const []),
        times: List.unmodifiable(
          (j['slots'] as List? ?? const []).map(
            (s) => SlotChartTime.fromJson(Map<String, dynamic>.from(s)),
          ),
        ),
      );
  final String expiresOn;
  final List<String> dates;
  final List<SlotChartTime> times;
  SlotChartTime? at(String time) =>
      times.where((t) => t.time == time).firstOrNull;
  @override
  List<Object?> get props => [expiresOn, dates, times];
}
