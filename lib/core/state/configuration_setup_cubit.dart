import 'dart:async';
import 'dart:convert';
import 'package:flutter/widgets.dart';
import '../../config/app_config.dart';
import '../../modules/workspace/models/workspace_state.dart';
import '../../modules/configuration_drafts/models/configuration_draft.dart';
import '../../modules/configuration_drafts/repositories/configuration_draft_repository.dart';
import 'workspace_screen_cubit.dart';

/// Local writes are serialized and coalesced; navigation never awaits storage.
abstract class ConfigurationSetupCubit<M extends WorkspaceState>
    extends WorkspaceScreenCubit<M>
    with WidgetsBindingObserver {
  ConfigurationSetupCubit(super.session, super.model);
  ConfigurationDraftRepository? _draftRepository;
  StreamSubscription<M>? _draftSubscription;
  Timer? _draftTimer;
  Future<void> _writes = Future.value();
  String? _scope, _lastPayload;
  bool _loadFailed = false,
      _cleanupFailed = false,
      _loadingDraft = false,
      _closingDraft = false,
      _conflict = false;
  int _generation = 0;
  bool get hasDraftChanges;
  int get draftBaseVersion;
  ConfigurationDraft captureLocalDraft();
  void restoreLocalDraft(ConfigurationDraft draft);
  void setLocalDraftStatus(LocalDraftStatus status, String? message);
  bool get localDraftConflict => _conflict;
  String? _currentScope(String businessId) {
    final data = state.data;
    if (!data.isOwner ||
        data.organization == null ||
        data.membership?['id'] == null) {
      return null;
    }
    return jsonEncode([
      AppConfig.useSupabase ? AppConfig.supabaseUrl : AppConfig.apiUrl,
      data.organization!.id,
      data.membership!['id'],
      businessId,
    ]);
  }

  late String _draftBusiness;
  Future<void> initializeLocalDraft(
    ConfigurationDraftRepository? repository,
    String businessId,
  ) async {
    if (repository == null) return;
    _draftRepository = repository;
    _draftBusiness = businessId;
    _scope = _currentScope(businessId);
    if (_scope == null) return;
    WidgetsBinding.instance.addObserver(this);
    _loadingDraft = true;
    _loadFailed = false;
    setLocalDraftStatus(LocalDraftStatus.loading, null);
    _draftSubscription = stream.listen((_) {
      if (_loadingDraft ||
          _closingDraft ||
          !hasDraftChanges ||
          _currentScope(_draftBusiness) != _scope) {
        return;
      }
      final payload = jsonEncode(captureLocalDraft().toJson());
      if (payload == _lastPayload) return;
      _lastPayload = payload;
      _draftTimer?.cancel();
      setLocalDraftStatus(
        _conflict ? LocalDraftStatus.conflict : LocalDraftStatus.saving,
        _conflict
            ? 'Newer settings exist online. Your local draft is kept; reload saved settings before publishing.'
            : null,
      );
      _draftTimer = Timer(const Duration(milliseconds: 300), () {
        unawaited(flushLocalDraft());
      });
    });
    try {
      final draft = await repository.read(_scope!);
      if (isClosed || _closingDraft || _currentScope(businessId) != _scope) {
        return;
      }
      if (draft != null) {
        _conflict = draft.baseVersion != draftBaseVersion;
        restoreLocalDraft(draft);
        _lastPayload = jsonEncode(captureLocalDraft().toJson());
        setLocalDraftStatus(
          _conflict ? LocalDraftStatus.conflict : LocalDraftStatus.saved,
          _conflict
              ? 'Newer settings exist online. Your local draft is kept; reload saved settings before publishing.'
              : 'Restored your draft from this device.',
        );
      } else {
        setLocalDraftStatus(LocalDraftStatus.idle, null);
      }
    } catch (_) {
      _loadFailed = true;
      if (!isClosed && !_closingDraft) {
        setLocalDraftStatus(
          LocalDraftStatus.loadFailed,
          'Could not load the local draft. Your saved online settings are shown.',
        );
      }
    } finally {
      _loadingDraft = false;
    }
  }

  Future<void> flushLocalDraft({bool force = false}) {
    _draftTimer?.cancel();
    if (_draftRepository == null ||
        _scope == null ||
        _loadingDraft ||
        (!hasDraftChanges && !force) ||
        _currentScope(_draftBusiness) != _scope) {
      return _writes;
    }
    final draft = captureLocalDraft(), generation = _generation;
    _writes = _writes.then((_) async {
      if (generation != _generation) return;
      try {
        await _draftRepository!.write(_scope!, draft);
        if (!isClosed &&
            !_closingDraft &&
            generation == _generation &&
            jsonEncode(captureLocalDraft().toJson()) ==
                jsonEncode(draft.toJson())) {
          setLocalDraftStatus(
            _conflict ? LocalDraftStatus.conflict : LocalDraftStatus.saved,
            _conflict
                ? 'Newer settings exist online. Your local draft is kept; reload saved settings before publishing.'
                : null,
          );
        }
      } catch (_) {
        if (!isClosed && !_closingDraft && generation == _generation) {
          setLocalDraftStatus(
            LocalDraftStatus.failed,
            'Could not save your draft on this device. Keep this screen open and retry.',
          );
        }
      }
    });
    return _writes;
  }

  void checkpointLocalDraft() {
    unawaited(flushLocalDraft());
  }

  Future<void> retryLocalDraft() async {
    if (_loadFailed) {
      await _draftSubscription?.cancel();
      WidgetsBinding.instance.removeObserver(this);
      await initializeLocalDraft(_draftRepository, _draftBusiness);
    } else if (_cleanupFailed) {
      await clearLocalDraft();
    } else {
      await flushLocalDraft();
    }
  }

  Future<void> clearLocalDraft() async {
    _generation++;
    _draftTimer?.cancel();
    _conflict = false;
    _cleanupFailed = false;
    _lastPayload = null;
    if (_draftRepository == null || _scope == null) return;
    _writes = _writes.then((_) async {
      try {
        await _draftRepository!.remove(_scope!);
        if (!isClosed && !_closingDraft) {
          setLocalDraftStatus(LocalDraftStatus.idle, null);
        }
      } catch (_) {
        _cleanupFailed = true;
        if (!isClosed && !_closingDraft) {
          setLocalDraftStatus(
            LocalDraftStatus.failed,
            'Settings were saved online, but the old local draft could not be cleared. Retry local cleanup.',
          );
        }
      }
    });
    await _writes;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      checkpointLocalDraft();
    }
  }

  @override
  Future<void> close() async {
    _closingDraft = true;
    _draftTimer?.cancel();
    await _draftSubscription?.cancel();
    if (_draftRepository != null && _scope != null) {
      WidgetsBinding.instance.removeObserver(this);
      await flushLocalDraft();
    }
    return super.close();
  }
}
