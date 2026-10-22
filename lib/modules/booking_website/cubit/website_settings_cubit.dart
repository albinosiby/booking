import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/website_settings.dart';
import '../repositories/website_repository.dart';
import 'website_settings_state.dart';

class WebsiteSettingsCubit extends Cubit<WebsiteSettingsState> {
  WebsiteSettingsCubit(this.session, this.repository)
    : super(const WebsiteSettingsState()) {
    scope = workspaceAccessScope(session.state.data);
    subscription = session.snapshots.listen((_) {
      if (scope != workspaceAccessScope(session.state.data)) {
        generation++;
        emit(
          const WebsiteSettingsState(
            loading: false,
            error: 'Your workspace changed. Reopen Booking website.',
          ),
        );
      }
    });
  }
  final WorkspaceSession session;
  final WebsiteRepository repository;
  late final String scope;
  late final StreamSubscription subscription;
  int generation = 0;
  bool get owner =>
      session.state.data.isOwner &&
      session.state.data.organization != null &&
      scope == workspaceAccessScope(session.state.data);
  bool valid(int g) => !isClosed && owner && g == generation;
  String failure(Object e) => e is AppException
      ? e.message
      : 'Could not complete this action. Please retry.';
  Future<void> load() async {
    if (!owner) {
      emit(
        const WebsiteSettingsState(
          loading: false,
          error: 'Only the owner can manage the booking website.',
        ),
      );
      return;
    }
    if (state.busy) return;
    final g = ++generation;
    emit(state.copyWith(loading: state.saved == null));
    try {
      final saved = await repository.settings();
      if (valid(g)) {
        emit(WebsiteSettingsState(saved: saved, draft: saved, loading: false));
      }
    } catch (e) {
      if (valid(g)) emit(state.copyWith(loading: false, error: failure(e)));
    }
  }

  void update(WebsiteSettings draft) {
    if (owner && !state.busy && !state.loading) {
      emit(state.copyWith(draft: draft));
    }
  }

  void toggleBusiness(String id, bool enabled) {
    final draft = state.draft;
    if (draft == null) return;
    final ids = [...draft.businessIds]..remove(id);
    if (enabled) ids.add(id);
    update(draft.copyWith(businessIds: ids));
  }

  Future<void> save({String? action}) async {
    if (!owner || state.busy || state.draft == null) return;
    final g = ++generation, draft = state.draft!;
    emit(state.copyWith(busy: true));
    try {
      var saved = state.dirty ? await repository.save(draft) : state.saved!;
      if (!valid(g)) return;
      emit(state.copyWith(saved: saved, draft: saved, busy: true));
      if (action != null) {
        saved = await repository.publication(action, saved.version);
      }
      if (valid(g)) {
        emit(
          WebsiteSettingsState(
            saved: saved,
            draft: saved,
            loading: false,
            message: action == 'publish'
                ? 'Your booking website is published.'
                : action == 'pause'
                ? 'Online bookings are paused.'
                : action == 'unpublish'
                ? 'The website is unpublished.'
                : 'Website settings saved.',
          ),
        );
      }
    } catch (e) {
      if (valid(g)) {
        emit(
          state.copyWith(
            busy: false,
            error:
                '${failure(e)} Reload settings before retrying an uncertain save.',
          ),
        );
      }
    }
  }

  Future<void> photo({
    String? businessId,
    String? resourceId,
    String? removeId,
  }) async {
    if (!owner || state.busy || state.draft == null || state.dirty) return;
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      final version = state.saved!.version;
      WebsiteSettings saved;
      if (removeId != null) {
        saved = await repository.removeImage(removeId, version);
      } else {
        final image = await repository.pickImage();
        if (!valid(g)) return;
        if (image == null) {
          emit(state.copyWith(busy: false));
          return;
        }
        saved = await repository.uploadImage(
          image,
          version,
          businessId: businessId,
          resourceId: resourceId,
        );
      }
      if (valid(g)) {
        emit(
          WebsiteSettingsState(
            saved: saved,
            draft: saved,
            loading: false,
            message: removeId == null
                ? 'Website photo saved.'
                : 'Website photo removed.',
          ),
        );
      }
    } catch (e) {
      if (valid(g)) {
        emit(
          state.copyWith(
            busy: false,
            error:
                '${failure(e)} Reload settings before retrying an uncertain upload.',
          ),
        );
      }
    }
  }

  Future<void> link({bool preview = false, bool copy = false}) async {
    if (!owner || state.busy || state.saved == null || state.dirty) return;
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      final url = preview ? await repository.preview() : state.saved!.url;
      if (!valid(g)) return;
      if (url == null) {
        throw const AppException(
          'Configure the public website URL on the API first.',
        );
      }
      if (copy) {
        await repository.copy(url);
      } else {
        await repository.open(url);
      }
      if (valid(g)) {
        emit(
          state.copyWith(
            busy: false,
            message: copy ? 'Website link copied.' : null,
          ),
        );
      }
    } catch (e) {
      if (valid(g)) emit(state.copyWith(busy: false, error: failure(e)));
    }
  }

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}
