/// The only records eligible for owner-confirmed permanent team deletion.
class TeamDeletionTarget {
  const TeamDeletionTarget({
    required this.id,
    required this.name,
    required this.email,
    required this.invitation,
    required this.eligible,
  });
  factory TeamDeletionTarget.member(Map<String, dynamic> record) =>
      TeamDeletionTarget(
        id: record['id'],
        name: record['display_name'] ?? 'Team member',
        email: record['email'] ?? '',
        invitation: false,
        eligible:
            record['active'] == false &&
            ['staff', 'manager', 'owner'].contains(record['role']),
      );
  factory TeamDeletionTarget.invitation(Map<String, dynamic> record) =>
      TeamDeletionTarget(
        id: record['id'],
        name: record['display_name'] ?? 'Team member',
        email: record['email'] ?? '',
        invitation: true,
        eligible: record['revoked_at'] != null && record['accepted_at'] == null,
      );
  final String id, name, email;
  final bool invitation, eligible;
  String get confirmation => invitation
      ? 'Permanently delete the cancelled invitation for $name ($email)? This cannot be undone. Their login account and booking, payment and attendance history will be kept.'
      : 'Permanently delete the removed team record and its invitation records for $name ($email)? This cannot be undone. Their login account and booking, payment and attendance history will be kept.';
}
