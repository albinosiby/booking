import 'package:equatable/equatable.dart';

class AppUser extends Equatable {
  const AppUser({
    required this.id,
    required this.email,
    required this.name,
    required this.verified,
    this.passwordRecovery = false,
  });
  final String id, email, name;
  final bool verified, passwordRecovery;
  @override
  List<Object?> get props => [id, email, name, verified, passwordRecovery];
}
