import 'package:uuid/uuid.dart';
import '../../../constants/api_path.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/coach_class.dart';
import '../../workspace/repositories/refreshable_reads.dart';

/// Coach endpoints: plan assignment, the owner's coach opt-in, overlap
/// checks and a coach's own classes.
abstract interface class CoachApi {
  /// Sets the coach (or null) of the given plans without other changes.
  Future<void> assignPlans(
    String businessId,
    int version,
    Map<String, String?> coaches,
  );
  Future<void> setOwnerCoach(bool coach);

  /// Upcoming class clashes if [coachId] coached exactly [planIds].
  Future<List<String>> conflicts(
    String businessId,
    String coachId,
    Set<String> planIds,
  );
  Future<CoachRoster> classes(String date);
  Future<void> mark(CoachStudent student, String attendance);
  Future<FlexibleAttendanceResult> checkIn(
    FlexibleCoachStudent student, {
    required String commandKey,
    required bool startClass,
  });
}

class RestCoachApi implements CoachApi, RetainedReadEvents {
  RestCoachApi(this.api);
  final RestApiService api;
  @override
  Stream<void> get readChanges => api.readUpdates
      .where((key) => key == '*' || key.startsWith('/admissions'))
      .map((_) {});
  @override
  void revalidateReads() => api.revalidateReads();
  @override
  Future<void> assignPlans(
    String businessId,
    int version,
    Map<String, String?> coaches,
  ) async {
    await api.request(
      '${ApiPath.businesses}/$businessId/plan-coaches',
      method: 'PATCH',
      data: {'version': version, 'coaches': coaches},
    );
  }

  @override
  Future<void> setOwnerCoach(bool coach) async {
    await api.request(
      '${ApiPath.team}/me/coach',
      method: 'PUT',
      data: {'coach': coach},
    );
  }

  @override
  Future<List<String>> conflicts(
    String businessId,
    String coachId,
    Set<String> planIds,
  ) async {
    if (planIds.isEmpty) return const [];
    final j = await api.request(
      '/admissions/coach-conflicts',
      method: 'POST',
      data: {
        'business_id': businessId,
        'coach_id': coachId,
        'plan_ids': planIds.toList(),
      },
    );
    return List.unmodifiable(
      (j['items'] as List).map(
        (v) => '${v['plan_name']} and ${v['other_plan_name']} · ${v['label']}',
      ),
    );
  }

  @override
  Future<CoachRoster> classes(String date) async {
    final j = await api.request(
      Uri(
        path: '/admissions/classes',
        queryParameters: {'date': date},
      ).toString(),
    );
    return CoachRoster(
      classes: (j['classes'] as List).map(
        (c) => CoachClass.fromJson(Map<String, dynamic>.from(c)),
      ),
      flexibleStudents: (j['flexible_students'] as List? ?? []).map(
        (s) => FlexibleCoachStudent.fromJson(Map<String, dynamic>.from(s)),
      ),
    );
  }

  @override
  Future<FlexibleAttendanceResult> checkIn(
    FlexibleCoachStudent student, {
    required String commandKey,
    required bool startClass,
  }) async {
    final j = await api.request(
      '/admissions/${student.admissionId}/check-ins',
      method: 'POST',
      data: {
        'command_key': commandKey,
        'version': student.version,
        'start_class': startClass,
      },
    );
    return FlexibleAttendanceResult(
      started: j['class_started'] == true,
      localMarkedAt: j['local_marked_at'],
      localStart: j['local_start'],
      localEnd: j['local_end'],
    );
  }

  @override
  Future<void> mark(CoachStudent student, String attendance) async {
    await api.request(
      '/admissions/${student.admissionId}/sessions/${student.visitId}/attendance',
      method: 'POST',
      data: {
        'command_key': const Uuid().v4(),
        'version': student.version,
        'attendance': attendance,
        'reason': '',
      },
    );
  }
}
