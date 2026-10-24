/// Saved member identity used for removal, independent of unsaved form edits.
class TeamRemovalTarget {
  const TeamRemovalTarget({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    this.pending = false,
  });
  factory TeamRemovalTarget.fromMember(Map<String, dynamic> member) =>
      TeamRemovalTarget(
        id: member['id'] as String,
        name: member['display_name'] as String? ?? 'Team member',
        email: member['email'] as String? ?? '',
        role: member['role'] as String? ?? '',
        active: member['active'] == true,
        pending: member['pending_access'] == true,
      );
  final String id, name, email, role;
  final bool active, pending;
  bool get removable =>
      active && !pending && (role == 'staff' || role == 'manager');
  String get label => role == 'manager' ? 'Remove manager' : 'Remove staff';
  String get confirmation =>
      '$name ($email) will lose access to this organization. '
      'Their business and space assignments will be removed, and their coaching plans will become Unassigned. '
      'Existing bookings, payments and attendance history will be preserved.';
}
