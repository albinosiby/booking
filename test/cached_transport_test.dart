import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/auth/repositories/auth_repository_interface.dart';
import 'package:eden_booking/modules/bookings/models/booking_models.dart';
import 'package:eden_booking/modules/bookings/repositories/rest_booking_repository.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:eden_booking/utils/services/retained_read_cache.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'repository_cache_test.dart' show MemorySnapshotStore;

class TestAuth extends Fake implements AuthRepository {
  AppUser? user = const AppUser(
    id: 'owner',
    email: 'owner@example.com',
    name: 'Owner',
    verified: true,
  );
  final events = StreamController<AppUser?>.broadcast();
  @override
  AppUser? get currentUser => user;
  @override
  Stream<AppUser?> get changes => events.stream;
  @override
  Future<String?> token({bool refresh = false}) async => 'test-token';
}

class TestAdapter implements HttpClientAdapter {
  final requests = <String>[];
  int status = 200;
  Completer<ResponseBody>? pending;
  Completer<void>? started;
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add('${options.method} ${options.path}');
    if (started != null && !started!.isCompleted) started!.complete();
    final gate = pending;
    pending = null;
    return gate?.future ??
        ResponseBody.fromString(
          jsonEncode({'value': requests.length, 'slots': [], 'id': 'saved'}),
          status,
          headers: {
            'content-type': ['application/json'],
            'cache-control': ['private, no-store'],
          },
        );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late TestAuth auth;
  late TestAdapter adapter;
  late RestApiService api;
  setUp(() async {
    auth = TestAuth();
    adapter = TestAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
      ..httpClientAdapter = adapter;
    api = RestApiService(
      auth,
      dio: dio,
      readCache: RetainedReadCache(
        store: MemorySnapshotStore(),
        identity: () => auth.currentUser?.id,
      ),
    );
    await api.authorizeReads({
      'organization': {'id': 'org'},
      'membership': {'role': 'owner'},
      'businesses': [],
    });
  });
  tearDown(() async {
    await api.dispose();
    await auth.events.close();
  });

  test(
    'concurrent identical GETs share transport but not mutable results',
    () async {
      final gate = Completer<ResponseBody>();
      adapter.pending = gate;
      adapter.started = Completer<void>();
      final first = api.request('/workspace');
      final second = api.request('/workspace');
      await adapter.started!.future;
      expect(adapter.requests, ['GET /workspace']);
      gate.complete(
        ResponseBody.fromString(
          '{"items":[1]}',
          200,
          headers: {
            'content-type': ['application/json'],
            'cache-control': ['no-store'],
          },
        ),
      );
      final values = await Future.wait([first, second]);
      (values[0]['items'] as List).add(2);
      expect(values[1]['items'], [1]);
      await api.request('/workspace');
      expect(adapter.requests, hasLength(2));
    },
  );

  test(
    'a write prevents a new GET from joining an older in-flight read',
    () async {
      final gate = Completer<ResponseBody>();
      adapter.pending = gate;
      adapter.started = Completer<void>();
      final before = api.request('/workspace');
      await adapter.started!.future;
      await api.request('/bookings', method: 'POST', data: {'command': 'save'});
      await api.request('/workspace');
      expect(
        adapter.requests.where((r) => r == 'GET /workspace'),
        hasLength(2),
      );
      gate.complete(
        ResponseBody.fromString(
          '{"value":"old"}',
          200,
          headers: {
            'content-type': ['application/json'],
            'cache-control': ['no-store'],
          },
        ),
      );
      await before;
    },
  );

