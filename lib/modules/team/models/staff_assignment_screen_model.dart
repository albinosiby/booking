import '../../workspace/models/workspace_state.dart';

class StaffAssignmentScreenModel extends WorkspaceState {
  StaffAssignmentScreenModel.fromSnapshot(
    WorkspaceState snapshot, {
    this.role = 'staff',
    Set<String> businesses = const {},
    Set<String> restricted = const {},
    Set<String> permissions = const {},
    this.accessRevision = 0,
    Map<String, Set<String>> resources = const {},
  }) : businesses = Set.unmodifiable(businesses),
       restricted = Set.unmodifiable(restricted),
       permissions = Set.unmodifiable(permissions),
       resources = Map.unmodifiable(
         resources.map(
           (key, value) => MapEntry(key, Set<String>.unmodifiable(value)),
         ),
       ),
       super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  final int accessRevision;
  final String role;
  final Set<String> businesses, restricted, permissions;
  final Map<String, Set<String>> resources;
  StaffAssignmentScreenModel copyWith({
    WorkspaceState? snapshot,
    int? accessRevision,
    String? role,
    Set<String>? businesses,
    Set<String>? restricted,
    Set<String>? permissions,
    Map<String, Set<String>>? resources,
  }) => StaffAssignmentScreenModel.fromSnapshot(
    snapshot ?? this,
    role: role ?? this.role,
    accessRevision: accessRevision ?? this.accessRevision,
    businesses: businesses ?? this.businesses,
    restricted: restricted ?? this.restricted,
    permissions: permissions ?? this.permissions,
    resources: resources ?? this.resources,
  );
  @override
  List<Object?> get props => [
    ...super.props,
    accessRevision,
    role,
    businesses,
    restricted,
    permissions,
    resources,
  ];
}
