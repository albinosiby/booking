import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../models/booking_website_link.dart';
import '../repositories/booking_website_link_repository.dart';

class BookingWebsiteLinkState {
  const BookingWebsiteLinkState({
    this.link,
    this.loading = false,
    this.working = false,
    this.error,
    this.message,
  });
  final BookingWebsiteLink? link;
  final bool loading, working;
  final String? error, message;
}

class BookingWebsiteLinkCubit extends Cubit<BookingWebsiteLinkState> {
  BookingWebsiteLinkCubit(this.session, this.repository)
    : super(const BookingWebsiteLinkState()) {
    scope = workspaceAccessScope(session.state.data);
    subscription = session.snapshots.listen((_) {
      if (!authorized && !isClosed) {
        generation++;
        emit(
          const BookingWebsiteLinkState(
            error: 'Your workspace changed. Close and reopen the website link.',
          ),
        );
      }
    });
  }
  final WorkspaceSession session;
  final BookingWebsiteLinkRepository repository;
  late final String scope;
  late final StreamSubscription subscription;
  int generation = 0;
  bool get authorized =>
      !isClosed &&
      session.state.data.organization != null &&
      scope == workspaceAccessScope(session.state.data);
  String failure(Object error) => error is AppException
      ? error.message
      : 'Could not load or open the website link.';
  Future<void> load() async {
    if (!authorized || state.working) return;
    final request = ++generation;
    emit(BookingWebsiteLinkState(link: state.link, loading: true));
    try {
      final link = await repository.load();
      if (authorized && request == generation) {
        emit(BookingWebsiteLinkState(link: link));
      }
    } catch (error) {
      if (authorized && request == generation) {
        emit(
          BookingWebsiteLinkState(
            link: accessFailure(error) ? null : state.link,
            error: failure(error),
          ),
        );
      }
    }
  }

  Future<void> open() => act(copy: false);
  Future<void> copy() => act(copy: true);
  Future<void> act({required bool copy}) async {
    final link = state.link;
    if (!authorized ||
        state.loading ||
        state.working ||
        link?.available != true) {
      return;
    }
    final request = generation;
    emit(BookingWebsiteLinkState(link: link, working: true));
    try {
      if (copy) {
        await repository.copy(link!.url!);
      } else {
        await repository.open(link!.url!);
      }
      if (authorized && request == generation) {
        emit(
          BookingWebsiteLinkState(
            link: link,
            message: copy ? 'Website link copied.' : null,
          ),
        );
      }
    } catch (error) {
      if (authorized && request == generation) {
        emit(
          BookingWebsiteLinkState(
            link: accessFailure(error) ? null : link,
            error: failure(error),
          ),
        );
      }
    }
  }

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}
