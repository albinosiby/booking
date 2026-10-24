import '../../workspace/models/workspace_state.dart';

class StaffAssignmentScreenModel extends WorkspaceState {
  StaffAssignmentScreenModel.fromSnapshot(
    WorkspaceState snapshot, {
    this.role = 'staff',
    this.removing = false,
    this.removed = false,
    this.removalError,
    Set<String> businesses = const {},
    Set<String> restricted = const {},
    Set<String> permissions = const {},
    this.accessRevision = 0,
    Map<String, Set<String>> resources = const {},
  }) : workspaceBusy = snapshot is StaffAssignmentScreenModel
           ? snapshot.workspaceBusy
           : snapshot.busy,
       businesses = Set.unmodifiable(businesses),
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
         busy:
             (snapshot is StaffAssignmentScreenModel
                 ? snapshot.workspaceBusy
                 : snapshot.busy) ||
             removing,
         error: snapshot.error,
       );
  final bool workspaceBusy, removing, removed;
  final String? removalError;
  final int accessRevision;
  final String role;
  final Set<String> businesses, restricted, permissions;
  final Map<String, Set<String>> resources;
  StaffAssignmentScreenModel copyWith({
    WorkspaceState? snapshot,
    int? accessRevision,
    bool? removing,
    bool? removed,
    String? removalError,
    bool clearRemovalError = false,
    String? role,
    Set<String>? businesses,
    Set<String>? restricted,
    Set<String>? permissions,
    Map<String, Set<String>>? resources,
  }) => StaffAssignmentScreenModel.fromSnapshot(
    snapshot ?? this,
    role: role ?? this.role,
    removing: removing ?? this.removing,
    removed: removed ?? this.removed,
    removalError: clearRemovalError ? null : removalError ?? this.removalError,
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
    workspaceBusy,
    removing,
    removed,
    removalError,
    role,
    businesses,
    restricted,
    permissions,
    resources,
  ];
}
