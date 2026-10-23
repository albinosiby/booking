import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;
import 'package:url_launcher/url_launcher.dart';
import '../../../config/app_config.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/app_user.dart';
import 'auth_repository_interface.dart';

class SupabaseAuthRepository
    implements
        AuthRepository,
        PasswordUpdateRepository,
        GoogleSignInRepository {
  SupabaseAuthRepository(this._auth, {Future<bool> Function(Uri)? launchOAuth})
    : _launchOAuth = launchOAuth ?? _launchGoogle;
  final sb.GoTrueClient _auth;
  final Future<bool> Function(Uri) _launchOAuth;
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
  Stream<AppUser?> get changes => _auth.onAuthStateChange
      .map((event) {
        if (event.event == sb.AuthChangeEvent.passwordRecovery) {
          _recovering = true;
        }
        if (event.event == sb.AuthChangeEvent.signedOut) _recovering = false;
        return _map(event.session?.user);
      })
      .handleError((Object error) {
        if (error is sb.AuthException) {
          throw AppException(
            error.code == 'access_denied'
                ? 'Google sign-in was cancelled. You can try again.'
                : 'Could not complete sign-in. Please try again.',
            code: 'AUTH_CALLBACK',
          );
        }
        throw error;
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
  Future<void> signInWithGoogle() => _run(() async {
    _recovering = false;
    final response = await _auth.getOAuthSignInUrl(
      provider: sb.OAuthProvider.google,
      redirectTo: googleOAuthRedirect(isWeb: kIsWeb, webUri: Uri.base),
      queryParams: const {'prompt': 'select_account'},
    );
    if (!await _launchOAuth(Uri.parse(response.url))) {
      throw const AppException(
        'Could not open Google sign-in. Please try again.',
        code: 'GOOGLE_LAUNCH_FAILED',
      );
    }
  });

  static Future<bool> _launchGoogle(Uri uri) => launchUrl(
    uri,
    mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    webOnlyWindowName: '_self',
  );
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

/// Retain the web deployment prefix (including /app/) and strip auth query data.
String googleOAuthRedirect({required bool isWeb, required Uri webUri}) => isWeb
    ? webUri.resolve('auth-callback').toString()
    : AppConfig.authRedirectUrl;
