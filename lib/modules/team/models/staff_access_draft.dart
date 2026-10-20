class BusinessAssignment {
  BusinessAssignment(this.businessId, Iterable<String> resources)
    : resourceIds = List.unmodifiable(resources);
  final String businessId;
  final List<String> resourceIds;
  Map<String, dynamic> toJson() => {
    'business_id': businessId,
    'resource_ids': resourceIds,
  };
}

class StaffAccessDraft {
  StaffAccessDraft({
    required this.name,
    required this.email,
    required this.role,
    required Iterable<String> permissions,
    required Iterable<BusinessAssignment> assignments,
  }) : permissions = List.unmodifiable(permissions),
       assignments = List.unmodifiable(assignments);
  final String name, email, role;
  final List<String> permissions;
  final List<BusinessAssignment> assignments;
  Map<String, dynamic> toJson() => {
    'display_name': name,
    'email': email,
    'role': role,
    'permissions': permissions,
    'assignments': assignments.map((a) => a.toJson()).toList(),
  };
}
