import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../../utils/services/logo_picker_service.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/website_settings.dart';
import '../models/website_autosave.dart';
import '../repositories/website_repository.dart';
import 'website_settings_state.dart';

class WebsiteSettingsCubit extends Cubit<WebsiteSettingsState> {
  WebsiteSettingsCubit(this.session, this.repository, {this.autosaveDelay})
    : super(const WebsiteSettingsState()) {
    scope = workspaceAccessScope(session.state.data);
    subscription = session.snapshots.listen((_) {
      if (scope != workspaceAccessScope(session.state.data)) {
        generation++;
        _autosaveTimer?.cancel();
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

  /// Null preserves explicit-save mode for other consumers; app DI enables autosave.
  final Duration? autosaveDelay;
  bool get autosaveEnabled => autosaveDelay != null;
  Timer? _autosaveTimer;
  Future<void>? _writeInFlight;
  String? get pendingValidation =>
      state.draft == null ? null : websiteAutosaveError(state.draft!);
  void _scheduleAutosave() {
    _autosaveTimer?.cancel();
    if (!autosaveEnabled ||
        !owner ||
        state.busy ||
        state.autosaving ||
        !state.dirty ||
        state.draft == null) {
      return;
    }
    _autosaveTimer = Timer(autosaveDelay!, () {
      if (pendingValidation == null) unawaited(save(automatic: true));
    });
  }

  Future<bool> flushAutosave() async {
    _autosaveTimer?.cancel();
    await _writeInFlight;
    if (isClosed || !owner) return false;
    if (state.dirty) await save();
    return !state.dirty && !state.busy && !state.autosaving;
  }

  int generation = 0;
  int photoSequence = 0;
  bool get owner =>
      !isClosed &&
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
    if (state.busy || state.autosaving) return;
    _autosaveTimer?.cancel();
    final g = ++generation;
    emit(state.copyWith(loading: state.saved == null));
    try {
      final saved = await repository.settings();
      if (valid(g)) {
        emit(
          WebsiteSettingsState(
            saved: saved,
            draft: saved,
            loading: false,
            revision: state.revision + 1,
          ),
        );
      }
    } catch (e) {
      if (valid(g)) emit(state.copyWith(loading: false, error: failure(e)));
    }
  }

  void update(WebsiteSettings draft) {
    if (owner && !state.busy && !state.loading) {
      emit(state.copyWith(draft: draft));
      _scheduleAutosave();
    }
  }

  void toggleBusiness(String id, bool enabled) {
    final draft = state.draft;
    if (draft == null) return;
    final ids = [...draft.businessIds]..remove(id);
    if (enabled) ids.add(id);
    update(draft.copyWith(businessIds: ids));
  }

  void updateBusiness(String id, WebsiteBusiness Function(WebsiteBusiness) f) {
    final draft = state.draft;
    if (draft == null) return;
    update(
      draft.copyWith(
        businesses: [for (final b in draft.businesses) b.id == id ? f(b) : b],
      ),
    );
  }

  void updateSpace(String businessId, WebsiteSpace space) => updateBusiness(
    businessId,
    (b) => b.copyWith(
      spaces: [for (final s in b.spaces) s.id == space.id ? space : s],
    ),
  );

  /// Applies one space's booking rules to every space on the website.
  void copyRulesToAll(WebsiteSpace source) {
    final draft = state.draft;
    if (draft == null || !owner || state.busy || state.loading) return;
    emit(
      state.copyWith(
        draft: draft.copyWith(
          businesses: [
            for (final b in draft.businesses)
              b.copyWith(
                spaces: [for (final s in b.spaces) s.withRulesOf(source)],
              ),
          ],
        ),
        revision: state.revision + 1,
        message: autosaveEnabled
            ? 'Booking rules copied. Changes save automatically.'
            : 'Booking rules copied to all spaces. Save to apply them.',
      ),
    );
    _scheduleAutosave();
  }

  /// Saves the address against the last server version, retaining other edits.
  Future<void> saveAddress() async {
    if (_writeInFlight != null) return;
    _autosaveTimer?.cancel();
    if (!owner ||
        state.busy ||
        state.loading ||
        state.saved == null ||
        state.draft == null ||
        !state.addressDirty) {
      return;
    }
    final draft = state.draft!;
    final slug = draft.slug.trim().toLowerCase();
    final error = websiteAddressError(slug);
    if (error != null) {
      emit(state.copyWith(addressError: error));
      return;
    }
    final g = ++generation;
    emit(state.copyWith(busy: true, savingAddress: true));
    try {
      final saved = await repository.save(state.saved!.copyWith(slug: slug));
      if (!valid(g)) return;
      emit(
        state.copyWith(
          saved: saved,
          draft: draft.copyWith(
            slug: saved.slug,
            version: saved.version,
            url: saved.url,
          ),
          busy: false,
          savingAddress: false,
          revision: state.revision + 1,
          message: 'Website address saved.',
        ),
      );
    } catch (e) {
      if (valid(g)) {
        emit(
          state.copyWith(
            busy: false,
            savingAddress: false,
            addressError: failure(e),
          ),
        );
      }
    }
    if (valid(g) && state.error == null && state.addressError == null) {
      _scheduleAutosave();
    }
  }

  Future<void> save({String? action, bool automatic = false}) async {
    _autosaveTimer?.cancel();
    if (_writeInFlight != null) {
      if (state.busy || automatic || action == null) return;
      await _writeInFlight;
    }
    if (!owner || state.busy || state.saved == null || state.draft == null) {
      return;
    }
    if (autosaveEnabled && pendingValidation != null) {
      emit(state.copyWith(error: pendingValidation));
      return;
    }
    final completion = Completer<void>();
    _writeInFlight = completion.future;
    try {
      await _saveNow(action: action, automatic: automatic);
    } finally {
      _writeInFlight = null;
      completion.complete();
      if (!isClosed && state.error == null) _scheduleAutosave();
    }
  }

  Future<void> _saveNow({String? action, required bool automatic}) async {
    if (!owner || state.busy || state.saved == null || state.draft == null) {
      return;
    }
    final g = ++generation;
    var draft = state.draft!, saved = state.saved!;
    final submitted = draft;
    emit(state.copyWith(busy: !automatic, autosaving: automatic));
    void accept(WebsiteSettings result, {List<WebsiteImage>? images}) {
      saved = result;
      draft = saved.copyWith(images: images ?? draft.images);
      emit(
        state.copyWith(
          saved: saved,
          draft: rebaseWebsiteSave(submitted, state.draft!, draft),
          busy: !automatic,
          autosaving: automatic,
        ),
      );
    }

    try {
      if (state.settingsDirty) {
        final result = await repository.save(draft);
        if (!valid(g)) return;
        accept(result);
      }
      // Single-photo uploads replace their existing slot atomically on the API.
      // Other removals run first to free gallery positions and the photo budget.
      final removals = saved.images
          .where(
            (image) =>
                !draft.images.any((i) => i.id == image.id) &&
                !draft.images.any(
                  (i) =>
                      i.pending && i.kind != 'space' && samePhotoSlot(i, image),
                ),
          )
          .toList();
      for (final image in removals) {
        final result = await repository.removeImage(image.id, saved.version);
        if (!valid(g)) return;
        accept(result);
      }
      for (final image in draft.images.where((i) => i.pending).toList()) {
        final previousIds = saved.images.map((i) => i.id).toSet();
        final result = await repository.uploadImage(
          LogoSelection(image.bytes!, 'image/jpeg'),
          saved.version,
          kind: image.kind,
          businessId: image.businessId,
          resourceId: image.resourceId,
        );
        if (!valid(g)) return;
        final uploaded = result.images
            .where(
              (i) => !previousIds.contains(i.id) && samePhotoSlot(i, image),
            )
            .single;
        accept(
          result,
          images: [
            for (final i in draft.images) i.id == image.id ? uploaded : i,
          ],
        );
      }
      if (action != null) {
        saved = await repository.publication(action, saved.version);
      }
      if (valid(g)) {
        emit(
          WebsiteSettingsState(
            saved: saved,
            draft: rebaseWebsiteSave(submitted, state.draft!, saved),
            loading: false,
            revision: automatic ? state.revision : state.revision + 1,
            message: action == 'publish'
                ? 'Your booking website is published.'
                : action == 'pause'
                ? 'Online bookings are paused.'
                : action == 'unpublish'
                ? 'The website is unpublished.'
                : automatic
                ? null
                : 'Website settings saved.',
          ),
        );
      }
    } catch (e) {
      if (valid(g)) {
        emit(
          state.copyWith(
            busy: false,
            autosaving: false,
            addressError: state.addressDirty ? failure(e) : null,
            error:
                '${failure(e)} Your remaining edits are kept here. Reload settings before retrying an uncertain save.',
          ),
        );
      }
    }
  }

  bool samePhotoSlot(WebsiteImage a, WebsiteImage b) =>
      a.kind == b.kind &&
      a.businessId == b.businessId &&
      a.resourceId == b.resourceId;

  /// Stages a local photo selection/removal. Only [save] persists photo changes.
  Future<void> photo({
    String? kind,
    String? businessId,
    String? resourceId,
    String? removeId,
  }) async {
    if (state.autosaving) await _writeInFlight;
    if (!owner || state.busy || state.loading || state.draft == null) return;
    _autosaveTimer?.cancel();
    final draft = state.draft!;
    if (removeId != null) {
      update(
        draft.copyWith(
          images: [
            for (final image in draft.images)
              if (image.id != removeId) image,
          ],
        ),
      );
      return;
    }
    final photoKind =
        kind ??
        (resourceId != null
            ? 'space'
            : businessId != null
            ? 'card'
            : 'hero');
    final slot = WebsiteImage(
      id: '',
      kind: photoKind,
      businessId: businessId,
      resourceId: resourceId,
    );
    final existing = draft.images.where((i) => samePhotoSlot(i, slot)).length;
    final replaces = photoKind != 'space' && existing > 0;
    if ((!replaces && draft.images.length >= websitePhotoLimit) ||
        (photoKind == 'space' && existing >= websiteSpacePhotoLimit)) {
      emit(
        state.copyWith(
          error: 'Photo limit reached. Remove a photo before adding another.',
        ),
      );
      return;
    }
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      final selected = await repository.pickImage();
      if (!valid(g)) return;
      if (selected == null) {
        emit(state.copyWith(busy: false));
        _scheduleAutosave();
        return;
      }
      if (selected.bytes.isEmpty || selected.bytes.length > 1024 * 1024) {
        throw const AppException('Choose an image up to 1 MB.');
      }
      final image = WebsiteImage(
        id: 'pending-photo-${++photoSequence}',
        kind: photoKind,
        businessId: businessId,
        resourceId: resourceId,
        bytes: Uint8List.fromList(selected.bytes).asUnmodifiableView(),
        pending: true,
      );
      emit(
        state.copyWith(
          draft: draft.copyWith(
            images: [
              for (final current in draft.images)
                if (photoKind == 'space' || !samePhotoSlot(current, image))
                  current,
              image,
            ],
          ),
          busy: false,
          message: autosaveEnabled
              ? 'Photo selected. Saving automatically.'
              : 'Photo selected. Save changes to apply it.',
        ),
      );
    } catch (e) {
      if (valid(g)) {
        emit(state.copyWith(busy: false, error: failure(e)));
      }
    }
    if (valid(g) && state.error == null) _scheduleAutosave();
  }

  Future<void> link({bool preview = false, bool copy = false}) async {
    if (!owner ||
        state.busy ||
        state.autosaving ||
        state.saved == null ||
        state.dirty) {
      return;
    }
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
    _autosaveTimer?.cancel();
    generation++;
    await subscription.cancel();
    return super.close();
  }
}
