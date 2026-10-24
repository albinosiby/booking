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
  Future<void> load({bool afterMutation = false, String? notice}) async {
    if (isClosed || state.busy && !afterMutation) return;
    final g = ++generation;
    emit(
      TeamState(
        members: state.members,
        invitations: state.invitations,
        busy: afterMutation,
        notice: notice,
      ),
    );
    try {
      final data = await repository.load();
      if (!isClosed && g == generation) {
        emit(
          TeamState(
            loading: false,
            notice: notice,
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
            notice: notice,
          ),
        );
      }
    }
  }

  Future<void> revoke(String id, {bool invitation = false}) => _mutate(
    () async {
      await repository.revoke(id, invitation: invitation);
      if (!invitation && !isClosed) {
        // Keep the confirmed removal visible even if the follow-up read fails.
        emit(
          TeamState(
            loading: false,
            busy: true,
            invitations: state.invitations,
            members: List.unmodifiable([
              for (final member in state.members)
                if (member['id'] == id)
                  Map<String, dynamic>.unmodifiable({
                    ...member,
                    'active': false,
                    'assignments': <Object>[],
                  })
                else
                  member,
            ]),
          ),
        );
      }
      return invitation
          ? 'Pending access cancelled.'
          : 'Member removed. History preserved.';
    },
  );

  Future<void> resendEmail(String id) => _mutate(() async {
    final result = await repository.resendEmail(id);
    return result.sent
        ? 'Access email sent.'
        : 'Email could not be sent. Check the server SMTP settings before retrying. Their saved access is still available.';
  });

  Future<void> _mutate(Future<String> Function() action) async {
    if (isClosed || state.busy) return;
    generation++;
    emit(
      TeamState(
        loading: false,
        members: state.members,
        invitations: state.invitations,
        busy: true,
      ),
    );
    try {
      final notice = await action();
      await load(afterMutation: true, notice: notice);
    } catch (e) {
      if (!isClosed) {
        emit(
          TeamState(
            loading: false,
            members: state.members,
            invitations: state.invitations,
            error: e is AppException
                ? e.message
                : 'Could not update your team. Refresh and try again.',
          ),
        );
      }
    }
  }
}
