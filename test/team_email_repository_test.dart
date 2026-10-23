import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:eden_booking/modules/workspace/repositories/rest_workspace_repository.dart';
import 'package:eden_booking/modules/team/repositories/team_repository.dart';
import 'package:eden_booking/modules/team/models/staff_access_draft.dart';

class TeamApi extends Fake implements RestApiService {
  final calls = <Map<String, dynamic>>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool readOnly = false,
  }) async {
    calls.add({
      'path': path,
      'method': method,
      'data': data,
      'readOnly': readOnly,
    });
    if (path == '/workspace/session') {
      return {
        'organization': null,
        'membership': null,
        'businesses': [],
        'locations': [],
      };
    }
    if (path == '/team' && method == 'GET') {
      return {'members': [], 'invitations': []};
    }
    return {'id': 'pending', 'delivery': 'sent'};
  }

  @override
  Future<void> authorizeReads(Map<String, dynamic> data) async {}
}

void main() {
  test(
    'workspace bootstrap uses an authenticated session command before authorizing cached reads',
    () async {
      final api = TeamApi();
      await RestWorkspaceRepository(api).load();
      expect(api.calls.single, {
        'path': '/workspace/session',
        'method': 'POST',
        'data': null,
        'readOnly': true,
      });
    },
  );
  test(
    'team add, pending edit and resend use email endpoints without a share URL',
    () async {
      final api = TeamApi(),
          draft = StaffAccessDraft(
            name: 'Staff',
            email: 'staff@example.com',
            role: 'staff',
            permissions: [],
            assignments: [BusinessAssignment('business', [])],
          );
      final team = LocalApiTeamRepository(RestWorkspaceRepository(api));
      expect((await team.add(draft)).sent, true);
      expect((await team.updatePending('pending', draft)).sent, true);
      expect((await team.resendEmail('pending')).sent, true);
      expect(api.calls.map((c) => '${c['method']} ${c['path']}'), [
        'POST /team',
        'PATCH /invitations/pending/access',
        'POST /invitations/pending/email',
      ]);
      expect(api.calls.first['data'], draft.toJson());
    },
  );
  test('team status refresh always reads the current server state', () async {
    final api = TeamApi();
    final team = LocalApiTeamRepository(RestWorkspaceRepository(api));
    await team.load();
    await team.load();
    expect(api.calls.map((c) => c['path']), ['/team', '/team']);
    expect(api.calls.every((c) => c['method'] == 'GET'), true);
  });
}
