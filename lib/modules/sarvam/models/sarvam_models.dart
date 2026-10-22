import 'package:equatable/equatable.dart';

class SarvamBusiness extends Equatable {
  const SarvamBusiness({
    required this.id,
    required this.name,
    required this.ready,
    required this.assigned,
  });
  factory SarvamBusiness.fromJson(Map<String, dynamic> j) => SarvamBusiness(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    ready: j['status'] == 'ready',
    assigned: j['assigned'] == true,
  );
  final String id, name;
  final bool ready, assigned;
  @override
  List<Object?> get props => [id, name, ready, assigned];
}

class SarvamDeployment extends Equatable {
  const SarvamDeployment({required this.id, required this.name});
  final String id, name;
  @override
  List<Object?> get props => [id, name];
}

class SarvamSettings extends Equatable {
  const SarvamSettings({
    this.version = 0,
    this.enabled = false,
    this.connected = false,
    this.hasCredentials = false,
    this.callLogsAvailable = false,
    this.apiKeyLast4 = '',
    this.orgId = '',
    this.workspaceId = '',
    this.appId = '',
    this.status = 'disconnected',
    this.step = '',
    this.setupError = '',
    this.authorizationUrl = '',
    this.draftVersion,
    this.publishedVersion,
    this.deployments = const [],
    this.businesses = const [],
  });
  factory SarvamSettings.fromJson(Map<String, dynamic> j) => SarvamSettings(
    version: (j['version'] as num?)?.toInt() ?? 0,
    enabled: j['enabled'] == true,
    connected: j['connected'] == true,
    hasCredentials: j['has_credentials'] == true,
    callLogsAvailable: j['call_logs_available'] == true,
    apiKeyLast4: j['api_key_last4'] as String? ?? '',
    orgId: j['sarvam_org_id'] as String? ?? '',
    workspaceId: j['workspace_id'] as String? ?? '',
    appId: j['app_id'] as String? ?? '',
    status: j['setup_status'] as String? ?? 'disconnected',
    step: j['setup_step'] as String? ?? '',
    setupError: j['setup_error'] as String? ?? '',
    authorizationUrl: j['authorization_url'] as String? ?? '',
    draftVersion: (j['draft_version'] as num?)?.toInt(),
    publishedVersion: (j['published_version'] as num?)?.toInt(),
    deployments: [
      for (final d in j['deployments'] as List? ?? [])
        SarvamDeployment(id: d['id'] as String, name: d['name'] as String),
    ],
    businesses: [
      for (final b in j['businesses'] as List? ?? [])
        SarvamBusiness.fromJson(Map<String, dynamic>.from(b as Map)),
    ],
  );
  final int version;
  final bool enabled, connected, hasCredentials, callLogsAvailable;
  final String apiKeyLast4,
      orgId,
      workspaceId,
      appId,
      status,
      step,
      setupError,
      authorizationUrl;
  final int? draftVersion, publishedVersion;
  final List<SarvamDeployment> deployments;
  final List<SarvamBusiness> businesses;
  bool get needsWork => [
    'connecting',
    'failed',
    'publishing',
    'cleanup_pending',
  ].contains(status);
  bool get canEnableBookings =>
      status == 'legacy' || connected && publishedVersion != null;
  bool get awaitingPublish => connected && draftVersion != publishedVersion;
  String get statusLabel => switch (status) {
    'connecting' => 'Connecting',
    'authorization_required' => 'Authorize Sarvam',
    'failed' => 'Setup failed — Retry',
    'publishing' => 'Publishing',
    'cleanup_pending' => 'Disconnected — cleanup pending',
    'configured' =>
      awaitingPublish ? 'Configured — awaiting publish' : 'Connected',
    'legacy' => 'Connect to upgrade setup',
    _ => 'Disconnected',
  };
  String get progressLabel => switch (step) {
    'verify_credentials' => 'Verifying API key and IDs',
    'authorize' =>
      status == 'authorization_required'
          ? 'Waiting for Sarvam sign-in'
          : 'Preparing Sarvam sign-in',
    'capabilities' => 'Checking authoring permissions',
    'scope' => 'Verifying agent and workspace',
    'secret' => 'Configuring secure tool authentication',
    'variables' => 'Configuring agent variables',
    'enable_tools' => 'Enabling booking tools',
    'prompt' => 'Configuring booking instructions',
    'verify' => 'Verifying booking configuration',
    'deployments' => 'Loading phone deployments',
    'commit' => 'Saving the reviewed agent version',
    'deploy' => 'Updating the selected phone deployment',
    'verify_publish' => 'Verifying the published version',
    'cleanup_tools' => 'Disabling managed tools',
    'cleanup_secret' => 'Revoking remote booking access',
    _ => step.startsWith('tool_') ? 'Configuring booking tools' : '',
  };
  @override
  List<Object?> get props => [
    version,
    enabled,
    connected,
    hasCredentials,
    callLogsAvailable,
    apiKeyLast4,
    orgId,
    workspaceId,
    appId,
    status,
    step,
    setupError,
    authorizationUrl,
    draftVersion,
    publishedVersion,
    deployments,
    businesses,
  ];
}

