import '../../bookings/models/booking_models.dart';
import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:uuid/uuid.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../../workspace/models/workspace_access.dart';
import '../models/message_template.dart';
import '../models/message_screen_models.dart';
import '../repositories/message_repository.dart';

String messageError(Object error) => error is AppException
    ? error.message
    : 'Could not complete this action. Please try again.';

abstract class ScopedMessageCubit<S> extends Cubit<S> {
  ScopedMessageCubit(this.session, this.repository, S initial)
    : super(initial) {
    scope = workspaceAccessScope(session.state.data);
    subscription = session.snapshots.listen((_) {
      if (scope != workspaceAccessScope(session.state.data)) {
        generation++;
        emit(accessReset());
      }
    });
  }
  final WorkspaceSession session;
  final MessageRepository repository;
  late final String scope;
  late final StreamSubscription subscription;
  int generation = 0;
  bool get authorized =>
      session.state.data.organization != null &&
      scope == workspaceAccessScope(session.state.data) &&
      [
        'view_bookings',
        'manage_bookings',
        'collect_payments',
        'view_finance',
      ].any(session.state.data.hasPermission);
  bool get owner => authorized && session.state.data.isOwner;
  bool valid(int g) => !isClosed && authorized && g == generation;
  S accessReset();
  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}

class TemplatesCubit extends ScopedMessageCubit<TemplatesState> {
  TemplatesCubit(WorkspaceSession session, MessageRepository repository)
    : super(session, repository, TemplatesState());
  @override
  TemplatesState accessReset() => TemplatesState(
    loading: false,
    error: 'Your access changed. Reopen this page.',
  );
  Future<void> load({bool refresh = false}) async {
    if (!owner) {
      emit(accessReset());
      return;
    }
    final g = ++generation;
    emit(state.copyWith(loading: true));
    try {
      final catalog = await repository.catalog(refresh: refresh);
      if (valid(g)) emit(state.copyWith(catalog: catalog, loading: false));
    } catch (e) {
      if (valid(g)) {
        emit(state.copyWith(loading: false, error: messageError(e)));
      }
    }
  }

  Future<void> primary(String id) => _change(() => repository.primary(id));
  Future<void> remove(String id) => _change(() => repository.remove(id));
  Future<void> _change(Future<void> Function() change) async {
    if (!owner || state.busy) return;
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      await change();
      final catalog = await repository.catalog(refresh: true);
      if (valid(g)) emit(state.copyWith(catalog: catalog, busy: false));
    } catch (e) {
      if (valid(g)) emit(state.copyWith(busy: false, error: messageError(e)));
    }
  }
}

class TemplateEditorCubit extends ScopedMessageCubit<TemplateEditorState> {
  TemplateEditorCubit(
    WorkspaceSession session,
    MessageRepository repository,
    MessageTemplate? source,
  ) : super(
        session,
        repository,
        TemplateEditorState(
          name: source == null ? '' : '${source.name} (copy)',
          body: source?.body ?? '',
          website: source?.website ?? '',
        ),
      );
  final key = const Uuid().v4();
  TemplateEditorState? pending;
  bool get lockedDraft => state.busy || pending != null;
  @override
  TemplateEditorState accessReset() => const TemplateEditorState(
    error: 'Your access changed. Reopen this page.',
  );
  void selectTab(TemplateEditorTab tab) {
    if (owner) emit(state.copyWith(tab: tab, error: state.error));
  }

  void update({String? name, String? body, String? website}) {
    if (!lockedDraft && owner) {
      emit(state.copyWith(name: name, body: body, website: website));
    }
  }

