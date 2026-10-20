import 'package:firebase_auth/firebase_auth.dart';
import '../../../utils/exceptions/app_exception.dart';
import '../models/app_user.dart';
import 'auth_repository_interface.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);
  final FirebaseAuth _auth;
  AppUser? _map(User? u) => u == null
      ? null
      : AppUser(
          id: u.uid,
          email: u.email ?? '',
          name: u.displayName ?? '',
          verified: u.emailVerified,
        );
  @override
  Stream<AppUser?> get changes => _auth.idTokenChanges().map(_map);
  @override
  AppUser? get currentUser => _map(_auth.currentUser);
  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AppException(switch (e.code) {
        'email-already-in-use' =>
          'This email already has an account. Sign in instead.',
        'invalid-credential' ||
        'wrong-password' ||
        'user-not-found' => 'Email or password is incorrect.',
        'weak-password' => 'Choose a stronger password.',
        'invalid-email' => 'Enter a valid email address.',
        'network-request-failed' =>
          'Cannot reach authentication. Check your connection.',
        'too-many-requests' => 'Too many attempts. Please wait and try again.',
        _ => 'Authentication failed. Please try again.',
      }, code: e.code);
    }
  }

  @override
  Future<void> register(String name, String email, String password) =>
      _run(() async {
        final result = await _auth.createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        await result.user!.updateDisplayName(name.trim());
        await result.user!.getIdToken(true);
        await result.user!.sendEmailVerification();
      });
  @override
  Future<void> signIn(String email, String password) => _run(() async {
    await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  });
  @override
  Future<void> signOut() => _auth.signOut();
  @override
  Future<void> resetPassword(String email) =>
      _run(() => _auth.sendPasswordResetEmail(email: email.trim()));
  @override
  Future<void> sendVerification() => _run(() async {
    await _auth.currentUser?.sendEmailVerification();
  });
  @override
  Future<void> reload() => _run(() async {
    await _auth.currentUser?.reload();
    await _auth.currentUser?.getIdToken(true);
  });
  @override
  Future<String?> token({bool refresh = false}) async =>
      _auth.currentUser?.getIdToken(refresh);
}
