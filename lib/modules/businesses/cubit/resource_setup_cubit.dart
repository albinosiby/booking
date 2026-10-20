import '../../../core/state/workspace_screen_cubit.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../repositories/business_repository.dart';
import '../models/business_draft.dart';
import '../models/resource_setup_screen_model.dart';
import '../../workspace/cubit/workspace_state.dart';
import '../../workspace/models/workspace.dart';

class ResourceSetupCubit
    extends WorkspaceScreenCubit<ResourceSetupScreenModel> {
  ResourceSetupCubit(
    WorkspaceSession session,
    this.repository,
    String businessId,
  ) : super(session, ResourceSetupScreenModel.fromSnapshot) {
    final business = state.data.businesses
        .where((b) => b.id == businessId)
        .firstOrNull;
    final config = business?.configuration;
    emit(
      state.copyWith(
        duration:
            config?['duration_minutes'] ??
            (business?.type == BusinessType.hall ? 1440 : 60),
        opens: config?['opens_at'],
        closes: config?['closes_at'],
        days: config == null ? null : Set<int>.from(config['days']),
        entitlement: config?['entitlement'],
      ),
    );
  }
  final BusinessRepository repository;
  @override
  ResourceSetupScreenModel mapSnapshot(WorkspaceState snapshot) =>
      state.copyWith(snapshot: snapshot);
  void selectStep(int value) {
    if (value >= 0 && value <= 2) emit(state.copyWith(step: value));
  }

  void selectDuration(int value) => emit(state.copyWith(duration: value));
  void selectEntitlement(String value) =>
      emit(state.copyWith(entitlement: value));
  void selectHours({String? opens, String? closes}) =>
      emit(state.copyWith(opens: opens, closes: closes));
  void selectDay(int day, bool enabled) {
    final days = {...state.days};
    enabled ? days.add(day) : days.remove(day);
    emit(state.copyWith(days: days));
  }

  Future<bool> addResource(String id, ResourceDraft draft) =>
      save(() => repository.addResource(id, draft));
  Future<bool> removeResource(String id, String resource) =>
      save(() => repository.removeResource(id, resource));
  Future<bool> configure(String id, BusinessConfiguration configuration) =>
      save(() => repository.configure(id, configuration));
  Future<bool> activate(String id) => save(() => repository.activate(id));
}
