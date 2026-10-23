import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/auth_continuation.dart';

abstract interface class AuthContinuationRepository {
  Future<AuthContinuation?> read();
  Future<void> write(AuthContinuation value);
  Future<void> clear();
}

/// Keeps private invitation links out of OAuth URLs and plain preferences.
class SecureAuthContinuationRepository implements AuthContinuationRepository {
  SecureAuthContinuationRepository(
    String projectUrl, {
    this.storage = const FlutterSecureStorage(),
    DateTime Function()? now,
  }) : _key = 'booking.oauth.${Uri.parse(projectUrl).host}',
       _now = now ?? DateTime.now;

  final String _key;
  final FlutterSecureStorage storage;
  final DateTime Function() _now;

  @override
  Future<AuthContinuation?> read() async {
    final raw = await storage.read(key: _key);
    if (raw == null) return null;
    try {
      final value = AuthContinuation.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (value.isValidAt(_now())) return value;
    } on FormatException {
      // Corrupt or expired routing context must never prevent sign-in.
    } on TypeError {
      // Treat incompatible saved data like an expired continuation.
    }
    await clear();
    return null;
  }

  @override
  Future<void> write(AuthContinuation value) =>
      storage.write(key: _key, value: jsonEncode(value.toJson()));

  @override
  Future<void> clear() => storage.delete(key: _key);
}
