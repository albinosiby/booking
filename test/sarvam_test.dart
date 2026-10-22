import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/agent_calls/cubit/agent_call_cubits.dart';
import 'package:eden_booking/modules/agent_calls/models/agent_call_models.dart';
import 'package:eden_booking/modules/agent_calls/repositories/agent_call_repository.dart';
import 'package:eden_booking/modules/agent_calls/screens/call_logs_screen.dart';
import 'package:eden_booking/modules/agent_calls/screens/sarvam_settings_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource;

class TestSarvam implements SarvamRepository {
  SarvamSettings value = const SarvamSettings(
    version: 2,
    connected: true,
    apiKeyLast4: '1234',
    orgId: 'org-1',
    workspaceId: 'ws-1',
    appId: 'Edens-Sport',
    hasCredentials: true,
    callLogsAvailable: true,
    status: 'configured',
    draftVersion: 7,
    publishedVersion: 6,
    deployments: [SarvamDeployment(id: 'deployment', name: 'Edens Sports')],
    businesses: [
      SarvamBusiness(
        id: 'business',
        name: 'Badminton',
        ready: true,
        assigned: false,
      ),
    ],
  );
  final saves = <Map<String, Object?>>[];
  AppException? failure;
  int connects = 0, disconnects = 0, publishes = 0, authorizations = 0;
  Completer<void>? pendingConnect;
  final steps = <SarvamSettings>[];
  AppException? stepFailure;
  @override
  Future<SarvamSettings> settings() async => value;
  SarvamSettings changed({
    String? status,
    bool? enabled,
    bool? credentials,
    int? publishedVersion,
  }) => SarvamSettings(
    version: value.version + 1,
    enabled: enabled ?? value.enabled,
    connected: (status ?? value.status) == 'configured',
    hasCredentials: credentials ?? value.hasCredentials,
    apiKeyLast4: value.apiKeyLast4,
    orgId: value.orgId,
    workspaceId: value.workspaceId,
    appId: value.appId,
    status: status ?? value.status,
    draftVersion: value.draftVersion,
    publishedVersion: publishedVersion ?? value.publishedVersion,
    deployments: value.deployments,
    businesses: value.businesses,
  );
  @override
  Future<SarvamSettings> connect({
    required int version,
    required Set<String> businessIds,
    required String orgId,
    required String workspaceId,
    required String appId,
    String? apiKey,
  }) async {
    connects++;
    saves.add({
      'version': version,
      'business_ids': businessIds,
      'org': orgId,
      'api_key': apiKey,
    });
    await pendingConnect?.future;
    if (failure != null) throw failure!;
    return value = SarvamSettings(
      version: version + 1,
      connected: false,
      hasCredentials: true,
      callLogsAvailable: true,
      enabled: value.enabled,
      status: 'connecting',
      apiKeyLast4: apiKey?.substring(apiKey.length - 4) ?? value.apiKeyLast4,
      orgId: orgId,
      workspaceId: workspaceId,
      appId: appId,
      draftVersion: 7,
      publishedVersion: value.publishedVersion,
      deployments: value.deployments,
      businesses: [
        for (final b in value.businesses)
          SarvamBusiness(
            id: b.id,
            name: b.name,
            ready: b.ready,
            assigned: businessIds.contains(b.id),
          ),
      ],
    );
  }

  @override
  Future<SarvamSettings> setupStep() async {
    if (stepFailure != null) throw stepFailure!;
    return value = steps.isEmpty
        ? changed(status: 'configured')
        : steps.removeAt(0);
  }

  @override
  Future<SarvamSettings> disconnect() async {
    disconnects++;
    return value = changed(
      status: 'disconnected',
      enabled: false,
      credentials: false,
    );
  }

  @override
  Future<SarvamSettings> setBookingEnabled(int version, bool enabled) async =>
      value = changed(enabled: enabled);
  @override
  Future<SarvamSettings> publish(int version, String deploymentId) async {
    publishes++;
    return value = changed(publishedVersion: value.draftVersion);
  }

