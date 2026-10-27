import 'dart:async';
import 'dart:convert';
import 'package:eden_booking/modules/agent_calls/cubit/agent_call_cubits.dart';
import 'package:eden_booking/modules/agent_calls/models/agent_call_models.dart';
import 'package:eden_booking/modules/agent_calls/repositories/agent_call_repository.dart';
import 'package:eden_booking/modules/businesses/cubit/business_management_cubit.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/configuration_drafts/models/configuration_draft.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/retained_read_cache.dart';
import 'package:flutter_test/flutter_test.dart';

class _Workspace extends Fake implements WorkspaceRepository {
  @override
  Future<Workspace> load() async => const Workspace(
    organization: Organization(
      id: 'o',
      name: 'Eden',
      phone: '9876543210',
      currency: 'INR',
    ),
    membership: {'id': 'me', 'role': 'owner'},
    businesses: [
      Business(
        id: 'b',
        name: 'Turf',
        type: BusinessType.turf,
        status: 'ready',
        locationId: 'l',
        version: 1,
        resources: [],
      ),
    ],
  );
}

class _Biz extends Fake implements BusinessRepository {
  final renames = <(String, String)>[];
  @override
  Future<void> rename(String id, String name) async => renames.add((id, name));
}

class _Calls extends Fake implements AgentCallRepository {
  final notes = <String>[];
  @override
  Future<AgentServiceStatus> status() async => const AgentServiceStatus();
  @override
  Future<AgentServiceStatus> request(
    String note,
    List<CallService> services,
  ) async {
    notes.add(note);
    return const AgentServiceStatus(status: 'requested');
  }
}

class _Store implements ReadSnapshotStore {
  String? value;
  bool failRead = false;
  @override
  Future<String?> read() async {
    if (failRead) throw StateError('corrupt');
    return value;
  }

  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> clear() async => value = null;
}

