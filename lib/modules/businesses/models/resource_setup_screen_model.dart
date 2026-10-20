import '../../workspace/models/workspace_state.dart';

class ResourceSetupScreenModel extends WorkspaceState {
  ResourceSetupScreenModel.fromSnapshot(
    WorkspaceState snapshot, {
    this.step = 0,
    this.duration = 60,
    this.opens = '06:00',
    this.closes = '23:00',
    this.entitlement = 'unlimited',
    Set<int> days = const {1, 2, 3, 4, 5, 6, 7},
  }) : days = Set.unmodifiable(days),
       super(
         status: snapshot.status,
         data: snapshot.data,
         busy: snapshot.busy,
         error: snapshot.error,
       );
  final int step, duration;
  final String opens, closes, entitlement;
  final Set<int> days;
  ResourceSetupScreenModel copyWith({
    WorkspaceState? snapshot,
    int? step,
    int? duration,
    String? opens,
    String? closes,
    String? entitlement,
    Set<int>? days,
  }) => ResourceSetupScreenModel.fromSnapshot(
    snapshot ?? this,
    step: step ?? this.step,
    duration: duration ?? this.duration,
    opens: opens ?? this.opens,
    closes: closes ?? this.closes,
    entitlement: entitlement ?? this.entitlement,
    days: days ?? this.days,
  );
  @override
  List<Object?> get props => [
    ...super.props,
    step,
    duration,
    opens,
    closes,
    entitlement,
    days,
  ];
}
