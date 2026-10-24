import 'package:equatable/equatable.dart';

enum CallService {
  booking('booking', 'Booking', 'Create bookings for available spaces.'),
  rescheduling(
    'rescheduling',
    'Rescheduling',
    'Change the date or time of a booking.',
  ),
  enquiry(
    'enquiry',
    'Enquiries',
    'Answer questions about spaces, availability and prices.',
  ),
  cancellation(
    'cancellation',
    'Cancellation',
    'Cancel a caller’s existing booking.',
  );

  const CallService(this.id, this.label, this.description);
  final String id, label, description;
}

class CallSpace extends Equatable {
  const CallSpace({
    required this.id,
    required this.name,
    required this.businessId,
    required this.businessName,
    this.ready = false,
    this.enabled = false,
  });
  factory CallSpace.fromJson(Map<String, dynamic> j) => CallSpace(
    id: j['id'] as String,
    name: j['name'] as String,
    businessId: j['business_id'] as String,
    businessName: j['business_name'] as String,
    ready: j['business_status'] == 'ready',
    enabled: j['enabled'] == true,
  );
  final String id, name, businessId, businessName;
  final bool ready, enabled;
  @override
  List<Object?> get props => [
    id,
    name,
    businessId,
    businessName,
    ready,
    enabled,
  ];
}

class AgentCall extends Equatable {
  const AgentCall({
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
  factory AgentCall.fromJson(Map<String, dynamic> j) {
    String s(String k) => j[k] as String? ?? '';
    final started = s('started_at');
    return AgentCall(
      id: s('interaction_id'),
      // The provider omits the zone suffix; observed timestamps are UTC.
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

class AgentCallPage extends Equatable {
  const AgentCallPage({
    this.items = const [],
    this.total = 0,
    this.nextOffset,
    this.warning = '',
  });
  factory AgentCallPage.fromJson(Map<String, dynamic> j) => AgentCallPage(
    items: [
      for (final c in j['items'] as List? ?? const [])
        AgentCall.fromJson(Map<String, dynamic>.from(c as Map)),
    ],
    total: (j['total'] as num?)?.toInt() ?? 0,
    nextOffset: (j['next_offset'] as num?)?.toInt(),
    warning: j['warning'] as String? ?? '',
  );
  final List<AgentCall> items;
  final int total;
  final int? nextOffset;
  final String warning;
  @override
  List<Object?> get props => [items, total, nextOffset, warning];
}

class TranscriptLine extends Equatable {
  const TranscriptLine({
    required this.agent,
    required this.text,
    this.unattributed = false,
  });
  factory TranscriptLine.fromJson(Map<String, dynamic> j) => TranscriptLine(
    agent: j['role'] == 'agent',
    text: j['text'] as String? ?? '',
  );
  final bool agent;
  final bool unattributed;
  final String text;
  @override
  List<Object?> get props => [agent, text, unattributed];
}

class CallLogsState extends Equatable {
  const CallLogsState({
    required this.day,
    this.page = const AgentCallPage(),
    this.loading = true,
    this.error,
  });
  final DateTime day;
  final AgentCallPage page;
  final bool loading;
  final String? error;
  CallLogsState copyWith({
    DateTime? day,
    AgentCallPage? page,
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

/// Progress of the owner's agent call service request.
class AgentServiceStatus extends Equatable {
  const AgentServiceStatus({
    this.status = 'none',
    this.message = '',
    this.ready = false,
    this.enabled = false,
    this.requestedAt,
    this.updatedAt,
    this.phoneNumber = '',
    this.version = 0,
    this.requestedServices = const [],
    this.approvedServices = const [],
    this.spaces = const [],
    this.callLogsAvailable = false,
  });
  factory AgentServiceStatus.fromJson(
    Map<String, dynamic> j,
  ) => AgentServiceStatus(
    status: j['status'] as String? ?? 'none',
    message: j['message'] as String? ?? '',
    ready: j['ready'] == true,
    enabled: j['enabled'] == true,
    requestedAt: DateTime.tryParse(j['requested_at'] as String? ?? ''),
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? ''),
    phoneNumber: j['phone_number'] as String? ?? '',
    version: (j['version'] as num?)?.toInt() ?? 0,
    requestedServices: CallService.values
        .where((v) => (j['requested_services'] as List? ?? []).contains(v.id))
        .toList(),
    approvedServices: CallService.values
        .where((v) => (j['approved_services'] as List? ?? []).contains(v.id))
        .toList(),
    spaces: [
      for (final item in j['spaces'] as List? ?? [])
        CallSpace.fromJson(Map<String, dynamic>.from(item as Map)),
    ],
    callLogsAvailable: j['call_logs_available'] == true,
  );
  final String status, message, phoneNumber;
  final int version;
  final List<CallService> requestedServices, approvedServices;
  final List<CallSpace> spaces;
  final bool callLogsAvailable;
  final bool ready, enabled;
  final DateTime? requestedAt, updatedAt;
  @override
  List<Object?> get props => [
    status,
    message,
    ready,
    enabled,
    requestedAt,
    updatedAt,
    phoneNumber,
    version,
    requestedServices,
    approvedServices,
    spaces,
    callLogsAvailable,
  ];
}

class AgentServiceState extends Equatable {
  const AgentServiceState({
    this.status = const AgentServiceStatus(),
    this.loading = true,
    this.busy = false,
    this.selectedServices = const [CallService.booking],
    this.error,
  });
  final AgentServiceStatus status;
  final List<CallService> selectedServices;
  final bool loading, busy;
  final String? error;
  AgentServiceState copyWith({
    AgentServiceStatus? status,
    bool? loading,
    bool? busy,
    List<CallService>? selectedServices,
    Object? error = _keep,
  }) => AgentServiceState(
    status: status ?? this.status,
    loading: loading ?? this.loading,
    busy: busy ?? this.busy,
    selectedServices: selectedServices ?? this.selectedServices,
    error: identical(error, _keep) ? this.error : error as String?,
  );
  @override
  List<Object?> get props => [status, loading, busy, selectedServices, error];
}

const _keep = Object();
