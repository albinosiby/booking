import 'package:equatable/equatable.dart';
import 'app_user.dart';

enum AuthStatus { loading, signedOut, signedIn }

class AuthState extends Equatable {
  const AuthState({
    this.status = AuthStatus.loading,
    this.user,
    this.busy = false,
    this.error,
    this.notice,
  });
  final AuthStatus status;
  final AppUser? user;
  final bool busy;
  final String? error, notice;
  @override
  List<Object?> get props => [status, user, busy, error, notice];
}
