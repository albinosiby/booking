import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../workspace/repositories/refreshable_reads.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../repositories/team_repository.dart';
import '../models/team_screen_model.dart';
export '../models/team_screen_model.dart';

typedef TeamState = TeamScreenModel;

class TeamCubit extends Cubit<TeamState> {
  TeamCubit(this.repository) : super(const TeamState()) {
    if (repository is RetainedReadEvents) {
      changes = (repository as RetainedReadEvents).readChanges.listen((_) {
        if (!state.busy) load();
      });
    }
  }
  StreamSubscription? changes;
  int generation = 0;
  @override
  Future<void> close() async {
    generation++;
    await changes?.cancel();
    return super.close();
  }

  final TeamRepository repository;
  Future<void> load() async {
    if (isClosed) return;
    final g = ++generation;
    emit(TeamState(members: state.members, invitations: state.invitations));
    try {
      final data = await repository.load();
      if (!isClosed && g == generation) {
        emit(
          TeamState(
            loading: false,
            members: List.unmodifiable(
              (data['members'] as List).map(
                (m) => Map<String, dynamic>.unmodifiable(m),
              ),
            ),
            invitations: List.unmodifiable(
              (data['invitations'] as List).map(
                (m) => Map<String, dynamic>.unmodifiable(m),
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (!isClosed && g == generation) {
        emit(
          TeamState(
            loading: false,
            members: accessFailure(e) ? const [] : state.members,
            invitations: accessFailure(e) ? const [] : state.invitations,
            error: e is AppException ? e.message : 'Could not load your team.',
          ),
        );
      }
    }
  }

  Future<void> revoke(String id, {bool invitation = false}) async {
    if (state.busy) return;
    emit(
      TeamState(
        loading: false,
        members: state.members,
        invitations: state.invitations,
        busy: true,
      ),
    );
    try {
      await repository.revoke(id, invitation: invitation);
      await load();
    } catch (e) {
      if (!isClosed) {
        emit(
          TeamState(
            loading: false,
            members: state.members,
            invitations: state.invitations,
            error: e is AppException ? e.message : 'Could not remove access.',
          ),
        );
      }
    }
  }
}
