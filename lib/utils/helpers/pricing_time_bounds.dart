import 'operating_window.dart';
import 'pricing_days.dart';
import 'time_format.dart';

/// Limits use operating weekdays, including the existing overnight semantics.
class PricingTimeBounds {
  PricingTimeBounds(Iterable<OperatingWindow> openings, Iterable<int> days)
    : openings = List.unmodifiable(openings),
      days = List.unmodifiable(days);
  final List<OperatingWindow> openings;
  final List<int> days;
  bool allows(String opens, String closes, {bool allDay = false}) {
    if (openings.isEmpty ||
        TimeFormat.normalize(opens) != opens ||
        TimeFormat.normalize(closes) != closes) {
      return false;
    }
    if (allDay ? opens != '00:00' || closes != '00:00' : opens == closes) {
      return false;
    }
    final selected = days.isEmpty
        ? commonOpeningDays(openings.map((h) => h.days))
        : days;
    if (selected.isEmpty) return false;
    final range = OperatingWindow(
      days: selected,
      opens: opens,
      closes: closes,
      allDay: allDay,
    );
    return openings.every((parent) => parent.span > 0 && range.within(parent));
  }

  String get label => openings
      .map(
        (h) => h.allDay
            ? 'Open 24 hours'
            : '${TimeFormat.display(h.opens)}–${TimeFormat.display(h.closes)}',
      )
      .toSet()
      .join(' & ');
  String? validate(String opens, String closes, {bool allDay = false}) =>
      allows(opens, closes, allDay: allDay)
      ? null
      : 'Choose a non-zero time range within opening hours: $label.';

  /// Usually a parent's interval is the answer. Endpoint intersections handle
  /// eligible pools with different/overnight windows without minute rounding.
  OperatingWindow? get defaultRange {
    if (openings.isEmpty) return null;
    final selected = days.isEmpty
        ? commonOpeningDays(openings.map((h) => h.days))
        : days;
    if (selected.isEmpty) return null;
    final endpoints = {
      '00:00',
      for (final h in openings) ...[h.opens, h.closes],
    };
    final fullDay = OperatingWindow(
      days: selected,
      opens: '00:00',
      closes: '00:00',
      allDay: true,
    );
    if (allows('00:00', '00:00', allDay: true)) return fullDay;
    final candidates = [
      for (final start in endpoints)
        for (final end in endpoints)
          if (start != end)
            OperatingWindow(
              days: selected,
              opens: start,
              closes: end,
              allDay: false,
            ),
    ]..sort((a, b) => b.span.compareTo(a.span));
    for (final c in candidates) {
      if (allows(c.opens, c.closes)) return c;
    }
    return null;
  }
}

bool sameOpeningTimes(OperatingWindow a, OperatingWindow b) =>
    a.opens == b.opens && a.closes == b.closes && a.allDay == b.allDay;
