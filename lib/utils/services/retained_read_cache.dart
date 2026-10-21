import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../exceptions/app_exception.dart';

/// Application read snapshots, separate from the HTTP cache. Repositories opt in;
/// writes, authentication, quotes, availability and downloaded reports never do.
abstract interface class ReadSnapshotStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}

class SecureReadSnapshotStore implements ReadSnapshotStore {
  const SecureReadSnapshotStore(this.storage);
  final FlutterSecureStorage storage;
  static const key = 'booking.read-snapshots.v1';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> clear() => storage.delete(key: key);
}

class _Snapshot {
  _Snapshot(this.json, this.savedAt, this.freshFor, this.retainFor);
  final String json;
  final DateTime savedAt;
  final Duration freshFor, retainFor;
  Map<String, Object> toJson() => {
    'data': json,
    'saved': savedAt.millisecondsSinceEpoch,
    'fresh': freshFor.inMilliseconds,
    'retain': retainFor.inMilliseconds,
  };
}

class RetainedReadCache {
  RetainedReadCache({
    required this.store,
    required this.identity,
    DateTime Function()? now,
    this.maxEntries = 80,
    this.maxBytes = 2 * 1024 * 1024,
  }) : now = now ?? DateTime.now;
  final ReadSnapshotStore store;
  final String? Function() identity;
  final DateTime Function() now;
  final int maxEntries, maxBytes;
  final _entries = <String, _Snapshot>{};
  final _pending = <String, Future<dynamic>>{};
  final _failures = <String, (Object, DateTime)>{};
  final _updates = StreamController<String>.broadcast();
  Stream<String> get updates => _updates.stream;
  String? _scope, _user;
  Object? _denied;
  int _epoch = 0;
  Timer? _timer;
  Future<void> _disk = Future.value();
  bool get _authorized =>
      _scope != null && _user != null && _user == identity();

  /// Called only after an authoritative workspace read. The scope includes the
  /// backend, user, organization, membership permissions and assigned spaces.
  Future<void> authorize(String scope) async {
    if (_authorized && _scope == scope) return;
    final user = identity();
    final epoch = ++_epoch;
    _scope = scope;
    _user = user;
    _denied = null;
    _entries.clear();
    _pending.clear();
    _failures.clear();
    _timer?.cancel();
    if (user == null) return;
    try {
      await _disk;
      final raw = await store.read();
      if (epoch != _epoch || !_authorized || raw == null) return;
      final data = jsonDecode(raw) as Map;
      if (data['scope'] != scope) {
        _schedulePersist();
        return;
      }
      for (final item in (data['items'] as Map).entries.take(maxEntries)) {
        final value = item.value as Map;
        final entry = _Snapshot(
          value['data'] as String,
          DateTime.fromMillisecondsSinceEpoch(value['saved'] as int),
          Duration(milliseconds: value['fresh'] as int),
          Duration(milliseconds: value['retain'] as int),
        );
        if (_usable(entry)) _entries[item.key as String] = entry;
      }
      _trim();
    } catch (_) {
      // Corrupt/unsupported secure storage must never block server reads.
      if (epoch == _epoch) _entries.clear();
    }
  }

  bool _usable(_Snapshot e) {
    final age = now().difference(e.savedAt);
    return !age.isNegative && age < e.retainFor;
  }

  Future<dynamic> read(
    String key,
    Future<dynamic> Function() fetch, {
    required Duration freshFor,
    required Duration retainFor,
  }) async {
    if (_denied != null) throw _denied!;
    if (!_authorized) return fetch();
    final failure = _failures[key];
    final coolingDown =
        failure != null && now().difference(failure.$2).inSeconds < 10;
    final value = _entries.remove(key);
    if (value != null &&
        _usable(value) &&
        now().difference(value.savedAt) < retainFor) {
      _entries[key] = value;
      if (!coolingDown && now().difference(value.savedAt) >= freshFor) {
        // Observe failure through updates; never leak an unhandled future.
        unawaited(
          _fetch(key, fetch, freshFor, retainFor).catchError((_) => null),
        );
      }
      return jsonDecode(value.json);
    }
    if (coolingDown) throw failure.$1;
    return _fetch(key, fetch, freshFor, retainFor);
  }

  Future<dynamic> _fetch(
    String key,
    Future<dynamic> Function() fetch,
    Duration freshFor,
    Duration retainFor,
  ) {
    final existing = _pending[key];
    if (existing != null) return existing;
    final epoch = _epoch;
    final future = () async {
      try {
        final value = await fetch();
        if (epoch != _epoch || !_authorized) {
          throw const AppException(
            'Your access changed. Refresh to continue.',
            code: 'CANCELLED',
          );
        }
        final previous = _entries[key];
        final recovered = _failures.remove(key) != null;
        final encoded = jsonEncode(value);
        _entries[key] = _Snapshot(encoded, now(), freshFor, retainFor);
        _trim();
        _schedulePersist();
        if (previous != null && (previous.json != encoded || recovered)) {
          _updates.add(key);
        }
        return value;
      } catch (e) {
        if (epoch == _epoch && _authorized) {
          if (accessFailure(e)) {
            lock(error: e);
          } else {
            _failures[key] = (e, now());
            while (_failures.length > maxEntries) {
              _failures.remove(_failures.keys.first);
            }
            _updates.add(key);
          }
        }
        rethrow;
      } finally {
        if (epoch == _epoch) _pending.remove(key);
      }
    }();
    _pending[key] = future;
    return future;
  }

  void _trim() {
    _entries.removeWhere((_, value) => !_usable(value));
    var size = _entries.entries.fold(
      0,
      (n, e) =>
          n + utf8.encode(e.key).length + utf8.encode(e.value.json).length,
    );
    while (_entries.length > maxEntries || size > maxBytes) {
      final key = _entries.keys.first;
      size -=
          utf8.encode(key).length +
          utf8.encode(_entries.remove(key)!.json).length;
    }
  }

  void revalidate() => _updates.add('*');

  void invalidate({bool notify = true, bool Function(String key)? keep}) {
    _epoch++;
    _pending.clear();
    _entries.removeWhere(
      (key, value) => keep == null || !keep(key) || !_usable(value),
    );
    _failures.clear();
    _timer?.cancel();
    _queue(() => store.clear());
    if (_entries.isNotEmpty) _schedulePersist();
    if (notify) _updates.add('*');
  }

  void lock({Object? error}) {
    _epoch++;
    _scope = null;
    _user = null;
    _denied = error;
    _entries.clear();
    _pending.clear();
    _failures.clear();
    _timer?.cancel();
    _queue(() => store.clear());
    _updates.add('*');
  }

  void _queue(Future<void> Function() action) {
    _disk = _disk.then((_) => action()).catchError((_) {});
  }

  void _schedulePersist() {
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 300), () {
      if (!_authorized) return;
      _trim();
      final payload = jsonEncode({
        'scope': _scope,
        'items': _entries.map((k, v) => MapEntry(k, v.toJson())),
      });
      _queue(() => store.write(payload));
    });
  }

  Future<void> dispose() async {
    _epoch++;
    _scope = null;
    _pending.clear();
    _timer?.cancel();
    await _disk;
    await _updates.close();
  }
}
