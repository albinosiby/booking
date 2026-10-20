import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// OS-protected mobile session storage; never store a password in the app.
class SupabaseSessionStorage extends LocalStorage {
  const SupabaseSessionStorage(this.projectUrl);
  final String projectUrl;
  static const _storage = FlutterSecureStorage();
  String get _key => 'booking.supabase.${Uri.parse(projectUrl).host}';
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> hasAccessToken() => _storage.containsKey(key: _key);
  @override
  Future<String?> accessToken() => _storage.read(key: _key);
  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);
  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}
