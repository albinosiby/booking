import '../../workspace/models/workspace_state.dart';
import '../../workspace/models/workspace.dart';

class BusinessesScreenModel extends WorkspaceState {
  BusinessesScreenModel.fromSnapshot(
    WorkspaceState snapshot, {
    Set<BusinessType> selected = const {},
    Map<BusinessType, String> names = const {},
    this.adding = false,
  }) : selected = Set.unmodifiable(selected),
       names = Map.unmodifiable(names),
       super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  final Set<BusinessType> selected;
  final Map<BusinessType, String> names;
  final bool adding;
  bool get disabled => busy || adding;
  BusinessesScreenModel copyWith({
    WorkspaceState? snapshot,
    Set<BusinessType>? selected,
    Map<BusinessType, String>? names,
    bool? adding,
  }) => BusinessesScreenModel.fromSnapshot(
    snapshot ?? this,
    selected: selected ?? this.selected,
    names: names ?? this.names,
    adding: adding ?? this.adding,
  );
  @override
  List<Object?> get props => [...super.props, selected, names, adding];
}