void main() {
  group('business rename field', () {
    Future<(BusinessManagementCubit, _Biz)> make() async {
      final w = WorkspaceCubit(_Workspace());
      await w.load();
      final repo = _Biz();
      final c = BusinessManagementCubit(w, repo);
      addTearDown(c.close);
      addTearDown(w.close);
      return (c, repo);
    }

    test(
      'empty, whitespace and one character are rejected with a message',
      () async {
        final (c, repo) = await make();
        for (final v in ['', '   ', 'A', ' A ']) {
          expect(await c.rename('b', v), isFalse, reason: v);
          expect(c.state.message, 'Enter at least two characters');
        }
        expect(repo.renames, isEmpty);
      },
    );

    test('121 characters are rejected, 120 accepted and trimmed', () async {
      final (c, repo) = await make();
      expect(await c.rename('b', 'a' * 121), isFalse);
      expect(await c.rename('b', '  ${'a' * 120}  '), isTrue);
      expect(repo.renames.single.$2, 'a' * 120);
    });

    test('unicode and emoji names are kept', () async {
      final (c, repo) = await make();
      expect(await c.rename('b', 'ഏബിൻ Turf 🏸'), isTrue);
      expect(repo.renames.single.$2, 'ഏബിൻ Turf 🏸');
    });
  });

  group('agent call request note', () {
    test(
      'no service selected shows an error and does not call the backend',
      () async {
        final w = WorkspaceCubit(_Workspace());
        await w.load();
        final repo = _Calls();
        final c = AgentServiceCubit(w, repo);
        addTearDown(c.close);
        addTearDown(w.close);
        c.selectService(CallService.booking, false);
        await c.request('hello');
        expect(c.state.error, 'Choose at least one service.');
        expect(repo.notes, isEmpty);
      },
    );

    test('double request while busy is sent once', () async {
      final w = WorkspaceCubit(_Workspace());
      await w.load();
      final repo = _Calls();
      final c = AgentServiceCubit(w, repo);
      addTearDown(c.close);
      addTearDown(w.close);
      c.selectService(CallService.booking, true);
      final a = c.request('x');
      final b = c.request('x');
      await Future.wait([a, b]);
      expect(repo.notes, hasLength(1));
    });
  });

  group('configuration draft json', () {
    test('round trip and unsupported schema', () {
      const d = ConfigurationDraft(
        baseVersion: 3,
        configuration: {'name': '😀 ഏബിൻ', 'price': 10.5},
        navigation: {'step': 1},
      );
      final back = ConfigurationDraft.fromJson(
        Map<String, dynamic>.from(jsonDecode(jsonEncode(d.toJson())) as Map),
      );
      expect(back, d);
      expect(
        () => ConfigurationDraft.fromJson({'schema': 2}),
        throwsFormatException,
      );
    });

    test('missing or malformed fields throw rather than silently loading', () {
      expect(
        () => ConfigurationDraft.fromJson({'schema': 1}),
        throwsA(anything),
      );
      expect(
        () => ConfigurationDraft.fromJson({
          'schema': 1,
          'base_version': 'x',
          'configuration': {},
          'navigation': {},
        }),
        throwsA(anything),
      );
    });
  });

  group('RetainedReadCache', () {
    RetainedReadCache make(
      _Store store, {
      String? user = 'u',
      DateTime Function()? now,
    }) => RetainedReadCache(store: store, identity: () => user, now: now);

    test('unauthorized reads go straight to the network', () async {
      final cache = make(_Store());
      var calls = 0;
      final v = await cache.read(
        'k',
        () async => ++calls,
        freshFor: const Duration(minutes: 1),
        retainFor: const Duration(hours: 1),
      );
      expect(v, 1);
      await cache.read(
        'k',
        () async => ++calls,
        freshFor: const Duration(minutes: 1),
        retainFor: const Duration(hours: 1),
      );
      expect(calls, 2);
      await cache.dispose();
    });

    test(
      'authorised cache serves retained data and survives corrupt storage',
      () async {
        final store = _Store()..failRead = true;
        final cache = make(store);
        await cache.authorize('scope');
        var calls = 0;
        Future<dynamic> fetch() async => {'n': ++calls, 'name': '😀'};
        final a = await cache.read(
          'k',
          fetch,
          freshFor: const Duration(hours: 1),
          retainFor: const Duration(hours: 2),
        );
        final b = await cache.read(
          'k',
          fetch,
          freshFor: const Duration(hours: 1),
          retainFor: const Duration(hours: 2),
        );
        expect(a, b);
        expect(calls, 1);
        await cache.dispose();
      },
    );

    test('malformed stored json is ignored', () async {
      final store = _Store()..value = '{not json';
      final cache = make(store);
      await cache.authorize('scope');
      expect(
        await cache.read(
          'k',
          () async => 5,
          freshFor: Duration.zero,
          retainFor: const Duration(hours: 1),
        ),
        5,
      );
      await cache.dispose();
    });

    test(
      'a scope change drops entries and access failure locks the cache',
      () async {
        final cache = make(_Store());
        await cache.authorize('a');
        await cache.read(
          'k',
          () async => 1,
          freshFor: const Duration(hours: 1),
          retainFor: const Duration(hours: 1),
        );
        await cache.authorize('b');
        expect(
          await cache.read(
            'k',
            () async => 2,
            freshFor: const Duration(hours: 1),
            retainFor: const Duration(hours: 1),
          ),
          2,
        );
        await expectLater(
          cache.read(
            'x',
            () async => throw const AppException('no', code: 'FORBIDDEN'),
            freshFor: Duration.zero,
            retainFor: Duration.zero,
          ),
          throwsA(isA<AppException>()),
        );
        await expectLater(
          cache.read(
            'y',
            () async => 1,
            freshFor: Duration.zero,
            retainFor: Duration.zero,
          ),
          throwsA(isA<AppException>()),
        );
        await cache.dispose();
      },
    );

    test('concurrent reads of one key share a single request', () async {
      final cache = make(_Store());
      await cache.authorize('a');
      final gate = Completer<int>();
      var calls = 0;
      Future<dynamic> fetch() {
        calls++;
        return gate.future;
      }

      final a = cache.read(
        'k',
        fetch,
        freshFor: Duration.zero,
        retainFor: const Duration(hours: 1),
      );
      final b = cache.read(
        'k',
        fetch,
        freshFor: Duration.zero,
        retainFor: const Duration(hours: 1),
      );
      gate.complete(7);
      expect(await Future.wait([a, b]), [7, 7]);
      expect(calls, 1);
      await cache.dispose();
    });

    test('expired snapshots are not served', () async {
      var t = DateTime(2026, 1, 1);
      final cache = make(_Store(), now: () => t);
      await cache.authorize('a');
      var calls = 0;
      Future<dynamic> fetch() async => ++calls;
      await cache.read(
        'k',
        fetch,
        freshFor: const Duration(minutes: 1),
        retainFor: const Duration(minutes: 5),
      );
      t = t.add(const Duration(minutes: 10));
      expect(
        await cache.read(
          'k',
          fetch,
          freshFor: const Duration(minutes: 1),
          retainFor: const Duration(minutes: 5),
        ),
        2,
      );
      await cache.dispose();
    });
  });
}
