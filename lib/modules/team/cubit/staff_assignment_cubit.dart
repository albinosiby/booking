import 'dart:convert';
import '../../../core/state/workspace_screen_cubit.dart';
import '../../workspace/repositories/workspace_session.dart';
import '../repositories/team_repository.dart';
import '../models/staff_access_draft.dart';
import '../models/staff_assignment_screen_model.dart';
import '../../workspace/cubit/workspace_state.dart';

class StaffAssignmentCubit
    extends WorkspaceScreenCubit<StaffAssignmentScreenModel> {
  StaffAssignmentCubit(
    WorkspaceSession session,
    this.repository, {
    Map<String, dynamic>? member,
  }) : super(session, StaffAssignmentScreenModel.fromSnapshot) {
    if (member != null) {
      final businesses = <String>{}, restricted = <String>{};
      final resources = <String, Set<String>>{};
      for (final assignment in member['assignments']) {
        final id = assignment['business_id'] as String;
        businesses.add(id);
        final ids = Set<String>.from(assignment['resource_ids']);
        if (ids.isNotEmpty) {
          restricted.add(id);
          resources[id] = ids;
        }
      }
      emit(
        state.copyWith(
          role: member['role'],
          businesses: businesses,
          restricted: restricted,
          resources: resources,
          permissions: {
            ...List<String>.from(member['permissions'] ?? const []),
            if ((member['permissions'] as List? ?? []).contains(
              'manage_attendance',
            ))
              'mark_attendance',
          }..remove('manage_attendance'),
        ),
      );
    }
    _savedCoachingScope = _coachingScope;
  }
  late String _savedCoachingScope;
  String get _coachingScope => jsonEncode({
    'coach': state.permissions.contains('coach'),
    'assignments': {
      for (final id in state.businesses.toList()..sort())
        id: state.restricted.contains(id)
            ? ((state.resources[id]?.toList() ?? <String>[])..sort())
            : <String>[],
    },
  });
  bool get coachingAccessChanged => _coachingScope != _savedCoachingScope;
  final TeamRepository repository;
  @override
  StaffAssignmentScreenModel mapSnapshot(WorkspaceState snapshot) =>
      state.copyWith(snapshot: snapshot);
  Set<String> _toggle(Set<String> source, String id, bool enabled) {
    final result = {...source};
    enabled ? result.add(id) : result.remove(id);
    return result;
  }

  void selectRole(String role) => emit(state.copyWith(role: role));
  void selectBusiness(String id, bool enabled) =>
      emit(state.copyWith(businesses: _toggle(state.businesses, id, enabled)));
  void restrictBusiness(String id, bool enabled) =>
      emit(state.copyWith(restricted: _toggle(state.restricted, id, enabled)));
  void selectPermission(String id, bool enabled) => emit(
    state.copyWith(permissions: _toggle(state.permissions, id, enabled)),
  );
  void selectResource(String business, String resource, bool enabled) => emit(
    state.copyWith(
      resources: {
        ...state.resources,
        business: _toggle(state.resources[business] ?? {}, resource, enabled),
      },
    ),
  );
  Future<String?> invite(StaffAccessDraft draft) async {
    String? link;
    final ok = await save(() async {
      link = await repository.invite(draft);
    });
    return ok ? link : null;
  }

  Future<bool> update(String id, StaffAccessDraft draft) async {
    final savedScope = _coachingScope;
    final ok = await save(() => repository.update(id, draft));
    if (ok && !isClosed) {
      _savedCoachingScope = savedScope;
      emit(state.copyWith(accessRevision: state.accessRevision + 1));
    }
    return ok;
  }
}
