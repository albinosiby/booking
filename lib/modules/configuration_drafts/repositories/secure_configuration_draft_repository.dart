import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/configuration_draft.dart';
import 'configuration_draft_repository.dart';

class SecureConfigurationDraftRepository
    implements ConfigurationDraftRepository {
  const SecureConfigurationDraftRepository(this.storage);
  final FlutterSecureStorage storage;
  String _key(String scope) =>
      'booking.configuration-draft.v1.${base64Url.encode(utf8.encode(scope))}';
  @override
  Future<ConfigurationDraft?> read(String scope) async {
    final json = await storage.read(key: _key(scope));
    return json == null
        ? null
        : ConfigurationDraft.fromJson(
            Map<String, dynamic>.from(jsonDecode(json) as Map),
          );
  }

  @override
  Future<void> write(String scope, ConfigurationDraft draft) =>
      storage.write(key: _key(scope), value: jsonEncode(draft.toJson()));
  @override
  Future<void> remove(String scope) => storage.delete(key: _key(scope));
}
