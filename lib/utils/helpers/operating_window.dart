/// Calendar-day windows used by explicit full-day configuration validation.
class OperatingWindow {
  const OperatingWindow({
    required this.days,
    required this.opens,
    required this.closes,
    required this.allDay,
    this.dateFrom,
    this.dateUntil,
  });
  final List<int> days;
  final String opens, closes;
  final bool allDay;
  final String? dateFrom, dateUntil;
  static int minute(String v) =>
      int.parse(v.substring(0, 2)) * 60 + int.parse(v.substring(3));
  int get start => minute(opens);
  int get span => allDay ? 1440 : (minute(closes) - start + 1440) % 1440;
  static int shiftedDay(int day, int offset) => (day - 1 + offset) % 7 + 1;
  bool within(OperatingWindow parent) {
    if (!days.every(parent.days.contains)) return false;
    if (parent.allDay) {
      return days.every(
        (d) => start + span <= 1440 || parent.days.contains(shiftedDay(d, 1)),
      );
    }
    return (start - parent.start + 1440) % 1440 + span <= parent.span;
  }

  static int dateNumber(String date) =>
      DateTime.parse('${date}T00:00:00Z').difference(DateTime.utc(1970)).inDays;
  bool overlaps(OperatingWindow other) {
    for (final day in days) {
      for (final offset in [-1, 0, 1]) {
        if (!other.days.contains(shiftedDay(day, offset))) continue;
        final otherStart = other.start + offset * 1440;
        if (start >= otherStart + other.span || otherStart >= start + span) {
          continue;
        }
        final fromA = dateFrom == null
            ? double.negativeInfinity
            : dateNumber(dateFrom!).toDouble();
        final fromB = other.dateFrom == null
            ? double.negativeInfinity
            : (dateNumber(other.dateFrom!) - offset).toDouble();
        final untilA = dateUntil == null
            ? double.infinity
            : dateNumber(dateUntil!).toDouble();
        final untilB = other.dateUntil == null
            ? double.infinity
            : (dateNumber(other.dateUntil!) - offset).toDouble();
        final from = fromA > fromB ? fromA : fromB,
            until = untilA < untilB ? untilA : untilB;
        if (from > until) continue;
        if (!from.isFinite || !until.isFinite) return true;
        final firstDay = DateTime.utc(
          1970,
        ).add(Duration(days: from.toInt())).weekday;
        if (from + (day - firstDay + 7) % 7 <= until) return true;
      }
    }
    return false;
  }
}
