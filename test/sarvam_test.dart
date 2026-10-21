import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/sarvam/cubit/sarvam_cubits.dart';
import 'package:eden_booking/modules/sarvam/models/sarvam_models.dart';
import 'package:eden_booking/modules/sarvam/repositories/sarvam_repository.dart';
import 'package:eden_booking/modules/sarvam/screens/call_logs_screen.dart';
import 'package:eden_booking/modules/sarvam/screens/sarvam_settings_screen.dart';
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
    toolKeyPrefix: 'bkv_abcdef',
    toolBaseUrl: 'https://x.supabase.co/functions/v1/booking-api/voice/v1',
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
  int rotations = 0;
  @override
  Future<SarvamSettings> settings() async => value;
  @override
  Future<SarvamSettings> save({
    required int version,
    required bool enabled,
    required Set<String> businessIds,
    required String orgId,
    required String workspaceId,
    required String appId,
    String? apiKey,
  }) async {
    if (failure != null) throw failure!;
    saves.add({
      'version': version,
      'enabled': enabled,
      'business_ids': businessIds,
      'org': orgId,
      'api_key': apiKey,
    });
    return value = SarvamSettings(
      version: version + 1,
      enabled: enabled,
      connected: value.connected || apiKey != null,
      apiKeyLast4: apiKey?.substring(apiKey.length - 4) ?? value.apiKeyLast4,
      orgId: orgId,
      workspaceId: workspaceId,
      appId: appId,
      toolKeyPrefix: value.toolKeyPrefix,
      toolBaseUrl: value.toolBaseUrl,
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
  Future<String> rotateToolKey() async {
    rotations++;
    return 'bkv_new_key_$rotations';
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

  test('settings keep the saved key unless a new one is typed', () async {
    final repo = TestSarvam();
    final cubit = SarvamSettingsCubit(await workspace(), repo);
    await cubit.load();
    expect(cubit.state.dirty, isFalse);
    cubit.toggleBusiness('business', true);
    cubit.update(enabled: true);
    await cubit.save();
    expect(repo.saves.single['api_key'], isNull);
    expect(repo.saves.single['version'], 2);
    expect(repo.saves.single['business_ids'], {'business'});
    expect(cubit.state.notice, 'Sarvam settings saved.');
    expect(cubit.state.dirty, isFalse);
    cubit.update(apiKey: ' sk_new_5678 ');
    await cubit.save();
    expect(repo.saves.last['api_key'], 'sk_new_5678');
    expect(cubit.state.saved.apiKeyLast4, '5678');
    await cubit.close();
  });

  test('settings validate before saving and surface server errors', () async {
    final repo = TestSarvam();
    final cubit = SarvamSettingsCubit(await workspace(), repo);
    await cubit.load();
    cubit.update(enabled: true);
    await cubit.save();
    expect(cubit.state.error, contains('at least one business'));
    cubit.update(enabled: false, appId: '');
    await cubit.save();
    expect(cubit.state.error, contains('together'));
    cubit.update(appId: 'bad id!');
    await cubit.save();
    expect(cubit.state.error, contains('letters, numbers'));
    expect(repo.saves, isEmpty);
    cubit.update(appId: 'Edens-Sport', orgId: 'org-2');
    repo.failure = AppException(
      'Sarvam settings changed elsewhere.',
      code: 'CONFLICT',
    );
    await cubit.save();
    expect(cubit.state.error, 'Sarvam settings changed elsewhere.');
    expect(cubit.state.orgId, 'org-2');
    await cubit.close();
  });

  test('generating a key keeps unsaved edits and shows the key once', () async {
    final repo = TestSarvam();
    final cubit = SarvamSettingsCubit(await workspace(), repo);
    await cubit.load();
    cubit.update(orgId: 'org-9');
    await cubit.rotateToolKey();
    expect(cubit.state.newToolKey, 'bkv_new_key_1');
    expect(cubit.state.orgId, 'org-9');
    cubit.update(appId: 'x');
    expect(cubit.state.newToolKey, isNull);
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
    'settings screen fits a narrow phone and shows the tool key once',
    (tester) async {
      final repo = TestSarvam();
      await pump(tester, const SarvamSettingsScreen(), repo, TestSaver());
      expect(tester.takeException(), isNull);
      expect(find.text('Connect Sarvam'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Replace'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Replace'));
      await tester.pumpAndSettle();
      expect(find.text('Replace the voice tool key?'), findsOneWidget);
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(find.text('bkv_new_key_1'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.text('bkv_new_key_1'), findsNothing);
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
