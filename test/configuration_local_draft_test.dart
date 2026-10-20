import 'package:eden_booking/modules/pool/models/pool_configuration.dart';
import 'package:eden_booking/modules/hall/models/hall_configuration.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/modules/configuration_drafts/models/configuration_draft.dart';
import 'package:eden_booking/modules/configuration_drafts/repositories/configuration_draft_repository.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/turf/cubit/turf_setup_cubit.dart';
import 'package:eden_booking/modules/court/cubit/court_setup_cubit.dart';
import 'package:eden_booking/modules/pool/cubit/pool_setup_cubit.dart';
import 'package:eden_booking/modules/hall/cubit/hall_setup_cubit.dart';
import 'turf_setup_test.dart' as turf;
import 'court_setup_test.dart' as court;
import 'pool_setup_test.dart' as pool;
import 'hall_setup_test.dart' as hall;

class DraftStore implements ConfigurationDraftRepository {
  final records = <String, ConfigurationDraft>{};
  bool failWrites = false, failReads = false;
  Completer<void>? gate;
  int writes = 0;
  @override
  Future<ConfigurationDraft?> read(String key) async {
    if (failReads) throw StateError('Storage unavailable');
    return records[key];
  }

  @override
  Future<void> write(String key, ConfigurationDraft draft) async {
    writes++;
    await gate?.future;
    if (failWrites) throw StateError('Disk unavailable');
    records[key] = ConfigurationDraft.fromJson(
      Map<String, dynamic>.from(jsonDecode(jsonEncode(draft.toJson()))),
    );
  }

  @override
  Future<void> remove(String key) async {
    records.remove(key);
  }
}

class ScopedWorkspace extends Fake implements WorkspaceRepository {
  ScopedWorkspace(this.source, {this.owner = 'owner'});
  final WorkspaceRepository source;
  final String owner;
  @override
  Future<Workspace> load() async {
    final s = await source.load();
    return Workspace(
      organization: s.organization,
      membership: {...s.membership!, 'id': owner},
      businesses: s.businesses,
      locations: s.locations,
    );
  }
}

class Scenario {
  Scenario(this.kind, this.source, this.remote, this.session, this.cubit);
  final String kind;
  final dynamic source, remote, cubit;
  final WorkspaceCubit session;
  Future<void> close() async {
    await cubit.close();
    await session.close();
  }
}

Future<Scenario> scenario(
  String kind,
  DraftStore store, {
  dynamic existingSource,
  String owner = 'owner',
}) async {
  final dynamic source =
      existingSource ??
      switch (kind) {
        'turf' => turf.TurfSource(),
        'court' => court.CourtSource(),
        'pool' => pool.PoolSource(),
        _ => hall.HallSource(),
      };
  final session = WorkspaceCubit(
    ScopedWorkspace(source as WorkspaceRepository, owner: owner),
  );
  await session.load();
  final dynamic remote = switch (kind) {
    'turf' => turf.FakeTurfRepository(source as turf.TurfSource),
    'court' => court.FakeCourtRepository(source as court.CourtSource),
    'pool' => pool.FakePoolRepository(source as pool.PoolSource),
    _ => hall.FakeHallRepository(source as hall.HallSource),
  };
  final dynamic cubit = switch (kind) {
    'turf' => TurfSetupCubit(session, remote, 'turf', drafts: store),
    'court' => CourtSetupCubit(session, remote, 'courts', drafts: store),
    'pool' => PoolSetupCubit(session, remote, 'swimming', drafts: store),
    _ => HallSetupCubit(session, remote, 'halls', drafts: store),
  };
  await pumpEventQueue();
  return Scenario(kind, source, remote, session, cubit);
}

