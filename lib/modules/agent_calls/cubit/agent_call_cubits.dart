import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/agent_call_models.dart';
import '../repositories/agent_call_repository.dart';

String agentCallError(Object error) => error is AppException
    ? error.message
    : 'Could not complete this action. Please try again.';

/// Owner-only cubit that stops emitting results once the workspace scope changes.
abstract class OwnerAgentCubit<S> extends Cubit<S> {
  OwnerAgentCubit(this.session, this.repository, S initial) : super(initial) {
    scope = workspaceAccessScope(session.state.data);
    subscription = session.snapshots.listen((_) {
      if (scope != workspaceAccessScope(session.state.data)) {
        generation++;
        emit(accessReset());
      }
    });
  }
  final WorkspaceSession session;
  final AgentCallRepository repository;
  late final String scope;
  late final StreamSubscription subscription;
  int generation = 0;
  bool get owner =>
      session.state.data.organization != null &&
      scope == workspaceAccessScope(session.state.data) &&
      session.state.data.isOwner;
  bool valid(int g) => !isClosed && owner && g == generation;
  S accessReset();
  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}

class AgentServiceCubit extends OwnerAgentCubit<AgentServiceState> {
  AgentServiceCubit(WorkspaceSession session, AgentCallRepository repository)
    : super(session, repository, const AgentServiceState());
  @override
  AgentServiceState accessReset() => const AgentServiceState(
    loading: false,
    error: 'Only the owner can manage the agent call service.',
  );
  Future<void> _run(Future<AgentServiceStatus> Function() work) async {
    if (!owner) return emit(accessReset());
    final g = ++generation;
    try {
      final status = await work();
      if (valid(g)) {
        emit(AgentServiceState(status: status, loading: false));
      }
    } catch (e) {
      if (valid(g)) {
        emit(state.copyWith(loading: false, busy: false, error: agentCallError(e)));
      }
    }
  }

  Future<void> load() {
    emit(state.copyWith(error: null));
    return _run(repository.status);
  }

  Future<void> request(String note) {
    emit(state.copyWith(busy: true, error: null));
    return _run(() => repository.request(note));
  }

  Future<void> setEnabled(bool enabled) {
    emit(state.copyWith(busy: true, error: null));
    return _run(() => repository.setEnabled(enabled));
  }
}

class CallLogsCubit extends OwnerAgentCubit<CallLogsState> {
  CallLogsCubit(WorkspaceSession session, AgentCallRepository repository)
    : super(session, repository, CallLogsState(day: _today()));
  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  @override
  CallLogsState accessReset() => CallLogsState(
    day: state.day,
    loading: false,
    error: 'Only the owner can view call logs.',
  );
  Future<void> load([DateTime? day]) async {
    if (!owner) {
      emit(accessReset());
      return;
    }
    final d = day ?? state.day;
    final g = ++generation;
    emit(state.copyWith(day: d, loading: true));
    try {
      final page = await repository.calls(
        d,
        DateTime(d.year, d.month, d.day + 1),
      );
      if (valid(g)) emit(state.copyWith(page: page, loading: false));
    } catch (e) {
      if (valid(g)) emit(state.copyWith(loading: false, error: agentCallError(e)));
    }
  }
}

class CallDetailCubit extends OwnerAgentCubit<CallDetailState> {
  CallDetailCubit(
    WorkspaceSession session,
    AgentCallRepository repository,
    this.saver,
    this.call,
  ) : super(session, repository, const CallDetailState());
  final RecordingSaver saver;
  final AgentCall call;
  @override
  CallDetailState accessReset() => const CallDetailState(
    loading: false,
    error: 'Only the owner can view call logs.',
  );
  Future<void> load() async {
    if (!owner) {
      emit(accessReset());
      return;
    }
    final g = ++generation;
    emit(state.copyWith(loading: true));
    try {
      final lines = await repository.transcript(call.id);
      if (valid(g)) emit(state.copyWith(lines: lines, loading: false));
    } catch (e) {
      if (valid(g)) emit(state.copyWith(loading: false, error: agentCallError(e)));
    }
  }

  Future<void> saveRecording() async {
    if (!owner || state.saving) return;
    final g = generation;
    emit(state.copyWith(saving: true));
    try {
      final bytes = await repository.recording(call.id);
      final name =
          'call-${call.id.replaceAll(RegExp(r'[^A-Za-z0-9-]'), '-')}.wav';
      final saved = await saver.save(bytes, name);
      if (valid(g)) {
        emit(
          state.copyWith(
            saving: false,
            notice: saved ? 'Recording saved.' : null,
          ),
        );
      }
    } catch (e) {
      if (valid(g)) emit(state.copyWith(saving: false, error: agentCallError(e)));
    }
  }
}
