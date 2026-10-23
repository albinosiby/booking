import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../repositories/auth_repository_interface.dart';
import '../repositories/auth_continuation_repository.dart';
import '../models/auth_continuation.dart';
import '../../../utils/helpers/safe_return_path.dart';
import 'auth_state.dart';
export 'auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  AuthCubit(this.repository, {this.continuations, this.beforeSignOut})
    : super(const AuthState()) {
    _restored = _restoreContinuation();
    _subscription = repository.changes.listen(
      (u) async {
        await _restored;
        if (!isClosed) {
          emit(
            AuthState(
              status: u == null ? AuthStatus.signedOut : AuthStatus.signedIn,
              user: u,
              busy: state.busy,
              googleSignIn: state.googleSignIn,
            ),
          );
        }
      },
      onError: (Object error) async {
        await _restored;
        if (!isClosed) {
          emit(
            AuthState(
              status: repository.currentUser == null
                  ? AuthStatus.signedOut
                  : AuthStatus.signedIn,
              user: repository.currentUser,
              error: error is AppException
                  ? error.message
                  : 'Your session could not be refreshed. Check your connection or sign in again.',
            ),
          );
        }
      },
    );
  }
  final AuthRepository repository;
  final Future<void> Function()? beforeSignOut;
  final AuthContinuationRepository? continuations;
  late final Future<void> _restored;
  Future<void> _clearing = Future.value();
  AuthContinuation? _continuation;
  bool get supportsGoogleSignIn => repository is GoogleSignInRepository;
  AuthContinuation? get continuation =>
      _continuation?.isValidAt(DateTime.now()) == true ? _continuation : null;

  Future<void> _restoreContinuation() async {
    try {
      _continuation = await continuations?.read();
    } catch (_) {
      // Optional routing recovery must not block an existing authenticated session.
      _continuation = null;
    }
  }

  /// Called once the router has restored the destination; no extra refresh needed.
  void consumeContinuation() {
    _continuation = null;
    _clearing = _clearing.then((_) async {
      try {
        await continuations?.clear();
      } catch (_) {
        // Expiration still bounds saved context if local storage is unavailable.
      }
    });
  }

  late final StreamSubscription<Object?> _subscription;
  Future<void> _perform(
    Future<void> Function() action, {
    bool googleSignIn = false,
  }) async {
    if (state.busy) return;
    emit(
      AuthState(
        status: state.status,
        user: state.user,
        busy: true,
        googleSignIn: googleSignIn,
      ),
    );
    try {
      await _restored;
      await _clearing;
      await action();
      if (!isClosed) {
        emit(
          AuthState(
            status: repository.currentUser == null
                ? AuthStatus.signedOut
                : AuthStatus.signedIn,
            user: repository.currentUser,
            notice: googleSignIn && repository.currentUser == null
                ? 'Complete Google sign-in in your browser, then return here.'
                : null,
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

  Future<void> register(String n, String e, String p) => _perform(() async {
    consumeContinuation();
    await _clearing;
    await repository.register(n, e, p);
  });
  Future<void> signIn(String e, String p) => _perform(() async {
    consumeContinuation();
    await _clearing;
    await repository.signIn(e, p);
  });
  Future<void> signInWithGoogle({String? invitationToken, String? returnTo}) =>
      _perform(() async {
        if (repository is! GoogleSignInRepository) {
          throw const AppException(
            'Google sign-in is unavailable for this connection.',
          );
        }
        final value = AuthContinuation(
          createdAt: DateTime.now(),
          invitationToken: invitationToken,
          returnTo: safeReturnPath(returnTo),
        );
        if (!value.isValidAt(DateTime.now())) {
          throw const AppException(
            'This invitation link is invalid. Ask your owner for a new link.',
          );
        }
        try {
          await continuations?.write(value);
          _continuation = value;
          await (repository as GoogleSignInRepository).signInWithGoogle();
        } catch (_) {
          consumeContinuation();
          await _clearing;
          rethrow;
        }
      }, googleSignIn: true);
  Future<void> signOut() => _perform(() async {
    consumeContinuation();
    await _clearing;
    try {
      await beforeSignOut?.call();
    } catch (_) {
      // Device cleanup retries independently; notification availability must not trap the user in a session.
    }
    await repository.signOut();
  });
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
