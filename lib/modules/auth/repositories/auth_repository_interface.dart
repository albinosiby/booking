import '../models/app_user.dart';

abstract interface class AuthRepository {
  Stream<AppUser?> get changes;
  AppUser? get currentUser;
  Future<void> register(String name, String email, String password);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
  Future<void> resetPassword(String email);
  Future<void> sendVerification();
  Future<void> reload();
  Future<String?> token({bool refresh = false});
}

abstract interface class PasswordUpdateRepository {
  Future<void> updatePassword(String password);
}

abstract interface class GoogleSignInRepository {
  Future<void> signInWithGoogle();
}
