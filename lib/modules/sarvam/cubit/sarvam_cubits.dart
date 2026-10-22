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
    if (state.busy) return;
    final g = ++generation;
    emit(state.copyWith(loading: state.saved.version == 0));
    try {
      final saved = await repository.settings();
      if (valid(g)) {
        emit(
          state.dirty && !state.loading
              ? state.copyWith(saved: saved, loading: false)
              : state.fromSaved(saved),
        );
      }
    } catch (e) {
      if (valid(g)) emit(state.copyWith(loading: false, error: sarvamError(e)));
    }
  }

  void update({
    String? orgId,
    String? workspaceId,
    String? appId,
    String? apiKey,
  }) => emit(
    state.copyWith(
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
    if ([
      state.orgId,
      state.workspaceId,
      state.appId,
    ].any((v) => !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(v))) {
      return 'Enter the organization, workspace and app IDs from Sarvam.';
    }
    if ((!state.saved.hasCredentials || state.apiKey.isNotEmpty) &&
        state.apiKey.length < 8) {
      return 'Enter a valid Sarvam workspace API key.';
    }
    if (state.businessIds.isEmpty) {
      return 'Choose at least one business the voice agent can book.';
    }
    return null;
  }

  Future<void> connect() async {
    if (!owner || state.busy) return;
    final error = validate();
    if (error != null) {
      emit(state.copyWith(error: error));
      return;
    }
    await _run(
      () => repository.connect(
        version: state.saved.version,
        businessIds: state.businessIds,
        orgId: state.orgId,
        workspaceId: state.workspaceId,
        appId: state.appId,
        apiKey: state.apiKey.isEmpty ? null : state.apiKey,
      ),
      drive: true,
    );
  }

  Future<void> continueSetup() => _run(repository.settings, drive: true);
  Future<void> authorize() async {
    if (!owner || state.busy || state.saved.authorizationUrl.isEmpty) return;
    final g = generation;
    try {
      final opened = await repository.openAuthorization(
        state.saved.authorizationUrl,
      );
      if (!valid(g)) return;
      if (!opened) {
        emit(
          state.copyWith(
            error:
                'Could not open Sarvam sign-in. Allow browser popups and retry.',
          ),
        );
      }
    } catch (e) {
      if (valid(g)) {
        emit(state.copyWith(error: sarvamError(e)));
      }
    }
  }

  Future<void> setBookingEnabled(bool enabled) async {
    if (!owner) return;
    if (!enabled && state.busy) {
      generation++;
      emit(state.copyWith(busy: false));
    }
    await _run(
      () => repository.setBookingEnabled(state.saved.version, enabled),
      preserveEdits: true,
    );
  }

  Future<void> disconnect() async {
    if (!owner) return;
    // Supersede a pending setup request; the backend fences its checkpoint too.
    generation++;
    emit(state.copyWith(busy: false, apiKey: ''));
    await _run(repository.disconnect, drive: true);
  }

  Future<void> publish(String deploymentId) => _run(
    () => repository.publish(state.saved.version, deploymentId),
    drive: true,
  );
  Future<void> test() async {
    if (!owner || state.busy) return;
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      final count = await repository.test();
      if (valid(g)) {
        emit(
          state.copyWith(
            busy: false,
            notice: 'Call logs connected. $count calls in the last 24 hours.',
          ),
        );
      }
    } catch (e) {
      if (valid(g)) emit(state.copyWith(busy: false, error: sarvamError(e)));
    }
  }

  Future<void> _run(
    Future<SarvamSettings> Function() work, {
    bool drive = false,
    bool preserveEdits = false,
  }) async {
    if (!owner || state.busy) return;
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      var saved = await work();
      if (!valid(g)) return;
      emit(
        (preserveEdits ? state.copyWith(saved: saved) : state.fromSaved(saved))
            .copyWith(busy: drive),
      );
      if (drive) {
        for (var step = 0; saved.needsWork && step < 30; step++) {
          if (!valid(g)) return;
          saved = await repository.setupStep();
          if (!valid(g)) return;
          emit(state.fromSaved(saved).copyWith(busy: saved.needsWork));
        }
        if (!valid(g)) return;
        emit(
          state.copyWith(
            busy: false,
            notice: saved.status == 'authorization_required'
                ? 'Authorize Sarvam, then return here and continue setup.'
                : saved.statusLabel,
          ),
        );
        if (saved.status == 'authorization_required') await authorize();
      }
    } catch (e) {
      if (!valid(g)) return;
      // Recover durable progress even when a request timed out after saving it.
      try {
        final saved = await repository.settings();
        if (valid(g)) {
          emit(
            (preserveEdits
                    ? state.copyWith(saved: saved)
                    : state.fromSaved(saved))
                .copyWith(busy: false, error: sarvamError(e)),
          );
        }
      } catch (_) {
        if (valid(g)) emit(state.copyWith(busy: false, error: sarvamError(e)));
      }
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