void editIncomplete(Scenario s) {
  final dynamic c = s.cubit;
  switch (s.kind) {
    case 'turf':
      c.groundName(c.state.draft.grounds.first.id, 'My draft');
      c.price(c.state.draft.offerings.first.id, 60, '12.');
    case 'court':
      c.addCourt();
      c.addTariff(c.state.selectedId);
      final p = c.state.selectedCourt;
      c.tariffPrice(p.id, p.tariffs.first.id, 60, '12.');
    case 'pool':
      c.addPool();
      final id = c.state.selectedId;
      c.updatePool(
        id,
        (PoolResource p) =>
            p.copyWith(capacity: '', minDepth: '3.', maxDepth: ''),
      );
      c.addTariff(id);
      final p = c.state.selectedPool;
      c.tariffPrice(p.id, p.tariffs.first.id, 60, '12.');
    case 'hall':
      c.addHall();
      final id = c.state.selectedId;
      c.updateHall(
        id,
        (HallResource p) => p.copyWith(capacity: '', seated: ''),
      );
      c.addTariff(id);
      final p = c.state.selectedHall;
      c.tariffPrice(p.id, p.tariffs.first.id, 60, '12.');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final kind in ['turf', 'court', 'pool', 'hall']) {
    test(
      '$kind: local draft restores exact incomplete inputs, navigation and version without cloud writes',
      () async {
        final store = DraftStore();
        final first = await scenario(kind, store);
        editIncomplete(first);
        final expected = jsonEncode(first.cubit.captureLocalDraft().toJson());
        await first.close();
        expect(store.records.length, 1);
        expect(first.remote.writes, 0);
        final restored = await scenario(
          kind,
          store,
          existingSource: first.source,
        );
        expect(
          jsonEncode(restored.cubit.captureLocalDraft().toJson()),
          expected,
        );
        expect(restored.cubit.state.localDraftStatus, LocalDraftStatus.saved);
        expect(restored.cubit.state.dirty, true);
        expect(restored.remote.writes, 0);
        await restored.close();
      },
    );
    test(
      '$kind: a newer cloud version blocks final save while keeping the local draft',
      () async {
        final store = DraftStore();
        final first = await scenario(kind, store);
        editIncomplete(first);
        await first.close();
        first.source.version++;
        final restored = await scenario(
          kind,
          store,
          existingSource: first.source,
        );
        expect(
          restored.cubit.state.localDraftStatus,
          LocalDraftStatus.conflict,
        );
        final bool ok = kind == 'turf'
            ? await restored.cubit.saveProgress()
            : await restored.cubit.saveChanges();
        expect(ok, false);
        expect(restored.remote.writes, 0);
        expect(store.records.length, 1);
        await restored.close();
      },
    );
  }
  test(
    'turf Continue advances before local storage finishes and never calls the cloud',
    () async {
      final store = DraftStore();
      final s = await scenario('turf', store);
      store.gate = Completer<void>();
      expect(await s.cubit.continueSetup(), true);
      expect(s.cubit.state.step, 1);
      expect(s.cubit.state.saving, false);
      expect(s.remote.writes, 0);
      store.gate!.complete();
      await s.cubit.flushLocalDraft();
      expect(store.records.length, 1);
      await s.close();
    },
  );
  test(
    'failed local writes show a retry and the latest data stays editable',
    () async {
      final store = DraftStore()..failWrites = true;
      final s = await scenario('turf', store);
      editIncomplete(s);
      await s.cubit.flushLocalDraft();
      expect(s.cubit.state.localDraftStatus, LocalDraftStatus.failed);
      expect(s.cubit.state.disabled, false);
      store.failWrites = false;
      await s.cubit.retryLocalDraft();
      expect(store.records.length, 1);
      expect(s.cubit.state.localDraftStatus, LocalDraftStatus.saved);
      await s.close();
    },
  );
  test('drafts cannot restore under a different owner membership', () async {
    final store = DraftStore();
    final first = await scenario('turf', store);
    editIncomplete(first);
    await first.close();
    final other = await scenario(
      'turf',
      store,
      existingSource: first.source,
      owner: 'another-owner',
    );
    expect(other.cubit.state.dirty, false);
    expect(other.cubit.state.draft.grounds.first.name, isNot('My draft'));
    await other.close();
  });
  test(
    'successful final save clears local draft; failed cloud save keeps it',
    () async {
      final store = DraftStore();
      final s = await scenario('turf', store);
      s.cubit.groundName(s.cubit.state.draft.grounds.first.id, 'Saved ground');
      expect(await s.cubit.saveProgress(), true);
      expect(s.remote.writes, 1);
      expect(store.records, isEmpty);
      s.cubit.groundName(s.cubit.state.draft.grounds.first.id, 'Kept ground');
      s.source.version++;
      expect(await s.cubit.saveProgress(), false);
      expect(store.records.length, 1);
      expect(s.cubit.state.dirty, true);
      await s.close();
    },
  );
  test(
    'local restore failures can retry without replacing a stored draft',
    () async {
      final store = DraftStore();
      final first = await scenario('turf', store);
      editIncomplete(first);
      await first.close();
      store.failReads = true;
      final s = await scenario('turf', store, existingSource: first.source);
      expect(s.cubit.state.localDraftStatus, LocalDraftStatus.loadFailed);
      expect(s.cubit.state.disabled, true);
      store.failReads = false;
      await s.cubit.retryLocalDraft();
      expect(s.cubit.state.draft.grounds.first.name, 'My draft');
      await s.close();
    },
  );
}
