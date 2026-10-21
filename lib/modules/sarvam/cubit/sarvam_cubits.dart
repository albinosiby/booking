import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/sarvam_models.dart';
import '../repositories/sarvam_repository.dart';

String sarvamError(Object error) => error is AppException
    ? error.message
    : 'Could not complete this action. Please try again.';

/// Owner-only cubit that stops emitting results once the workspace scope changes.
abstract class OwnerSarvamCubit<S> extends Cubit<S> {
  OwnerSarvamCubit(this.session, this.repository, S initial) : super(initial) {
    scope = workspaceAccessScope(session.state.data);
    subscription = session.snapshots.listen((_) {
      if (scope != workspaceAccessScope(session.state.data)) {
        generation++;
        emit(accessReset());
      }
    });
  }
  final WorkspaceSession session;
  final SarvamRepository repository;
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

class SarvamSettingsCubit extends OwnerSarvamCubit<SarvamSettingsState> {
  SarvamSettingsCubit(WorkspaceSession session, SarvamRepository repository)
    : super(session, repository, const SarvamSettingsState());
  @override
  SarvamSettingsState accessReset() => const SarvamSettingsState(
    loading: false,
    error: 'Only the owner can manage the Sarvam voice agent.',
  );
  Future<void> load() async {
    if (!owner) {
      emit(accessReset());
      return;
    }
    final g = ++generation;
    emit(state.copyWith(loading: true));
    try {
      final s = await repository.settings();
      if (valid(g)) emit(state.fromSaved(s));
    } catch (e) {
      if (valid(g)) emit(state.copyWith(loading: false, error: sarvamError(e)));
    }
  }

  void update({
    bool? enabled,
    String? orgId,
    String? workspaceId,
    String? appId,
    String? apiKey,
  }) => emit(
    state.copyWith(
      enabled: enabled,
      orgId: orgId?.trim(),
      workspaceId: workspaceId?.trim(),
      appId: appId?.trim(),
      apiKey: apiKey?.trim(),
    ),
  );
  void toggleBusiness(String id, bool on) => emit(
    state.copyWith(
      businessIds: on
          ? {...state.businessIds, id}
          : ({...state.businessIds}..remove(id)),
    ),
  );

  String? validate() {
    final ids = [state.orgId, state.workspaceId, state.appId];
    final anyId = ids.any((v) => v.isNotEmpty);
    if (anyId && ids.any((v) => v.isEmpty)) {
      return 'Enter the organization, workspace and app IDs together.';
    }
    if (ids.any(
      (v) => v.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(v),
    )) {
      return 'IDs contain only letters, numbers, hyphens and underscores.';
    }
    if (state.apiKey.isNotEmpty && state.apiKey.length < 8) {
      return 'The Sarvam API key looks too short.';
    }
    if (state.enabled && state.businessIds.isEmpty) {
      return 'Choose at least one business the voice agent can book.';
    }
    if (state.enabled && !state.saved.hasToolKey) {
      return 'Generate a voice tool key before turning the agent on.';
    }
    return null;
  }

  Future<void> save() async {
    if (!owner || state.busy) return;
    final invalid = validate();
    if (invalid != null) {
      emit(state.copyWith(error: invalid));
      return;
    }
    await _run(() async {
      final saved = await repository.save(
        version: state.saved.version,
        enabled: state.enabled,
        businessIds: state.businessIds,
        orgId: state.orgId,
        workspaceId: state.workspaceId,
        appId: state.appId,
        apiKey: state.apiKey.isEmpty ? null : state.apiKey,
      );
      return state.fromSaved(saved).copyWith(notice: 'Sarvam settings saved.');
    });
  }

  Future<void> rotateToolKey() => _run(() async {
    final key = await repository.rotateToolKey();
    final saved = await repository.settings();
    // Keep unsaved edits; only the key and version come from the server.
    return SarvamSettingsState(
      saved: saved,
      enabled: state.enabled,
      orgId: state.orgId,
      workspaceId: state.workspaceId,
      appId: state.appId,
      apiKey: state.apiKey,
      businessIds: state.businessIds,
      loading: false,
      newToolKey: key,
    );
  });

  Future<void> test() => _run(() async {
    final count = await repository.test();
    return state.copyWith(
      notice:
          'Connected to Sarvam. $count call${count == 1 ? '' : 's'} in the last 24 hours.',
    );
  });

  Future<void> _run(Future<SarvamSettingsState> Function() work) async {
    if (!owner || state.busy) return;
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      final next = await work();
      if (valid(g)) emit(next);
    } catch (e) {
      if (valid(g)) emit(state.copyWith(busy: false, error: sarvamError(e)));
    }
  }
}

class CallLogsCubit extends OwnerSarvamCubit<CallLogsState> {
  CallLogsCubit(WorkspaceSession session, SarvamRepository repository)
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
      if (valid(g)) emit(state.copyWith(loading: false, error: sarvamError(e)));
    }
  }
}

class CallDetailCubit extends OwnerSarvamCubit<CallDetailState> {
  CallDetailCubit(
    WorkspaceSession session,
    SarvamRepository repository,
    this.saver,
    this.call,
  ) : super(session, repository, const CallDetailState());
  final RecordingSaver saver;
  final SarvamCall call;
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
      if (valid(g)) emit(state.copyWith(loading: false, error: sarvamError(e)));
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
      if (valid(g)) emit(state.copyWith(saving: false, error: sarvamError(e)));
    }
  }
}
