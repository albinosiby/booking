import '../models/staff_access_draft.dart';
import '../../workspace/repositories/workspace_repository_interface.dart';
import '../../workspace/repositories/refreshable_reads.dart';

abstract interface class TeamRepository {
  Future<Map<String, dynamic>> load();
  Future<String> invite(StaffAccessDraft draft);
  Future<void> update(String id, StaffAccessDraft draft);
  Future<void> accept(String token);
  Future<void> revoke(String id, {bool invitation = false});
}

class LocalApiTeamRepository implements TeamRepository, RetainedReadEvents {
  LocalApiTeamRepository(this.source);
  final WorkspaceRepository source;
  @override
  Stream<void> get readChanges => source is RetainedReadEvents
      ? (source as RetainedReadEvents).readChanges
      : const Stream.empty();
  @override
  void revalidateReads() {
    if (source is RetainedReadEvents) {
      (source as RetainedReadEvents).revalidateReads();
    }
  }

  @override
  Future<Map<String, dynamic>> load() => source.team();
  @override
  Future<String> invite(StaffAccessDraft draft) =>
      source.invite(draft.toJson());
  @override
  Future<void> update(String id, StaffAccessDraft draft) =>
      source.updateMember(id, draft.toJson());
  @override
  Future<void> accept(String token) => source.accept(token);
  @override
  Future<void> revoke(String id, {bool invitation = false}) =>
      source.revoke(id, invitation: invitation);
}
