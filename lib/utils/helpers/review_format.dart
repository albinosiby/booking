import 'time_format.dart';

/// Presentation only: the original weekday/time values remain unchanged.
String reviewDays(Iterable<int> days) {
  final values = days.toSet().toList()..sort();
  if (values.length == 7) return 'Every day';
  if (values.join(',') == '1,2,3,4,5') return 'Mon–Fri';
  if (values.join(',') == '6,7') return 'Sat–Sun';
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return values.isEmpty
      ? 'No days selected'
      : values
            .where((d) => d >= 1 && d <= 7)
            .map((d) => names[d - 1])
            .join(', ');
}

String reviewTime(String opens, String closes, {bool allDay = false}) => allDay
    ? 'Open 24 hours'
    : '${TimeFormat.display(opens)}–${TimeFormat.display(closes)}';

String reviewSchedule({
  required Iterable<int> days,
  required String opens,
  required String closes,
  bool allDay = false,
  String? dateFrom,
  String? dateUntil,
}) => [
  reviewDays(days),
  reviewTime(opens, closes, allDay: allDay),
  if (dateFrom != null) '$dateFrom → ${dateUntil ?? 'not set'}',
].join(' · ');

String reviewPrice(String currency, String price) => price.trim().isEmpty
    ? 'Price not set'
    : '${currency == 'INR' ? '₹' : currency} $price';

String reviewCount(int count, String noun) =>
    '$count $noun${count == 1 ? '' : 's'}';
