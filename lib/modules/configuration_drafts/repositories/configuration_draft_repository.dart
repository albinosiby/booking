import '../models/configuration_draft.dart';

abstract interface class ConfigurationDraftRepository {
  Future<ConfigurationDraft?> read(String scope);
  Future<void> write(String scope, ConfigurationDraft draft);
  Future<void> remove(String scope);
}