  @override
  Future<bool> openAuthorization(String url) async {
    authorizations++;
    return true;
  }

  @override
  Future<int> test() async => 3;
  @override
  Future<SarvamCallPage> calls(DateTime start, DateTime end) async =>
      SarvamCallPage.fromJson({
        'total': 1,
        'items': [
          {
            'interaction_id': '20260920/a71c352f-11:03:08-e6013eb8',
            'started_at': '2026-09-20 05:33:08',
            'duration_seconds': 137.6,
            'language': 'Malayalam',
            'direction': 'inbound',
            'contact': '+919847012345',
            'caller_name': 'Ebin',
            'summary': 'Caller booked Court 1 for 8 PM tomorrow.',
            'disposition': 'request_captured',
          },
        ],
      });
  @override
  Future<List<TranscriptLine>> transcript(String interactionId) async => const [
    TranscriptLine(agent: true, text: 'Hi, this is Eden Sports.'),
    TranscriptLine(agent: false, text: 'Book a court for 8 PM.'),
  ];
  @override
  Future<List<int>> recording(String interactionId) async => [1, 2, 3];
}

class TestSaver implements RecordingSaver {
  final names = <String>[];
  @override
  Future<bool> save(List<int> bytes, String filename) async {
    names.add(filename);
    return true;
  }
}

Future<WorkspaceCubit> workspace({bool owner = true}) async {
  final source = BookingSource();
  if (!owner) {
    source.value = Workspace(
      organization: source.value.organization,
      membership: const {
        'role': 'staff',
        'permissions': ['view_bookings'],
      },
      businesses: source.value.businesses,
    );
  }
  final w = WorkspaceCubit(source);
  await w.load();
  return w;
}

