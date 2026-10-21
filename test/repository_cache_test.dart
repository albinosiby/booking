import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/utils/services/retained_read_cache.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

class MemorySnapshotStore implements ReadSnapshotStore {
  String? value;
  final written = Completer<void>();
  final cleared = Completer<void>();
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    value = data;
    if (!written.isCompleted) written.complete();
  }

  @override
  Future<void> clear() async {
    value = null;
    if (!cleared.isCompleted) cleared.complete();
  }
}

void main() {
  late MemorySnapshotStore store;
  late RetainedReadCache cache;
  late DateTime now;
  String? user;
  Future<dynamic> read(String key, Future<dynamic> Function() fetch) =>
      cache.read(
        key,
        fetch,
        freshFor: const Duration(seconds: 20),
        retainFor: const Duration(minutes: 15),
      );
  setUp(() async {
    user = 'owner';
    now = DateTime(2026, 10, 16, 10);
    store = MemorySnapshotStore();
    cache = RetainedReadCache(
      store: store,
      identity: () => user,
      now: () => now,
      maxEntries: 3,
    );
    await cache.authorize('backend/owner/org/access-v1');
  });
  tearDown(() => cache.dispose());

  test(
    'deduplicates identical reads and returns isolated JSON snapshots',
    () async {
      final gate = Completer<dynamic>();
      var calls = 0;
      Future<dynamic> fetch() {
        calls++;
        return gate.future;
      }

      final first = read('/bookings?date=16', fetch);
      final second = read('/bookings?date=16', fetch);
      gate.complete({
        'items': [1],
      });
      await Future.wait([first, second]);
      expect(calls, 1);
      final hit = await read('/bookings?date=16', fetch) as Map;
      (hit['items'] as List).add(99);
      expect(await read('/bookings?date=16', fetch), {
        'items': [1],
      });
    },
  );

  test(
    'stale reads return immediately and notify after background refresh',
    () async {
      await read('/accounts', () async => {'total': 500});
      now = now.add(const Duration(seconds: 21));
      final gate = Completer<dynamic>();
      final update = cache.updates.first;
      expect(await read('/accounts', () => gate.future), {'total': 500});
      gate.complete({'total': 700});
      expect(await update, '/accounts');
      expect(await read('/accounts', () async => fail('fresh hit')), {
        'total': 700,
      });
    },
  );

  test(
    'unchanged background response refreshes freshness without rebuilding subscribers',
    () async {
      await read(
        '/same',
        () async => {
          'items': [1],
        },
      );
      final events = <String>[];
      final listener = cache.updates.listen(events.add);
      now = now.add(const Duration(seconds: 21));
      await read(
        '/same',
        () async => {
          'items': [1],
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      expect(await read('/same', () async => fail('must be fresh')), {
        'items': [1],
      });
      await listener.cancel();
    },
  );

  test(
    'expired reads wait for the server rather than showing old balances',
    () async {
      await read('/accounts', () async => 500);
      now = now.add(const Duration(minutes: 16));
      final gate = Completer<dynamic>();
      var completed = false;
      final pending = read('/accounts', () => gate.future).then((v) {
        completed = true;
        return v;
      });
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      gate.complete(900);
      expect(await pending, 900);
    },
  );

  test('date, filters and pagination use separate keys', () async {
    expect(await read('/bookings?date=16&cursor=0', () async => 1), 1);
    expect(await read('/bookings?date=17&cursor=0', () async => 2), 2);
    expect(await read('/bookings?date=16&cursor=20', () async => 3), 3);
    expect(await read('/bookings?date=16&cursor=0', () async => 99), 1);
  });

  test(
    'mutation invalidation prevents an older in-flight result being installed',
    () async {
      final gate = Completer<dynamic>();
      final pending = read('/bookings', () => gate.future);
      final rejected = expectLater(pending, throwsA(isA<AppException>()));
      cache.invalidate();
      gate.complete('old');
      await rejected;
      expect(await read('/bookings', () async => 'new'), 'new');
    },
  );

  test('an account switch rejects an in-flight read', () async {
    final gate = Completer<dynamic>();
    final pending = read('/accounts', () => gate.future);
    final rejected = expectLater(pending, throwsA(isA<AppException>()));
    user = 'other';
    gate.complete('private old account');
    await rejected;
    await cache.authorize('backend/other/org/access-v1');
    expect(
      await read('/accounts', () async => 'other account'),
      'other account',
    );
  });

  test(
    'encrypted-store snapshots restore only for the same authorized scope',
    () async {
      await read('/accounts', () async => {'amount': 500});
      await store.written.future;
      expect(store.value, isNotNull);
      final next = RetainedReadCache(
        store: store,
        identity: () => user,
        now: () => now,
      );
      await next.authorize('backend/owner/org/access-v1');
      expect(
        await next.read(
          '/accounts',
          () async => fail('should restore'),
          freshFor: const Duration(seconds: 20),
          retainFor: const Duration(minutes: 15),
        ),
        {'amount': 500},
      );
      await next.authorize('backend/owner/another-org/access-v1');
      expect(
        await next.read(
          '/accounts',
          () async => 'new org',
          freshFor: const Duration(seconds: 20),
          retainFor: const Duration(minutes: 15),
        ),
        'new org',
      );
      await next.dispose();
    },
  );

  test(
    'logout purges saved data and cannot restore it on next login',
    () async {
      await read('/accounts', () async => 'private');
      await store.written.future;
      user = null;
      cache.lock();
      await store.cleared.future;
      expect(store.value, isNull);
      user = 'owner';
      await cache.authorize('backend/owner/org/access-v1');
      expect(await read('/accounts', () async => 'fresh'), 'fresh');
    },
  );

  test(
    'a failed refresh keeps retained content visible and retries after cooldown',
    () async {
      await read('/accounts', () async => 500);
      now = now.add(const Duration(seconds: 21));
      final updated = cache.updates.first;
      expect(
        await read(
          '/accounts',
          () async => throw const AppException('Offline', code: 'NETWORK'),
        ),
        500,
      );
      await updated;
      expect(
        await read('/accounts', () async => fail('cooldown must not retry')),
        500,
      );
      now = now.add(const Duration(seconds: 11));
      final recovered = cache.updates.first;
      expect(await read('/accounts', () async => 900), 500);
      await recovered;
      expect(await read('/accounts', () async => fail('fresh hit')), 900);
    },
  );

  test(
    'successful recovery clears refresh errors even when the data did not change',
    () async {
      await read('/recover', () async => 500);
      now = now.add(const Duration(seconds: 21));
      final failed = cache.updates.first;
      await read(
        '/recover',
        () async => throw const AppException('Offline', code: 'NETWORK'),
      );
      await failed;
      now = now.add(const Duration(seconds: 11));
      final recovered = cache.updates.first;
      await read('/recover', () async => 500);
      expect(await recovered, '/recover');
    },
  );

  test('refresh cooldown cannot extend expired snapshot retention', () async {
    Future<dynamic> shortRead(Future<dynamic> Function() fetch) => cache.read(
      '/short',
      fetch,
      freshFor: const Duration(seconds: 1),
      retainFor: const Duration(seconds: 5),
    );
    await shortRead(() async => 500);
    now = now.add(const Duration(seconds: 2));
    final updated = cache.updates.first;
    expect(
      await shortRead(
        () async => throw const AppException('Offline', code: 'NETWORK'),
      ),
      500,
    );
    await updated;
    now = now.add(const Duration(seconds: 4));
    await expectLater(
      shortRead(() async => fail('still cooling down')),
      throwsA(isA<AppException>()),
    );
  });

  test(
    'authorization failure purges snapshots rather than using stale fallback',
    () async {
      await read('/accounts', () async => 'private');
      now = now.add(const Duration(seconds: 21));
      final updated = cache.updates.first;
      await read(
        '/accounts',
        () async => throw const AppException('Removed', code: 'FORBIDDEN'),
      );
      await updated;
      await expectLater(
        read('/accounts', () async => 'must not return'),
        throwsA(predicate((e) => e != null && accessFailure(e))),
      );
      await store.cleared.future;
      expect(store.value, isNull);
    },
  );

  test('LRU eviction bounds the number of snapshots', () async {
    for (var i = 0; i < 3; i++) {
      await read('/$i', () async => i);
    }
    await read('/0', () async => 999);
    await read('/3', () async => 3);
    expect(await read('/1', () async => 100), 100);
  });

  test(
    'anonymous reads are never installed in a user snapshot cache',
    () async {
      user = null;
      cache.lock();
      await cache.authorize('signed-out');
      var calls = 0;
      await read('/catalog', () async => ++calls);
      await read('/catalog', () async => ++calls);
      expect(calls, 2);
    },
  );
  test('corrupt stored snapshots do not block server reads', () async {
    store.value = 'not valid JSON';
    await cache.authorize('changed scope');
    expect(await read('/accounts', () async => 'fresh'), 'fresh');
  });
}
