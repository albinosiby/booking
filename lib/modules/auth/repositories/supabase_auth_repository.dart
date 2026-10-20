import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import '../../../config/app_config.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/app_user.dart';
import 'auth_repository_interface.dart';

class SupabaseAuthRepository
    implements AuthRepository, PasswordUpdateRepository {
  SupabaseAuthRepository(this._auth);
  final sb.GoTrueClient _auth;
  bool _recovering = false;
  String? get _redirect => kIsWeb ? null : AppConfig.authRedirectUrl;
  AppUser? _map(sb.User? user) => user == null
      ? null
      : AppUser(
          id: user.id,
          email: user.email ?? '',
          name: user.userMetadata?['full_name'] is String
              ? user.userMetadata!['full_name'] as String
              : '',
          verified: user.emailConfirmedAt != null,
          passwordRecovery: _recovering,
        );
  @override
  Stream<AppUser?> get changes => _auth.onAuthStateChange.map((event) {
    if (event.event == sb.AuthChangeEvent.passwordRecovery) _recovering = true;
    if (event.event == sb.AuthChangeEvent.signedOut) _recovering = false;
    return _map(event.session?.user);
  });
  @override
  AppUser? get currentUser => _map(_auth.currentUser);

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on sb.AuthException catch (error) {
      throw AppException(switch (error.code) {
        'invalid_credentials' => 'Email or password is incorrect.',
        'email_not_confirmed' =>
          'Verify your email using the link in your inbox, then sign in.',
        'user_already_exists' ||
        'email_exists' => 'This email already has an account. Sign in instead.',
        'weak_password' => 'Choose a stronger password.',
        'over_request_rate_limit' || 'over_email_send_rate_limit' =>
          'Too many attempts. Please wait and try again.',
        _ => 'Could not complete authentication. Please try again.',
      }, code: error.code ?? 'AUTH');
    } catch (error) {
      if (error is AppException) rethrow;
      throw const AppException(
        'Cannot reach authentication. Check your connection.',
        code: 'NETWORK',
      );
    }
  }

  @override
  Future<void> register(String name, String email, String password) =>
      _run(() async {
        final response = await _auth.signUp(
          email: email.trim(),
          password: password,
          data: {'full_name': name.trim()},
          emailRedirectTo: _redirect,
        );
        if (response.session == null) {
          throw const AppException(
            'Check your inbox to confirm your email, then choose Sign in.',
            code: 'EMAIL_CONFIRMATION_REQUIRED',
          );
        }
      });
  @override
  Future<void> signIn(String email, String password) => _run(() async {
    _recovering = false;
    await _auth.signInWithPassword(email: email.trim(), password: password);
  });
  @override
  Future<void> signOut() => _run(() async {
    await _auth.signOut();
  });
  @override
  Future<void> resetPassword(String email) => _run(
    () => _auth.resetPasswordForEmail(email.trim(), redirectTo: _redirect),
  );
  @override
  Future<void> sendVerification() => _run(() async {
    final email = _auth.currentUser?.email;
    if (email != null) {
      await _auth.resend(
        type: sb.OtpType.signup,
        email: email,
        emailRedirectTo: _redirect,
      );
    }
  });
  @override
  Future<void> reload() => _run(() async {
    await _auth.refreshSession();
  });
  @override
  Future<void> updatePassword(String password) => _run(() async {
    await _auth.updateUser(sb.UserAttributes(password: password));
    _recovering = false;
    await _auth.signOut();
  });
  @override
  Future<String?> token({bool refresh = false}) async {
    final session = _auth.currentSession;
    if (session == null) return null;
    if (refresh || session.isExpired) {
      return (await _auth.refreshSession()).session?.accessToken;
    }
    return session.accessToken;
  }
}