void main() {
  tearDown(() => getIt.reset());

  test('parses Sarvam UTC timestamps without a zone suffix', () {
    final call = SarvamCall.fromJson({
      'interaction_id': 'x',
      'started_at': '2026-09-20 05:33:08',
      'duration_seconds': 137.58,
    });
    expect(call.startedAt, DateTime.utc(2026, 9, 20, 5, 33, 8).toLocal());
    expect(call.duration, '2:18');
    expect(call.title, 'Unknown caller');
  });

  test(
    'Connect keeps server credentials, configures automatically and never publishes',
    () async {
      final repo = TestSarvam();
      final cubit = SarvamSettingsCubit(await workspace(), repo);
      await cubit.load();
      cubit.toggleBusiness('business', true);
      await cubit.connect();
      expect(repo.saves.single['api_key'], isNull);
      expect(repo.saves.single['version'], 2);
      expect(repo.saves.single['business_ids'], {'business'});
      expect(cubit.state.saved.connected, isTrue);
      expect(cubit.state.saved.awaitingPublish, isTrue);
      expect(repo.publishes, 0);
      expect(cubit.state.dirty, isFalse);
      cubit.update(apiKey: ' sk_new_5678 ');
      await cubit.connect();
      expect(repo.saves.last['api_key'], 'sk_new_5678');
      expect(cubit.state.apiKey, isEmpty);
      await cubit.close();
    },
  );

  test('validates input and reports durable setup failures', () async {
    final repo = TestSarvam();
    final cubit = SarvamSettingsCubit(await workspace(), repo);
    await cubit.load();
    await cubit.connect();
    expect(cubit.state.error, contains('at least one business'));
    cubit.update(appId: 'bad id!');
    await cubit.connect();
    expect(cubit.state.error, contains('IDs'));
    expect(repo.saves, isEmpty);
    cubit.update(appId: 'Edens-Sport');
    cubit.toggleBusiness('business', true);
    repo.stepFailure = const AppException('Setup interrupted. Retry.');
    await cubit.connect();
    expect(cubit.state.error, 'Setup interrupted. Retry.');
    expect(cubit.state.busy, isFalse);
    repo.stepFailure = null;
    await cubit.continueSetup();
    expect(cubit.state.saved.connected, isTrue);
    expect(repo.connects, 1);
    await cubit.close();
  });

  test(
    'Disconnect supersedes pending Connect and prevents a late response restoring it',
    () async {
      final repo = TestSarvam()..pendingConnect = Completer<void>();
      final cubit = SarvamSettingsCubit(await workspace(), repo);
      await cubit.load();
      cubit.toggleBusiness('business', true);
      final pending = cubit.connect();
      await cubit.connect();
      expect(repo.connects, 1);
      await cubit.disconnect();
      expect(cubit.state.saved.status, 'disconnected');
      repo.pendingConnect!.complete();
      await pending;
      expect(cubit.state.saved.status, 'disconnected');
      expect(cubit.state.saved.enabled, isFalse);
      await cubit.close();
    },
  );

  test('booking switch saves immediately and Publish is explicit', () async {
    final repo = TestSarvam();
    final cubit = SarvamSettingsCubit(await workspace(), repo);
    await cubit.load();
    await cubit.setBookingEnabled(true);
    expect(cubit.state.saved.enabled, isTrue);
    expect(repo.connects, 0);
    await cubit.setBookingEnabled(false);
    expect(cubit.state.saved.enabled, isFalse);
    await cubit.publish('deployment');
    expect(repo.publishes, 1);
    expect(cubit.state.saved.awaitingPublish, isFalse);
    await cubit.close();
  });

  test('non-owners cannot load Sarvam settings or calls', () async {
    final repo = TestSarvam();
    final w = await workspace(owner: false);
    final settings = SarvamSettingsCubit(w, repo);
    await settings.load();
    expect(settings.state.error, contains('Only the owner'));
    final calls = CallLogsCubit(w, repo);
    await calls.load();
    expect(calls.state.page.items, isEmpty);
    expect(calls.state.error, contains('Only the owner'));
    await settings.close();
    await calls.close();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget screen,
    TestSarvam repo,
    TestSaver saver,
  ) async {
    final w = await workspace();
    registerFeatureDependencies(getIt);
    await getIt.unregister<SarvamRepository>();
    getIt.registerSingleton<SarvamRepository>(repo);
    await getIt.unregister<RecordingSaver>();
    getIt.registerSingleton<RecordingSaver>(saver);
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (c, s) => screen)],
    );
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider.value(
        value: w,
        child: ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (c, _) => MaterialApp.router(
            theme: lightTheme(),
            routerConfig: router,
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'settings fit a narrow phone with booking controls and no key popup',
    (tester) async {
      final repo = TestSarvam();
      await pump(tester, const SarvamSettingsScreen(), repo, TestSaver());
      expect(tester.takeException(), isNull);
      expect(find.text('Connect Sarvam'), findsOneWidget);
      expect(find.text('Generate'), findsNothing);
      expect(find.text('Replace'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Accept phone bookings'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(repo.value.enabled, isTrue);
      await tester.scrollUntilVisible(
        find.text('Disconnect Sarvam'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Disconnect Sarvam'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(repo.disconnects, 1);
      expect(repo.value.enabled, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('call logs list calls and open the transcript', (tester) async {
    final repo = TestSarvam(), saver = TestSaver();
    await pump(tester, const CallLogsScreen(), repo, saver);
    expect(tester.takeException(), isNull);
    expect(find.text('Ebin'), findsOneWidget);
    expect(find.textContaining('Court 1 for 8 PM'), findsOneWidget);
    await tester.tap(find.byType(AppCard).first);
    await tester.pumpAndSettle();
    final sheet = find.byType(Scrollable).last;
    await tester.tap(find.text('Save recording'));
    await tester.pumpAndSettle();
    expect(saver.names.single, 'call-20260920-a71c352f-11-03-08-e6013eb8.wav');
    expect(find.text('Recording saved.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Book a court for 8 PM.'),
      200,
      scrollable: sheet,
    );
    expect(find.text('Hi, this is Eden Sports.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
