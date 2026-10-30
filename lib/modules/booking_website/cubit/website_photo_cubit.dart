import 'dart:async';
import 'dart:typed_data';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../../workspace/models/workspace_access.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../repositories/website_repository.dart';

class WebsitePhotoState extends Equatable {
  const WebsitePhotoState({this.bytes, this.loading = true, this.error});
  final Uint8List? bytes;
  final bool loading;
  final String? error;
  @override
  List<Object?> get props => [bytes, loading, error];
}

/// One mounted preview; photo completion never changes the editor draft.
class WebsitePhotoCubit extends Cubit<WebsitePhotoState> {
  WebsitePhotoCubit(this.session, this.repository, this.id)
    : super(const WebsitePhotoState()) {
    scope = workspaceAccessScope(session.state.data);
    subscription = session.snapshots.listen((_) {
      if (!authorized) {
        generation++;
        emit(
          const WebsitePhotoState(
            loading: false,
            error: 'Your workspace changed. Reopen Design website.',
          ),
        );
      }
    });
  }
  final WorkspaceSession session;
  final WebsiteRepository repository;
  final String id;
  late final String scope;
  late final StreamSubscription subscription;
  int generation = 0;
  bool _loading = false;
  bool get authorized =>
      !isClosed &&
      session.state.data.isOwner &&
      session.state.data.organization != null &&
      workspaceAccessScope(session.state.data) == scope;

  Future<void> load({bool refresh = false}) async {
    if (!authorized || _loading) return;
    _loading = true;
    final g = ++generation;
    emit(const WebsitePhotoState());
    try {
      final bytes = await repository.photoBytes(id, refresh: refresh);
      if (authorized && g == generation) {
        emit(WebsitePhotoState(bytes: bytes, loading: false));
      }
    } catch (e) {
      if (authorized && g == generation) {
        emit(
          WebsitePhotoState(
            loading: false,
            error: e is AppException ? e.message : 'Could not load this photo.',
          ),
        );
      }
    } finally {
      _loading = false;
    }
  }

  @override
  Future<void> close() async {
    generation++;
    await subscription.cancel();
    return super.close();
  }
}
