/// Weekday sets that subscription package prices are defined for.
const subscriptionDayPresets = <String, List<int>>{
  'daily': [1, 2, 3, 4, 5, 6, 7],
  'weekends': [6, 7],
  'weekdays': [1, 2, 3, 4, 5],
};

String dayPresetLabel(String preset) => switch (preset) {
  'daily' => 'Every day',
  'weekends' => 'Weekends',
  'weekdays' => 'Weekdays',
  _ => 'Custom days',
};

/// The preset matching exactly these weekdays, or null for a custom mix.
String? dayPresetOf(List<int> weekdays) {
  final days = (weekdays.toSet().toList()..sort()).join(',');
  for (final e in subscriptionDayPresets.entries) {
    if (e.value.join(',') == days) return e.key;
  }
  return null;
}

/// 60 → `1 h`, 90 → `1.5 h`, 30 → `30 min`.
String hoursLabel(int minutes) {
  if (minutes < 60) return '$minutes min';
  final hours = minutes / 60;
  return '${hours == hours.roundToDouble() ? hours.toInt() : hours.toStringAsFixed(1)} h';
}
