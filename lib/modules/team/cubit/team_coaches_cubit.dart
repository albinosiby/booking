import '../../pool/models/pool_configuration.dart' show poolCoachPhoneValid;
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
  Future<void> load() async {
    if (!authorized || state.busy) return;
    final g = ++generation;
    emit(state.copy(loading: true));
    try {
      final businesses = await repository.load();
      if (!isClosed && g == generation && authorized) {
        emit(state.copy(businesses: businesses, loading: false));
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(
          state.copy(
            loading: false,
            businesses: accessFailure(e) ? [] : null,
            error: e is AppException ? e.message : 'Could not load coaches.',
          ),
        );
      }
    }
  }

  void beginAdd() {
    if (!authorized || state.busy || state.businesses.isEmpty) return;
    emit(
      state.copy(
        editor: CoachEditor.add,
        businessId: state.businesses.first.id,
        name: '',
        phone: '',
        planIds: [],
      ),
    );
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
        editor: CoachEditor.assign,
        businessId: businessId,
        coachId: coachId,
        planIds: business.plans
            .where((p) => p.coachId == coachId)
            .map((p) => p.id),
      ),
    );
  }

  void beginSpaces(String businessId, String coachId) {
    if (!authorized || state.busy) return;
    final b = state.businesses.where((b) => b.id == businessId).firstOrNull;
    final coach = b?.coaches.where((c) => c.id == coachId).firstOrNull;
    if (coach == null) return;
    emit(
      state.copy(
        editor: CoachEditor.spaces,
        businessId: businessId,
        coachId: coachId,
        spaceIds: coach.poolIds,
      ),
    );
  }

  void toggleSpace(String id, bool selected) {
    if (state.busy || state.editor != CoachEditor.spaces) return;
    final ids = {...state.spaceIds};
    if (selected) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    emit(state.copy(spaceIds: ids));
  }

  void business(String value) {
    if (!state.busy) emit(state.copy(businessId: value));
  }

  void name(String value) {
    if (!state.busy) emit(state.copy(name: value));
  }

  void phone(String value) {
    if (!state.busy) emit(state.copy(phone: value));
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

  void closeEditor() {
    if (!isClosed && !state.busy) {
      emit(state.copy(clearEditor: true, error: state.error));
    }
  }

  Future<bool> saveEditor({bool removeAffectedPlans = false}) async {
    if (!authorized || state.busy || state.loading || state.editor == null) {
      return false;
    }
    final b = state.selectedBusiness;
    if (b == null) return false;
    if (state.editor == CoachEditor.add &&
        (state.name.trim().length < 2 ||
            state.name.trim().length > 100 ||
            !poolCoachPhoneValid(state.phone))) {
      emit(
        state.copy(error: 'Enter the coach’s name and a valid phone number.'),
      );
      return false;
    }
    if (state.editor == CoachEditor.spaces &&
        state.affectedPlans.isNotEmpty &&
        !removeAffectedPlans) {
      emit(
        state.copy(
          error: 'Confirm removal of the affected coaching-plan assignments.',
        ),
      );
      return false;
    }
    final g = ++generation;
    final draft = state;
    emit(state.copy(busy: true));
    final ok = await session.change(
      () => switch (draft.editor!) {
        CoachEditor.add => repository.add(
          b.id,
          b.version,
          draft.name,
          draft.phone,
        ),
        CoachEditor.assign => repository.assign(
          b.id,
          b.version,
          draft.coachId!,
          draft.planIds,
        ),
        CoachEditor.spaces => repository.assignSpaces(
          b.id,
          b.version,
          draft.coachId!,
          draft.spaceIds,
          removeAffectedPlans: removeAffectedPlans,
        ),
      },
    );
    if (isClosed || g != generation || !authorized) return false;
    emit(
      state.copy(
        busy: false,
        error: ok
            ? null
            : session.state.error ??
                  'Could not save coaches. Refresh and retry.',
      ),
    );
    if (ok) {
      await load();
    }
    return ok;
  }

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}
