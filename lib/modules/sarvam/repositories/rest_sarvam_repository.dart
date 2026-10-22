import 'package:url_launcher/url_launcher.dart';
import '../../../utils/services/rest_api_service.dart';
import '../models/sarvam_models.dart';
import 'sarvam_repository.dart';

class RestSarvamRepository implements SarvamRepository {
  RestSarvamRepository(this.api);
  final RestApiService api;
  SarvamSettings _settings(Object? data) =>
      SarvamSettings.fromJson(Map<String, dynamic>.from(data as Map));
  @override
  Future<SarvamSettings> settings() async =>
      _settings(await api.request('/sarvam/settings'));
  @override
  Future<SarvamSettings> connect({
    required int version,
    required Set<String> businessIds,
    required String orgId,
    required String workspaceId,
    required String appId,
    String? apiKey,
  }) async => _settings(
    await api.request(
      '/sarvam/connect',
      method: 'POST',
      data: {
        'version': version,
        'business_ids': businessIds.toList(),
        'sarvam_org_id': orgId,
        'workspace_id': workspaceId,
        'app_id': appId,
        'api_key': ?apiKey,
      },
    ),
  );
  @override
  Future<SarvamSettings> setupStep() async =>
      _settings(await api.request('/sarvam/setup', method: 'POST'));
  @override
  Future<SarvamSettings> disconnect() async =>
      _settings(await api.request('/sarvam/disconnect', method: 'POST'));
  @override
  Future<SarvamSettings> setBookingEnabled(int version, bool enabled) async =>
      _settings(
        await api.request(
          '/sarvam/booking-enabled',
          method: 'PUT',
          data: {'version': version, 'enabled': enabled},
        ),
      );
  @override
  Future<SarvamSettings> publish(int version, String deploymentId) async =>
      _settings(
        await api.request(
          '/sarvam/publish',
          method: 'POST',
          data: {'version': version, 'deployment_id': deploymentId},
        ),
      );
  @override
  Future<bool> openAuthorization(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https' ||
        uri.host != 'mcp.sarvam.ai' ||
        uri.path != '/voice-agents/authorize') {
      return false;
    }
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Future<int> test() async =>
      ((await api.request('/sarvam/test', method: 'POST'))['calls_last_24h']
              as num)
          .toInt();
  @override
  Future<SarvamCallPage> calls(DateTime start, DateTime end) async =>
      SarvamCallPage.fromJson(
        Map<String, dynamic>.from(
          await api.request(
            Uri(
              path: '/sarvam/calls',
              queryParameters: {
                'start': start.toUtc().toIso8601String(),
                'end': end.toUtc().toIso8601String(),
              },
            ).toString(),
          ),
        ),
      );
  String _call(String path, String id) =>
      Uri(path: path, queryParameters: {'interaction_id': id}).toString();
  @override
  Future<List<TranscriptLine>> transcript(String interactionId) async => [
    for (final m
        in (await api.request(
                  _call('/sarvam/transcript', interactionId),
                ))['messages']
                as List? ??
            const [])
      TranscriptLine.fromJson(Map<String, dynamic>.from(m as Map)),
  ];
  @override
  Future<List<int>> recording(String interactionId) => api.bytes(
    _call('/sarvam/recording', interactionId),
    errorMessage: 'Could not download the call recording. Please retry.',
  );
}
