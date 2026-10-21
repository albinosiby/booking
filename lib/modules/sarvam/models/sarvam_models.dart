import 'package:equatable/equatable.dart';

/// Endpoints Sarvam's voice agent calls, relative to [SarvamSettings.toolBaseUrl].
const voiceTools = [
  ('catalog', 'List spaces and activities'),
  ('availability', 'Find free times and prices'),
  ('bookings', 'Book a slot'),
  ('my-bookings', "Caller's upcoming bookings"),
  ('reschedule', 'Move a booking'),
  ('cancel', 'Cancel a booking'),
];

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

class SarvamSettings extends Equatable {
  const SarvamSettings({
    this.version = 0,
    this.enabled = false,
    this.connected = false,
    this.apiKeyLast4 = '',
    this.orgId = '',
    this.workspaceId = '',
    this.appId = '',
    this.toolKeyPrefix = '',
    this.toolBaseUrl = '',
    this.businesses = const [],
  });
  factory SarvamSettings.fromJson(Map<String, dynamic> j) => SarvamSettings(
    version: (j['version'] as num?)?.toInt() ?? 0,
    enabled: j['enabled'] == true,
    connected: j['connected'] == true,
    apiKeyLast4: j['api_key_last4'] as String? ?? '',
    orgId: j['sarvam_org_id'] as String? ?? '',
    workspaceId: j['workspace_id'] as String? ?? '',
    appId: j['app_id'] as String? ?? '',
    toolKeyPrefix: j['tool_key_prefix'] as String? ?? '',
    toolBaseUrl: j['tool_base_url'] as String? ?? '',
    businesses: [
      for (final b in j['businesses'] as List? ?? const [])
        SarvamBusiness.fromJson(Map<String, dynamic>.from(b as Map)),
    ],
  );
  final int version;
  final bool enabled, connected;
  final String apiKeyLast4, orgId, workspaceId, appId;
  final String toolKeyPrefix, toolBaseUrl;
  final List<SarvamBusiness> businesses;
  bool get hasToolKey => toolKeyPrefix.isNotEmpty;
  @override
  List<Object?> get props => [
    version,
    enabled,
    connected,
    apiKeyLast4,
    orgId,
    workspaceId,
    appId,
    toolKeyPrefix,
    toolBaseUrl,
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
    this.enabled = false,
    this.orgId = '',
    this.workspaceId = '',
    this.appId = '',
    this.apiKey = '',
    this.businessIds = const {},
    this.loading = true,
    this.busy = false,
    this.newToolKey,
    this.notice,
    this.error,
  });
  final SarvamSettings saved;
  final bool enabled;
  final String orgId, workspaceId, appId;

  /// A newly typed key; empty keeps the saved one.
  final String apiKey;
  final Set<String> businessIds;
  final bool loading, busy;

  /// Shown once after generating a tool key.
  final String? newToolKey;
  final String? notice, error;
  bool get dirty =>
      enabled != saved.enabled ||
      orgId != saved.orgId ||
      workspaceId != saved.workspaceId ||
      appId != saved.appId ||
      apiKey.isNotEmpty ||
      !_sameSet(businessIds, {
        for (final b in saved.businesses)
          if (b.assigned) b.id,
      });
  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);
  SarvamSettingsState fromSaved(SarvamSettings s) => SarvamSettingsState(
    saved: s,
    enabled: s.enabled,
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
    bool? enabled,
    String? orgId,
    String? workspaceId,
    String? appId,
    String? apiKey,
    Set<String>? businessIds,
    bool? loading,
    bool? busy,
    String? newToolKey,
    String? notice,
    String? error,
  }) => SarvamSettingsState(
    saved: saved,
    enabled: enabled ?? this.enabled,
    orgId: orgId ?? this.orgId,
    workspaceId: workspaceId ?? this.workspaceId,
    appId: appId ?? this.appId,
    apiKey: apiKey ?? this.apiKey,
    businessIds: businessIds ?? this.businessIds,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    newToolKey: newToolKey,
    notice: notice,
    error: error,
  );
  @override
  List<Object?> get props => [
    saved,
    enabled,
    orgId,
    workspaceId,
    appId,
    apiKey,
    businessIds,
    loading,
    busy,
    newToolKey,
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
