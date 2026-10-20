import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../repositories/auth_repository_interface.dart';
import 'auth_state.dart';
export 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this.repository) : super(const AuthState()) {
    _subscription = repository.changes.listen(
      (u) {
        if (!isClosed) {
          emit(
            AuthState(
              status: u == null ? AuthStatus.signedOut : AuthStatus.signedIn,
              user: u,
              busy: state.busy,
            ),
          );
        }
      },
      onError: (Object error) {
        if (!isClosed) {
          emit(
            AuthState(
              status: state.status,
              user: state.user,
              error:
                  'Your session could not be refreshed. Check your connection or sign in again.',
            ),
          );
        }
      },
    );
  }
  final AuthRepository repository;
  late final StreamSubscription<Object?> _subscription;
  Future<void> _perform(Future<void> Function() action) async {
    if (state.busy) return;
    emit(AuthState(status: state.status, user: state.user, busy: true));
    try {
      await action();
      if (!isClosed) {
        emit(
          AuthState(
            status: repository.currentUser == null
                ? AuthStatus.signedOut
                : AuthStatus.signedIn,
            user: repository.currentUser,
          ),
        );
      }
    } catch (e) {
      if (!isClosed) {
        emit(
          AuthState(
            status: state.status,
            user: state.user,
            notice: e is AppException && e.code == 'EMAIL_CONFIRMATION_REQUIRED'
                ? e.message
                : null,
            error: e is AppException && e.code == 'EMAIL_CONFIRMATION_REQUIRED'
                ? null
                : e is AppException
                ? e.message
                : 'Could not complete this action. Try again.',
          ),
        );
      }
    }
  }

  Future<void> register(String n, String e, String p) =>
      _perform(() => repository.register(n, e, p));
  Future<void> signIn(String e, String p) =>
      _perform(() => repository.signIn(e, p));
  Future<void> signOut() => _perform(repository.signOut);
  Future<void> resetPassword(String e) =>
      _perform(() => repository.resetPassword(e));
  Future<void> verify() => _perform(repository.sendVerification);
  Future<void> updatePassword(String password) => _perform(() async {
    if (repository is! PasswordUpdateRepository) {
      throw const AppException(
        'Password updates are unavailable for this connection.',
      );
    }
    await (repository as PasswordUpdateRepository).updatePassword(password);
  });
  Future<void> reload() => _perform(repository.reload);
  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
