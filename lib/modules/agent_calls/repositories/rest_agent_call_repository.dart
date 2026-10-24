import '../../../utils/services/rest_api_service.dart';
import '../models/agent_call_models.dart';
import 'agent_call_repository.dart';

class RestAgentCallRepository implements AgentCallRepository {
  RestAgentCallRepository(this.api);
  final RestApiService api;
  AgentServiceStatus _status(Object? data) =>
      AgentServiceStatus.fromJson(Map<String, dynamic>.from(data as Map));
  @override
  Future<AgentServiceStatus> status() async =>
      _status(await api.request('/agent-calls'));
  @override
  Future<AgentServiceStatus> request(
    String note,
    List<CallService> services,
  ) async => _status(
    await api.request(
      '/agent-calls/request',
      method: 'POST',
      data: {'note': note, 'services': services.map((s) => s.id).toList()},
    ),
  );
  @override
  Future<AgentServiceStatus> setEnabled(bool enabled, int version) async =>
      _status(
        await api.request(
          '/agent-calls/enabled',
          method: 'PUT',
          data: {'enabled': enabled, 'version': version},
        ),
      );
  @override
  Future<AgentServiceStatus> setSpaces(List<String> ids, int version) async =>
      _status(
        await api.request(
          '/agent-calls/spaces',
          method: 'PUT',
          data: {'resource_ids': ids, 'version': version},
        ),
      );
  @override
  Future<AgentCallPage> calls(
    DateTime start,
    DateTime end, {
    int offset = 0,
  }) async => AgentCallPage.fromJson(
    Map<String, dynamic>.from(
      await api.request(
        Uri(
          path: '/agent-calls/calls',
          queryParameters: {
            'start': start.toUtc().toIso8601String(),
            'end': end.toUtc().toIso8601String(),
            'offset': '$offset',
          },
        ).toString(),
      ),
    ),
  );
  String _call(String path, String id) =>
      Uri(path: path, queryParameters: {'interaction_id': id}).toString();
  @override
  Future<List<TranscriptLine>> transcript(String interactionId) async {
    final data = Map<String, dynamic>.from(
      await api.request(_call('/agent-calls/transcript', interactionId)) as Map,
    );
    final messages = [
      for (final m in data['messages'] as List? ?? const [])
        TranscriptLine.fromJson(Map<String, dynamic>.from(m as Map)),
    ];
    if (messages.isEmpty &&
        data['text'] is String &&
        (data['text'] as String).isNotEmpty) {
      return [
        TranscriptLine(
          agent: true,
          text: data['text'] as String,
          unattributed: true,
        ),
      ];
    }
    return messages;
  }

  @override
  Future<List<int>> recording(String interactionId) => api.bytes(
    _call('/agent-calls/recording', interactionId),
    errorMessage: 'Could not download the call recording. Please retry.',
  );
}