  test(
    'HTTP no-store remains respected independently of app read snapshots',
    () async {
      await api.request('/private');
      await api.request('/private');
      expect(adapter.requests, hasLength(2));
      final first = await api.retainedRead('/bookings');
      expect(await api.retainedRead('/bookings'), first);
      expect(adapter.requests, hasLength(3));
    },
  );
  test(
    'a successful write invalidates read snapshots across features',
    () async {
      await api.retainedRead('/accounts/catalog');
      await api.retainedRead('/bookings');
      await api.request(
        '/accounts/entries',
        method: 'POST',
        data: {'amount': 500},
      );
      await api.retainedRead('/accounts/catalog');
      await api.retainedRead('/bookings');
      expect(
        adapter.requests.where((r) => r == 'GET /accounts/catalog'),
        hasLength(2),
      );
      expect(adapter.requests.where((r) => r == 'GET /bookings'), hasLength(2));
    },
  );
  test(
    'availability is always fetched and does not evict cached page data',
    () async {
      final repository = RestBookingRepository(api);
      await api.retainedRead('/bookings');
      const selection = BookingSelection(
        businessId: 'business',
        resourceId: 'space',
        optionId: 'court',
        date: '2030-06-04',
        time: '09:00',
        duration: 60,
        people: 1,
      );
      await repository.availability(selection);
      await repository.availability(selection);
      await api.retainedRead('/bookings');
      expect(
        adapter.requests.where((r) => r == 'POST /bookings/availability'),
        hasLength(2),
      );
      expect(adapter.requests.where((r) => r == 'GET /bookings'), hasLength(1));
    },
  );
  test('logout clears cached responses before another account reads', () async {
    final old = await api.retainedRead('/accounts/catalog');
    auth.user = null;
    auth.events.add(null);
    await Future<void>.delayed(Duration.zero);
    auth.user = const AppUser(
      id: 'other',
      email: 'other@example.com',
      name: 'Other',
      verified: true,
    );
    auth.events.add(auth.user);
    await Future<void>.delayed(Duration.zero);
    await api.authorizeReads({
      'organization': {'id': 'other-org'},
      'membership': {'role': 'owner'},
      'businesses': [],
    });
    expect(await api.retainedRead('/accounts/catalog'), isNot(old));
    expect(adapter.requests, hasLength(2));
  });
  test(
    'auth stream errors are handled without losing a retained page',
    () async {
      final retained = await api.retainedRead('/bookings');
      auth.events.addError(
        const AppException('Token refresh interrupted', code: 'NETWORK'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await api.retainedRead('/bookings'), retained);
    },
  );
  test('403 cannot turn into a cached-data success', () async {
    await api.retainedRead('/accounts/catalog');
    adapter.status = 403;
    await expectLater(
      api.request('/permission-check'),
      throwsA(predicate((e) => e != null && accessFailure(e))),
    );
    await expectLater(
      api.retainedRead('/accounts/catalog'),
      throwsA(predicate((e) => e != null && accessFailure(e))),
    );
    expect(adapter.requests, hasLength(2));
  });
  test(
    'a late denial from the old account cannot lock the new account cache',
    () async {
      final gate = Completer<ResponseBody>();
      adapter.pending = gate;
      final pending = api.request('/old-account-only');
      await Future<void>.delayed(Duration.zero);
      auth.user = const AppUser(
        id: 'other',
        email: 'other@example.com',
        name: 'Other',
        verified: true,
      );
      auth.events.add(auth.user);
      await Future<void>.delayed(Duration.zero);
      await api.authorizeReads({
        'organization': {'id': 'new-org'},
        'membership': {'role': 'owner'},
        'businesses': [],
      });
      final cached = await api.retainedRead('/accounts/catalog');
      gate.complete(
        ResponseBody.fromString(
          '{"code":"FORBIDDEN","message":"Removed"}',
          403,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      await expectLater(pending, throwsA(isA<AppException>()));
      expect(await api.retainedRead('/accounts/catalog'), cached);
    },
  );
  test(
    'responses from an old account cannot authorize a new workspace',
    () async {
      final gate = Completer<ResponseBody>();
      adapter.pending = gate;
      final pending = api.request('/workspace');
      await Future<void>.delayed(Duration.zero);
      auth.user = const AppUser(
        id: 'other',
        email: 'other@example.com',
        name: 'Other',
        verified: true,
      );
      gate.complete(
        ResponseBody.fromString(
          '{}',
          200,
          headers: {
            'content-type': ['application/json'],
          },
        ),
      );
      await expectLater(pending, throwsA(isA<AppException>()));
    },
  );
}
