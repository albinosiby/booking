import '../../../utils/helpers/safe_return_path.dart';

/// Routing context only: authentication and invitation acceptance stay separate.
class AuthContinuation {
  const AuthContinuation({
    required this.createdAt,
    this.invitationToken,
    this.returnTo,
  });

  final DateTime createdAt;
  final String? invitationToken, returnTo;
  static const lifetime = Duration(minutes: 30);

  bool isValidAt(DateTime now) =>
      now.difference(createdAt) >= Duration.zero &&
      now.difference(createdAt) < lifetime &&
      (invitationToken == null ||
          RegExp(r'^[a-f0-9]{64}$').hasMatch(invitationToken!)) &&
      (returnTo == null || safeReturnPath(returnTo) == returnTo);

  Map<String, dynamic> toJson() => {
    'created_at': createdAt.toUtc().toIso8601String(),
    'invite': invitationToken,
    'from': returnTo,
  };

  factory AuthContinuation.fromJson(Map<String, dynamic> json) =>
      AuthContinuation(
        createdAt: DateTime.parse(json['created_at'] as String),
        invitationToken: json['invite'] as String?,
        returnTo: json['from'] as String?,
      );
}
