import 'package:equatable/equatable.dart';

import '../../../utils/helpers/time_format.dart';

/// Who occupies a slot: an ordinary booking, an admission session or a block.
class SlotHolder extends Equatable {
  const SlotHolder({
    required this.kind,
    this.bookingId,
    this.admissionId,
    this.reference,
    this.name,
    this.planName,
    this.weekdays = const [],
    this.expiresOn,
    this.localStart = '',
    this.localEnd = '',
  });
  factory SlotHolder.fromJson(Map<String, dynamic> j) => SlotHolder(
    kind: j['kind'],
    bookingId: j['booking_id'],
    admissionId: j['admission_id'],
    reference: j['reference'],
    name: j['name'],
    planName: j['plan_name'],
    weekdays: List<int>.unmodifiable(
      (j['weekdays'] as List? ?? const []).map((d) => (d as num).toInt()),
    ),
    expiresOn: j['expires_on'],
    localStart: j['local_start'] ?? '',
    localEnd: j['local_end'] ?? '',
  );

  /// `admission`, `booking` or `block`.
  final String kind;
  final String? bookingId, admissionId, reference, name, planName, expiresOn;
  final List<int> weekdays;
  final String localStart, localEnd;

  String get title => switch (kind) {
    'block' => 'Blocked slot',
    'admission' => name ?? 'Member',
    _ => name ?? 'Booking',
  };

  String get time => localStart.length < 16 || localEnd.length < 16
      ? ''
      : '${TimeFormat.display(localStart.substring(11, 16))}–'
            '${TimeFormat.display(localEnd.substring(11, 16))}';

  String get details => switch (kind) {
    'block' => ['Slot block', time].where((p) => p.isNotEmpty).join(' · '),
    'admission' => [
      planName ?? 'Plan',
      if (weekdays.isNotEmpty) weekdayNames(weekdays),
      if (expiresOn != null) 'till $expiresOn',
      ?reference,
    ].join(' · '),
    _ => ['Booking', time, ?reference].where((p) => p.isNotEmpty).join(' · '),
  };

  @override
  List<Object?> get props => [
    kind,
    bookingId,
    admissionId,
    reference,
    name,
    planName,
    weekdays,
    expiresOn,
    localStart,
    localEnd,
  ];
}

/// `[1, 3, 5]` → `Mon/Wed/Fri`; all seven days read as `Daily`.
String weekdayNames(List<int> days) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (days.toSet().length == 7) return 'Daily';
  return ([...days]..sort()).map((d) => names[d - 1]).join('/');
}
