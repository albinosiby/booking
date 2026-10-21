import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/team_coaches_model.dart';
import '../repositories/team_coaches_repository.dart';

class TeamCoachesCubit extends Cubit<TeamCoachesModel> {
  TeamCoachesCubit(this.repository, this.session) : super(TeamCoachesModel()) {
    scope = _scope;
    subscription = session.snapshots.listen((_) {
      if (_scope != scope) {
        scope = _scope;
        generation++;
        if (!isClosed) {
          emit(TeamCoachesModel(error: 'Your access changed. Reopen Coaches.'));
        }
      }
    });
  }
  final TeamCoachesRepository repository;
  final WorkspaceSession session;
  late final StreamSubscription subscription;
  late String scope;
  int generation = 0;
  String get _scope =>
      '${session.state.data.organization?.id}/${session.state.data.membership?['id']}/${session.state.data.isOwner}';
  bool get authorized => !isClosed && session.state.data.isOwner;
  String? get ownerId => session.state.data.membership?['id'];
  Future<void> load() async {
    if (!authorized || state.busy) return;
    final g = ++generation;
    emit(state.copy(loading: true));
    try {
      final team = await repository.load();
      if (!isClosed && g == generation && authorized) {
        emit(state.copy(team: team, loading: false));
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(
          state.copy(
            loading: false,
            team: accessFailure(e) ? CoachTeam() : null,
            error: e is AppException ? e.message : 'Could not load coaches.',
          ),
        );
      }
    }
  }

  void beginAssign(String businessId, String coachId) {
    if (!authorized || state.busy) return;
    final business = state.businesses
        .where((b) => b.id == businessId)
        .firstOrNull;
    if (business == null || !business.coaches.any((c) => c.id == coachId)) {
      return;
    }
    emit(
      state.copy(
        editing: true,
        businessId: businessId,
        coachId: coachId,
        planIds: business.plans
            .where((p) => p.coachId == coachId)
            .map((p) => p.id),
      ),
    );
  }

  void toggle(String id, bool selected) {
    if (state.busy) return;
    final ids = {...state.planIds};
    if (selected) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    emit(state.copy(planIds: ids));
  }

  // Editor errors belong to the editor; don't leave them on the page.
  void closeEditor() {
    if (!isClosed && !state.busy) emit(state.copy(editing: false));
  }

  /// Upcoming class clashes the plan assignment would create, or null when
  /// they could not be checked (the error is shown in the editor).
  Future<List<String>?> assignmentConflicts() async {
    final b = state.selectedBusiness, coachId = state.coachId;
    if (!authorized ||
        state.busy ||
        !state.editing ||
        b == null ||
        coachId == null) {
      return null;
    }
    final added = state.planIds.where(
      (id) => !b.plans.any((p) => p.id == id && p.coachId == coachId),
    );
    if (added.isEmpty) return const [];
    final g = generation;
    emit(state.copy(busy: true));
    try {
      final conflicts = await repository.conflicts(
        b.id,
        coachId,
        state.planIds,
      );
      if (isClosed || g != generation) return null;
      emit(state.copy(busy: false));
      return conflicts;
    } catch (e) {
      if (isClosed || g != generation) return null;
      emit(
        state.copy(
          busy: false,
          error: e is AppException
              ? e.message
              : 'Could not check this coach’s classes. Retry.',
        ),
      );
      return null;
    }
  }

  Future<bool> saveEditor() async {
    if (!authorized || state.busy || state.loading || !state.editing) {
      return false;
    }
    final b = state.selectedBusiness, coachId = state.coachId;
    if (b == null || coachId == null) return false;
    return _change(
      () => repository.assign(b.id, b.version, coachId, state.planIds),
      'Could not save coaches. Refresh and retry.',
    );
  }

  /// The owner starts or stops coaching; stopping releases their plans.
  Future<bool> setOwnerCoach(bool coach) => _change(
    () => repository.setOwnerCoach(coach),
    'Could not update your coaching. Retry.',
  );

  Future<bool> _change(Future<void> Function() action, String failure) async {
    if (!authorized || state.busy) return false;
    final g = ++generation;
    emit(state.copy(busy: true));
    final ok = await session.change(action);
    if (isClosed || g != generation || !authorized) return false;
    emit(
      state.copy(
        busy: false,
        error: ok ? null : session.state.error ?? failure,
      ),
    );
    if (ok) await load();
    return ok;
  }

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}
