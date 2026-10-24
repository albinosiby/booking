import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../utils/exceptions/app_exception.dart';
import '../../utils/services/rest_api_service.dart';

const supportCategories = {
  'booking': 'Bookings',
  'payments': 'Payments',
  'team': 'Team & access',
  'website': 'Booking website',
  'agent_calls': 'Agent call service',
  'other': 'Something else',
};
const supportStatusLabels = {
  'open': 'Open',
  'in_progress': 'In progress',
  'resolved': 'Resolved',
  'closed': 'Closed',
};

class SupportTicket extends Equatable {
  const SupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    required this.updatedAt,
  });
  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
    id: j['id'] as String,
    subject: j['subject'] as String? ?? '',
    category: j['category'] as String? ?? 'other',
    status: j['status'] as String? ?? 'open',
    updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '')?.toLocal(),
  );
  final String id, subject, category, status;
  final DateTime? updatedAt;
  @override
  List<Object?> get props => [id, subject, category, status, updatedAt];
}

class SupportMessage extends Equatable {
  const SupportMessage({
    required this.fromSupport,
    required this.name,
    required this.body,
    required this.createdAt,
  });
  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
    fromSupport: j['author'] == 'admin',
    name: j['author_name'] as String? ?? '',
    body: j['body'] as String? ?? '',
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
  );
  final bool fromSupport;
  final String name, body;
  final DateTime? createdAt;
  @override
  List<Object?> get props => [fromSupport, name, body, createdAt];
}

class SupportThread extends Equatable {
  const SupportThread(this.ticket, this.messages);
  factory SupportThread.fromJson(Map<String, dynamic> j) => SupportThread(
    SupportTicket.fromJson(Map<String, dynamic>.from(j['ticket'] as Map)),
    [
      for (final m in j['messages'] as List? ?? const [])
        SupportMessage.fromJson(Map<String, dynamic>.from(m as Map)),
    ],
  );
  final SupportTicket ticket;
  final List<SupportMessage> messages;
  @override
  List<Object?> get props => [ticket, messages];
}

abstract interface class SupportRepository {
  Future<List<SupportTicket>> tickets();
  Future<SupportThread> create(String category, String subject, String message);
  Future<SupportThread> thread(String id);
  Future<SupportThread> reply(String id, String message);
}

class RestSupportRepository implements SupportRepository {
  RestSupportRepository(this.api);
  final RestApiService api;
  SupportThread _thread(Object? d) =>
      SupportThread.fromJson(Map<String, dynamic>.from(d as Map));
  @override
  Future<List<SupportTicket>> tickets() async => [
    for (final t
        in (await api.request('/support/tickets'))['tickets'] as List? ??
            const [])
      SupportTicket.fromJson(Map<String, dynamic>.from(t as Map)),
  ];
  @override
  Future<SupportThread> create(
    String category,
    String subject,
    String message,
  ) async => _thread(
    await api.request(
      '/support/tickets',
      method: 'POST',
      data: {'category': category, 'subject': subject, 'message': message},
    ),
  );
  @override
  Future<SupportThread> thread(String id) async =>
      _thread(await api.request('/support/tickets/$id'));
  @override
  Future<SupportThread> reply(String id, String message) async => _thread(
    await api.request(
      '/support/tickets/$id/messages',
      method: 'POST',
      data: {'message': message},
    ),
  );
}

String supportError(Object e) => e is AppException
    ? e.message
    : 'Could not complete this action. Please try again.';

class SupportListState extends Equatable {
  const SupportListState({
    this.tickets = const [],
    this.loading = true,
    this.error,
  });
  final List<SupportTicket> tickets;
  final bool loading;
  final String? error;
  @override
  List<Object?> get props => [tickets, loading, error];
}

class SupportListCubit extends Cubit<SupportListState> {
  SupportListCubit(this.repository) : super(const SupportListState());
  final SupportRepository repository;
  int generation = 0;
  Future<void> load() async {
    if (isClosed) return;
    final request = ++generation;
    emit(SupportListState(tickets: state.tickets, loading: true));
    try {
      final t = await repository.tickets();
      if (!isClosed && request == generation) {
        emit(SupportListState(tickets: t, loading: false));
      }
    } catch (e) {
      if (!isClosed && request == generation) {
        emit(
          SupportListState(
            tickets: state.tickets,
            loading: false,
            error: supportError(e),
          ),
        );
      }
    }
  }
}

class SupportThreadState extends Equatable {
  const SupportThreadState({
    this.thread,
    this.loading = true,
    this.busy = false,
    this.error,
  });
  final SupportThread? thread;
  final bool loading, busy;
  final String? error;
  @override
  List<Object?> get props => [thread, loading, busy, error];
}

class SupportThreadCubit extends Cubit<SupportThreadState> {
  SupportThreadCubit(this.repository, this.id)
    : super(const SupportThreadState());
  final SupportRepository repository;
  final String id;
  int generation = 0;
  Future<void> load() async {
    if (isClosed || state.busy) return;
    final request = ++generation;
    emit(SupportThreadState(thread: state.thread));
    try {
      final t = await repository.thread(id);
      if (!isClosed && request == generation) {
        emit(SupportThreadState(thread: t, loading: false));
      }
    } catch (e) {
      if (!isClosed && request == generation) {
        emit(
          SupportThreadState(
            thread: state.thread,
            loading: false,
            error: supportError(e),
          ),
        );
      }
    }
  }

  /// Returns true when the reply was sent.
  Future<bool> reply(String message) async {
    if (isClosed || state.busy || message.trim().isEmpty) return false;
    ++generation;
    emit(SupportThreadState(thread: state.thread, loading: false, busy: true));
    try {
      final t = await repository.reply(id, message);
      if (!isClosed) emit(SupportThreadState(thread: t, loading: false));
      return true;
    } catch (e) {
      if (!isClosed) {
        emit(
          SupportThreadState(
            thread: state.thread,
            loading: false,
            error: supportError(e),
          ),
        );
      }
      return false;
    }
  }
}