  Future<void> save() async {
    if (!owner || state.busy) return;
    final draft = pending ?? state;
    final bodyError = validateMessageBody(draft.body);
    final uri = Uri.tryParse(draft.website.trim());
    final error = draft.name.trim().length < 2 || draft.name.trim().length > 80
        ? 'Use a template name of 2–80 characters.'
        : bodyError ??
              (draft.website.trim().isNotEmpty &&
                      (uri == null ||
                          !['http', 'https'].contains(uri.scheme) ||
                          uri.host.isEmpty ||
                          draft.website.length > 500)
                  ? 'Enter an http or https website URL.'
                  : null);
    if (error != null) {
      emit(state.copyWith(error: error));
      return;
    }
    pending = draft;
    final g = ++generation;
    emit(state.copyWith(busy: true));
    try {
      await repository.create(
        key: key,
        name: draft.name.trim(),
        body: draft.body,
        website: draft.website.trim(),
      );
      if (valid(g)) emit(state.copyWith(busy: false, saved: true));
    } catch (e) {
      if (valid(g)) {
        if (e is AppException &&
            [
              'VALIDATION_ERROR',
              'REQUEST_ERROR',
              'CONFLICT',
            ].contains(e.code)) {
          pending = null;
        }
        emit(state.copyWith(busy: false, error: messageError(e)));
      }
    }
  }
}

class MessagePreviewCubit extends ScopedMessageCubit<MessagePreviewState> {
  MessagePreviewCubit(
    WorkspaceSession session,
    MessageRepository repository,
    this.gateway,
    this.bookingId,
  ) : super(session, repository, const MessagePreviewState());
  final MessageShareGateway gateway;
  final String bookingId;
  @override
  MessagePreviewState accessReset() => const MessagePreviewState(
    loading: false,
    error: 'Your access changed. Reopen this booking.',
  );
  Future<void> load() async {
    if (!authorized) {
      emit(accessReset());
      return;
    }
    final g = ++generation;
    emit(state.copyWith(loading: true));
    String? notice;
    // A missing template must not prevent a successful booking. Preview fallback explicitly.
    final templateFuture = repository.catalog(refresh: true).catchError((
      Object e,
    ) {
      if (e is AppException &&
          ['FORBIDDEN', 'UNAUTHENTICATED'].contains(e.code)) {
        throw e;
      }
      notice =
          'Could not load your primary template. Showing the predefined template; retry to check it.';
      return MessageTemplateCatalog();
    });
    try {
      final results = await Future.wait<Object>([
        repository.booking(bookingId),
        templateFuture,
      ]);
      if (!valid(g)) return;
      final booking = results[0] as BookingRecord;
      final catalog = results[1] as MessageTemplateCatalog;
      final template = catalog.primary;
      final error = validateMessageBody(template.body);
      if (error != null) throw AppException(error);
      if (booking.status != 'confirmed') {
        notice =
            'Booking status: ${booking.status}. Check the message wording before sharing.';
      }
      final message = template.render(
        bookingMessageFields(
          booking,
          session.state.data.organization!.name,
          template.website,
          session.state.data.organization!.currency,
        ),
      );
      emit(
        MessagePreviewState(
          message: message,
          templateName: template.name,
          loading: false,
          notice: notice,
        ),
      );
    } catch (e) {
      if (valid(g)) {
        emit(MessagePreviewState(loading: false, error: messageError(e)));
      }
    }
  }

  Future<void> share() async {
    if (!authorized || state.loading || state.busy || state.message.isEmpty) {
      return;
    }
    final g = generation;
    emit(state.copyWith(busy: true));
    try {
      final opened = await gateway.whatsapp(state.message);
      if (valid(g)) {
        emit(
          state.copyWith(
            busy: false,
            notice: opened
                ? 'Review the message and choose the recipient in WhatsApp.'
                : 'Could not open WhatsApp. Use Copy message instead.',
          ),
        );
      }
    } catch (e) {
      if (valid(g)) emit(state.copyWith(busy: false, error: messageError(e)));
    }
  }

  Future<void> copy() async {
    if (!authorized || state.loading || state.busy || state.message.isEmpty) {
      return;
    }
    final g = generation;
    emit(state.copyWith(busy: true));
    try {
      await gateway.copy(state.message);
      if (valid(g)) {
        emit(state.copyWith(busy: false, notice: 'Message copied.'));
      }
    } catch (e) {
      if (valid(g)) emit(state.copyWith(busy: false, error: messageError(e)));
    }
  }
}
