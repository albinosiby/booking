import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../auth/models/app_user.dart';
import '../../auth/repositories/auth_repository_interface.dart';
import '../models/booking_notification.dart';
import '../models/notification_state.dart';
import '../repositories/notification_repository.dart';

class NotificationCubit extends Cubit<NotificationState> {
  NotificationCubit(this._repository, this._auth)
    : super(const NotificationState());
  final NotificationRepository _repository;
  final AuthRepository _auth;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Set<String> _seen = {};
  Future<void> _queue = Future.value();
  Future<void>? _starting;
  String? _userId;
  String? _logoutUserId;
  int _epoch = 0, _failures = 0;
  bool _initialized = false,
      _started = false,
      _suspended = false,
      _closing = false;
  Timer? _retry;

  Future<void> start() {
    if (_initialized) return Future.value();
    return _starting ??= _start().whenComplete(() => _starting = null);
  }

  Future<void> _start() async {
    if (!_started) {
      _started = true;
      _subscriptions.add(
        _auth.changes.listen(_account, onError: (Object e) => _error()),
      );
    }
    try {
      if (!await _repository.initialize()) return;
      if (isClosed) return;
      _initialized = true;
      _subscriptions.add(
        _repository.tokenChanges.listen(
          (_) => unawaited(refresh()),
          onError: (Object e) => _error(),
        ),
      );
      _subscriptions.add(_repository.foregroundMessages.listen(_message));
      _subscriptions.add(_repository.openedMessages.listen(_open));
      emit(const NotificationState(ready: true));
      if (!_suspended) _account(_auth.currentUser, force: true);
      final initial = await _repository.initialMessage();
      if (initial != null) _open(initial);
    } catch (_) {
      _error();
    }
  }

  void _account(AppUser? user, {bool force = false}) {
    final next = user != null && user.verified && !user.passwordRecovery
        ? user.id
        : null;
    // A delayed session-refresh callback must not undo a logout already in progress.
    if (_suspended && user != null && user.id == _logoutUserId) return;
    if (next == _userId && !_suspended && !force) return;
    final pending = state.pending?.userId == next ? state.pending : null;
    _suspended = false;
    _logoutUserId = null;
    _userId = next;
    _epoch++;
    _failures = 0;
    _retry?.cancel();
    _seen.clear();
    if (!isClosed) {
      emit(NotificationState(ready: _initialized, pending: pending));
    }
    unawaited(refresh());
  }

  Future<void> _serialize(Future<void> Function() work) {
    _queue = _queue.then((_) => work()).catchError((Object e) {
      _error();
    });
    return _queue;
  }

  Future<void> refresh() async {
    if (isClosed || _suspended) return;
    if (!_initialized) {
      await start();
      return;
    }
    final epoch = _epoch, user = _userId;
    await _serialize(() async {
      if (isClosed || epoch != _epoch || _suspended) return;
      final registered = user == null
          ? false
          : await _repository.register(user);
      if (user == null) await _repository.unregister();
      if (!isClosed && epoch == _epoch) {
        _failures = 0;
        _retry?.cancel();
        emit(
          NotificationState(
            ready: true,
            registered: registered,
            pending: state.pending,
          ),
        );
      }
    });
  }

  void resumed() {
    unawaited(refresh());
  }

  Future<void> signOut() async {
    _suspended = true;
    _logoutUserId = _auth.currentUser?.id;
    _epoch++;
    _userId = null;
    _retry?.cancel();
    _seen.clear();
    if (!isClosed) emit(NotificationState(ready: _initialized));
    await _serialize(_repository.unregister);
  }

  void _message(BookingNotification message) {
    if (_userId != message.userId ||
        _suspended ||
        !_seen.add(message.eventId)) {
      return;
    }
    if (_seen.length > 100) _seen.remove(_seen.first);
    unawaited(
      _repository.show(message).catchError((Object e) {
        _error();
      }),
    );
  }

  void _open(BookingNotification message) {
    if (isClosed || _suspended) return;
    // An initial notification may arrive before login is restored. Validate its account again on consumption.
    if (_userId != null && _userId != message.userId) return;
    emit(
      NotificationState(
        ready: _initialized,
        registered: state.registered,
        pending: message,
      ),
    );
  }

  void consume() {
    if (!isClosed) {
      emit(
        NotificationState(ready: _initialized, registered: state.registered),
      );
    }
  }

  void _error() {
    if (isClosed || _closing) return;
    debugPrint(
      'Booking notification setup/cleanup unavailable; retry pending.',
    );
    emit(
      NotificationState(
        ready: _initialized,
        error: 'Notifications are temporarily unavailable.',
        pending: state.pending,
      ),
    );
    if (!_suspended && _failures++ < 5) {
      _retry?.cancel();
      _retry = Timer(
        Duration(seconds: 5 * (1 << (_failures - 1))),
        () => unawaited(refresh()),
      );
    }
  }

  @override
  Future<void> close() async {
    _closing = true;
    _epoch++;
    _retry?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _queue;
    await _repository.dispose();
    return super.close();
  }
}
