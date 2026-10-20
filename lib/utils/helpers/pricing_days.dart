/// Retain only explicitly selected weekdays when a parent schedule narrows.
List<int> pricingDays(Iterable<int> selected, Iterable<int> openingDays) {
  final allowed = openingDays.toSet();
  return selected.where(allowed.contains).toSet().toList()..sort();
}

/// A product available at several pools must fit every eligible pool.
List<int> commonOpeningDays(Iterable<Iterable<int>> schedules) {
  final values = schedules.toList();
  if (values.isEmpty) return [];
  return values
      .skip(1)
      .fold(
        values.first.toSet(),
        (days, next) => days.intersection(next.toSet()),
      )
      .toList()
    ..sort();
}
