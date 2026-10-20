import '../models/business_draft.dart';
import '../../workspace/repositories/workspace_repository_interface.dart';

abstract interface class BusinessRepository {
  Future<void> add(BusinessDraft draft);
  Future<void> reorder(List<String> ids, int revision);
  Future<void> rename(String id, String name);
  Future<void> addResource(String businessId, ResourceDraft draft);
  Future<void> removeResource(String businessId, String resourceId);
  Future<void> configure(String id, BusinessConfiguration configuration);
  Future<void> activate(String id);
}

class LocalApiBusinessRepository implements BusinessRepository {
  LocalApiBusinessRepository(this.source);
  final WorkspaceRepository source;
  @override
  Future<void> add(BusinessDraft draft) => source.addBusiness(draft.toJson());
  @override
  Future<void> reorder(List<String> ids, int revision) =>
      source.reorderBusinesses(ids, revision);
  @override
  Future<void> rename(String id, String name) =>
      source.renameBusiness(id, name);
  @override
  Future<void> addResource(String id, ResourceDraft draft) =>
      source.addResource(id, draft.name, draft.capacity);
  @override
  Future<void> removeResource(String id, String resource) =>
      source.removeResource(id, resource);
  @override
  Future<void> configure(String id, BusinessConfiguration configuration) =>
      source.configure(id, configuration.toJson());
  @override
  Future<void> activate(String id) => source.activate(id);
}