class SarvamCall extends Equatable {
  const SarvamCall({
    required this.id,
    this.startedAt,
    this.durationSeconds = 0,
    this.language = '',
    this.direction = '',
    this.contact = '',
    this.callerName = '',
    this.summary = '',
    this.enquiryType = '',
    this.disposition = '',
    this.requestedFacility = '',
    this.preferredDatetime = '',
  });
  factory SarvamCall.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k] as String? ?? '';
    final started = s('started_at');
    return SarvamCall(
      id: s('interaction_id'),
      // Sarvam omits the zone suffix; observed timestamps are UTC.
      startedAt: started.isEmpty
          ? null
          : DateTime.tryParse(
              RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(started)
                  ? started
                  : '${started.replaceFirst(' ', 'T')}Z',
            )?.toLocal(),
      durationSeconds: (j['duration_seconds'] as num?)?.toDouble() ?? 0,
      language: s('language'),
      direction: s('direction'),
      contact: s('contact').isNotEmpty ? s('contact') : s('contact_masked'),
      callerName: s('caller_name'),
      summary: s('summary'),
      enquiryType: s('enquiry_type'),
      disposition: s('disposition'),
      requestedFacility: s('requested_facility'),
      preferredDatetime: s('preferred_datetime'),
    );
  }
  final String id;
  final DateTime? startedAt;
  final double durationSeconds;
  final String language, direction, contact, callerName, summary;
  final String enquiryType, disposition, requestedFacility, preferredDatetime;
  String get title => callerName.isNotEmpty
      ? callerName
      : contact.isNotEmpty
      ? contact
      : 'Unknown caller';
  String get duration {
    final total = durationSeconds.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  List<Object?> get props => [id, startedAt, durationSeconds, summary];
}

class SarvamCallPage extends Equatable {
  const SarvamCallPage({this.items = const [], this.total = 0});
  factory SarvamCallPage.fromJson(Map<String, dynamic> j) => SarvamCallPage(
    items: [
      for (final c in j['items'] as List? ?? const [])
        SarvamCall.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    total: (j['total'] as num?)?.toInt() ?? 0,
  );
  final List<SarvamCall> items;
  final int total;
  @override
  List<Object?> get props => [items, total];
}

class TranscriptLine extends Equatable {
  const TranscriptLine({required this.agent, required this.text});
  factory TranscriptLine.fromJson(Map<String, dynamic> j) => TranscriptLine(
    agent: j['role'] == 'agent',
    text: j['text'] as String? ?? '',
  );
  final bool agent;
  final String text;
  @override
  List<Object?> get props => [agent, text];
}

class SarvamSettingsState extends Equatable {
  const SarvamSettingsState({
    this.saved = const SarvamSettings(),
    this.orgId = '',
    this.workspaceId = '',
    this.appId = '',
    this.apiKey = '',
    this.businessIds = const {},
    this.loading = true,
    this.busy = false,
    this.notice,
    this.error,
  });
  final SarvamSettings saved;
  final String orgId, workspaceId, appId, apiKey;
  final Set<String> businessIds;
  final bool loading, busy;
  final String? notice, error;
  bool get dirty =>
      orgId != saved.orgId ||
      workspaceId != saved.workspaceId ||
      appId != saved.appId ||
      apiKey.isNotEmpty ||
      businessIds.length != saved.businesses.where((b) => b.assigned).length ||
      !businessIds.containsAll(
        saved.businesses.where((b) => b.assigned).map((b) => b.id),
      );
  SarvamSettingsState fromSaved(SarvamSettings s) => SarvamSettingsState(
    saved: s,
    orgId: s.orgId,
    workspaceId: s.workspaceId,
    appId: s.appId,
    businessIds: {
      for (final b in s.businesses)
        if (b.assigned) b.id,
    },
    loading: false,
  );
  SarvamSettingsState copyWith({
    SarvamSettings? saved,
    String? orgId,
    String? workspaceId,
    String? appId,
    String? apiKey,
    Set<String>? businessIds,
    bool? loading,
    bool? busy,
    String? notice,
    String? error,
  }) => SarvamSettingsState(
    saved: saved ?? this.saved,
    orgId: orgId ?? this.orgId,
    workspaceId: workspaceId ?? this.workspaceId,
    appId: appId ?? this.appId,
    apiKey: apiKey ?? this.apiKey,
    businessIds: businessIds ?? this.businessIds,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    notice: notice,
    error: error,
  );
  @override
  List<Object?> get props => [
    saved,
    orgId,
    workspaceId,
    appId,
    apiKey,
    businessIds,
    loading,
    busy,
    notice,
    error,
  ];
}

class CallLogsState extends Equatable {
  const CallLogsState({
    required this.day,
    this.page = const SarvamCallPage(),
    this.loading = true,
    this.error,
  });
  final DateTime day;
  final SarvamCallPage page;
  final bool loading;
  final String? error;
  CallLogsState copyWith({
    DateTime? day,
    SarvamCallPage? page,
    bool? loading,
    String? error,
  }) => CallLogsState(
    day: day ?? this.day,
    page: page ?? this.page,
    loading: loading ?? this.loading,
    error: error,
  );
  @override
  List<Object?> get props => [day, page, loading, error];
}

class CallDetailState extends Equatable {
  const CallDetailState({
    this.lines = const [],
    this.loading = true,
    this.saving = false,
    this.notice,
    this.error,
  });
  final List<TranscriptLine> lines;
  final bool loading, saving;
  final String? notice, error;
  CallDetailState copyWith({
    List<TranscriptLine>? lines,
    bool? loading,
    bool? saving,
    String? notice,
    String? error,
  }) => CallDetailState(
    lines: lines ?? this.lines,
    loading: loading ?? this.loading,
    saving: saving ?? this.saving,
    notice: notice,
    error: error,
  );
  @override
  List<Object?> get props => [lines, loading, saving, notice, error];
}
