import '../../workspace/models/workspace.dart';

/// Reads saved opening configuration without confusing a price rule's all-day
/// flag with the resource's actual opening hours.
bool bookingOpensAllDay(
  Workspace workspace,
  String? businessId,
  String? spaceId,
  String? optionId,
) {
  final config = workspace.businesses
      .where((b) => b.id == businessId)
      .firstOrNull
      ?.configuration;
  if (config == null) return false;
  Map? find(Object? rows, String? id) => rows is List
      ? rows.whereType<Map>().where((r) => r['id'] == id).firstOrNull
      : null;
  Object? hours;
  if (config['kind'] == 'turf_v1') {
    hours =
        find(config['offerings'], optionId)?['hours_override'] ??
        config['operating'];
  } else {
    hours = find(
      config['courts'] ?? config['pools'] ?? config['halls'],
      spaceId,
    )?['operating'];
  }
  return hours is Map && hours['all_day'] == true;
}
