import '../../pool/models/pool_configuration.dart';
import '../../workspace/models/workspace.dart';

/// Whether a team member row (from GET /team) coaches classes.
bool memberCoaches(Map<String, dynamic> member) =>
    member['active'] == true &&
    (member['permissions'] as List? ?? const []).contains('coach');

/// Coaches of [businessId] in a GET /team response: the owner and staff with
/// the coach flag who are assigned to it. `poolIds` lists their assigned
/// spaces; empty means every space of the business.
List<PoolCoach> staffCoaches(Map<String, dynamic> team, String businessId) =>
    List.unmodifiable([
      for (final m in (team['members'] as List).cast<Map>())
        if (memberCoaches(Map<String, dynamic>.from(m)))
          if (m['role'] == 'owner')
            PoolCoach(id: m['id'], name: m['display_name'], owner: true)
          else
            for (final a in (m['assignments'] as List? ?? const []).cast<Map>())
              if (a['business_id'] == businessId)
                PoolCoach(
                  id: m['id'],
                  name: m['display_name'],
                  poolIds: List<String>.from(a['resource_ids']),
                ),
    ]);

/// Coaching plans [memberId] would stop coaching with this access: [coach]
/// off, or businesses and spaces that no longer cover the plan. [assignments]
/// maps business ids to assigned spaces; empty means the whole business.
List<String> releasedPlans(
  Iterable<Business> businesses,
  String memberId, {
  required bool coach,
  required Map<String, List<String>> assignments,
}) => [
  for (final b in businesses)
    if (b.configuration?['kind'] == 'pool_v1' ||
        b.configuration?['kind'] == 'court_v1')
      for (final p in (b.configuration!['plans'] as List? ?? const []))
        if (p['kind'] == 'coaching' && p['coach_id'] == memberId)
          if (!coach ||
              !assignments.containsKey(b.id) ||
              (assignments[b.id]!.isNotEmpty &&
                  !List<String>.from(
                    p['pool_ids'] ?? p['court_ids'] ?? const [],
                  ).every(assignments[b.id]!.contains)))
            p['name'] as String,
];
