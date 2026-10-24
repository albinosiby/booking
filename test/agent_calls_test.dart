import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:eden_booking/modules/agent_calls/screens/agent_service_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource;

class TestAgentCalls implements AgentCallRepository {
  AgentServiceStatus value = const AgentServiceStatus();
  final requests = <String>[];
  List<CallService> requestedServices = [];
  AppException? failure;
  @override
  Future<AgentServiceStatus> status() async => value;
  @override
  Future<AgentServiceStatus> request(
    String note,
    List<CallService> services,
  ) async {
    if (failure != null) throw failure!;
    requests.add(note);
    requestedServices = services;
    return value = const AgentServiceStatus(status: 'requested');
  }

  @override
  Future<AgentServiceStatus> setEnabled(bool enabled, int version) async =>
      value = AgentServiceStatus(
        status: 'active',
        ready: true,
        enabled: enabled,
        phoneNumber: value.phoneNumber,
        spaces: value.spaces,
        approvedServices: value.approvedServices,
        callLogsAvailable: true,
        version: 2,
      );
  @override
  Future<AgentServiceStatus> setSpaces(List<String> ids, int version) async =>
      value = AgentServiceStatus(
        status: 'active',
        ready: true,
        enabled: value.enabled && ids.isNotEmpty,
        phoneNumber: value.phoneNumber,
        approvedServices: value.approvedServices,
        spaces: [
          for (final s in value.spaces)
            CallSpace(
              id: s.id,
              name: s.name,
              businessId: s.businessId,
              businessName: s.businessName,
              ready: s.ready,
              enabled: ids.contains(s.id),
            ),
        ],
        callLogsAvailable: true,
        version: version + 1,
      );
  @override
  Future<AgentCallPage> calls(
    DateTime start,
    DateTime end, {
    int offset = 0,
  }) async => AgentCallPage.fromJson({
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

  test('parses UTC timestamps without a zone suffix', () {
    final call = AgentCall.fromJson({
      'interaction_id': 'x',
      'started_at': '2026-09-20 05:33:08',
      'duration_seconds': 137.58,
    });
    expect(call.startedAt, DateTime.utc(2026, 9, 20, 5, 33, 8).toLocal());
    expect(call.duration, '2:18');
    expect(call.title, 'Unknown caller');
  });

  test('owner requests the service and sees progress', () async {
    final repo = TestAgentCalls();
    final cubit = AgentServiceCubit(await workspace(), repo);
    await cubit.load();
    expect(cubit.state.status.status, 'none');
    await cubit.request('Please set up');
    expect(repo.requests, ['Please set up']);
    expect(cubit.state.status.status, 'requested');
    expect(cubit.state.status.ready, isFalse);
    await cubit.close();
  });

  test('toggle works only once active and reports failures', () async {
    final repo = TestAgentCalls()
      ..value = const AgentServiceStatus(
        status: 'active',
        ready: true,
        phoneNumber: '+919876543210',
        callLogsAvailable: true,
        approvedServices: [CallService.booking],
        spaces: [
          CallSpace(
            id: 'court1',
            name: 'Court 1',
            businessId: 'arena',
            businessName: 'Arena',
            ready: true,
            enabled: true,
          ),
        ],
        version: 1,
      );
    final cubit = AgentServiceCubit(await workspace(), repo);
    await cubit.load();
    await cubit.setEnabled(true);
    expect(cubit.state.status.enabled, isTrue);
    repo.failure = const AppException('Not allowed.');
    await cubit.request('x');
    expect(cubit.state.error, 'Not allowed.');
    await cubit.close();
  });

  test(
    'service selection requires at least one and submits the chosen services',
    () async {
      final repo = TestAgentCalls();
      final c = AgentServiceCubit(await workspace(), repo);
      c.selectService(CallService.booking, false);
      await c.request('');
      expect(c.state.error, contains('at least one'));
      expect(repo.requests, isEmpty);
      c.selectService(CallService.enquiry, true);
      c.selectService(CallService.cancellation, true);
      await c.request('Support');
      expect(repo.requestedServices, [
        CallService.enquiry,
        CallService.cancellation,
      ]);
      await c.close();
    },
  );

  test('staff cannot manage the service', () async {
    final cubit = AgentServiceCubit(
      await workspace(owner: false),
      TestAgentCalls(),
    );
    await cubit.load();
    expect(cubit.state.error, contains('owner'));
    await cubit.close();
  });

  Future<void> pump(
    WidgetTester tester,
    Widget screen,
    TestAgentCalls repo,
    TestSaver saver, {
    double width = 320,
  }) async {
    final w = await workspace();
    registerFeatureDependencies(getIt);
    await getIt.unregister<AgentCallRepository>();
    getIt.registerSingleton<AgentCallRepository>(repo);
    await getIt.unregister<RecordingSaver>();
    getIt.registerSingleton<RecordingSaver>(saver);
    final router = GoRouter(
      routes: [GoRoute(path: '/', builder: (c, s) => screen)],
    );
    tester.view.physicalSize = Size(width, 900);
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

  testWidgets('request screen shows the request form without provider names', (
    tester,
  ) async {
    final repo = TestAgentCalls();
    await pump(tester, const AgentServiceScreen(), repo, TestSaver());
    expect(tester.takeException(), isNull);
    expect(find.text('Request service'), findsOneWidget);
    expect(find.textContaining('Sarvam'), findsNothing);
    await tester.ensureVisible(find.text('Request service'));
    await tester.tap(find.text('Request service'));
    await tester.pumpAndSettle();
    expect(repo.requests, hasLength(1));
    expect(find.text('Under review'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'connected client copies the number and deselecting the last space disables service',
    (tester) async {
      final repo = TestAgentCalls()
        ..value = const AgentServiceStatus(
          status: 'active',
          ready: true,
          enabled: true,
          version: 1,
          phoneNumber: '+919876543210',
          callLogsAvailable: true,
          approvedServices: [CallService.enquiry],
          spaces: [
            CallSpace(
              id: 'court1',
              name: 'Court 1',
              businessId: 'arena',
              businessName: 'Arena',
              ready: true,
              enabled: true,
            ),
          ],
        );
      await pump(tester, const AgentServiceScreen(), repo, TestSaver());
      expect(find.text('+919876543210'), findsOneWidget);
      expect(find.text('Activated services'), findsOneWidget);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.ensureVisible(find.text('Copy number'));
      await tester.tap(find.text('Copy number'));
      await tester.pumpAndSettle();
      expect(clipboard, '+919876543210');
      final space = find.byKey(const ValueKey('call-space-court1'));
      await tester.ensureVisible(space);
      await tester.tap(space);
      await tester.pumpAndSettle();
      expect(repo.value.spaces.single.enabled, isFalse);
      expect(repo.value.enabled, isFalse);
      final toggle = tester.widget<SwitchListTile>(
        find.byKey(const ValueKey('call-service-enabled')),
      );
      expect(toggle.onChanged, isNull);
      expect(find.textContaining('Sarvam'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('paused service still offers call logs', (tester) async {
    final repo = TestAgentCalls()
      ..value = const AgentServiceStatus(
        status: 'paused',
        callLogsAvailable: true,
      );
    await pump(tester, const AgentServiceScreen(), repo, TestSaver());
    expect(find.text('Call logs'), findsOneWidget);
    expect(find.byKey(const ValueKey('call-service-enabled')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('call logs list calls and open the transcript', (tester) async {
    final repo = TestAgentCalls(), saver = TestSaver();
    await pump(tester, const CallLogsScreen(), repo, saver);
    expect(tester.takeException(), isNull);
    expect(find.text('Ebin'), findsOneWidget);
    expect(find.textContaining('Court 1 for 8 PM'), findsOneWidget);
    await tester.tap(find.byType(AppCard).first);
    await tester.pumpAndSettle();
    final sheet = find.byType(Scrollable).last;
    await tester.ensureVisible(find.text('Save recording'));
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
  for (final width in [320.0, 1440.0]) {
    for (final status in [
      'requested',
      'in_review',
      'setting_up',
      'paused',
      'active',
    ]) {
      testWidgets('request status $status is readable at $width pixels', (
        tester,
      ) async {
        final repo = TestAgentCalls()
          ..value = AgentServiceStatus(
            status: status,
            message: 'We are preparing your venue’s call service.',
            requestedAt: DateTime(2026, 10, 20),
            updatedAt: DateTime(2026, 10, 22),
          );
        await pump(
          tester,
          const AgentServiceScreen(),
          repo,
          TestSaver(),
          width: width,
        );
        expect(find.text('Request status'), findsOneWidget);
        expect(find.text('Request received'), findsWidgets);
        expect(find.text('Under review'), findsWidgets);
        expect(find.textContaining('Requested '), findsOneWidget);
        expect(
          find.text('We are preparing your venue’s call service.'),
          findsOneWidget,
        );
        expect(find.byType(SwitchListTile), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
    testWidgets('ready call service toggles answering at $width pixels', (
      tester,
    ) async {
      final repo = TestAgentCalls()
        ..value = const AgentServiceStatus(
          status: 'active',
          ready: true,
          phoneNumber: '+919876543210',
          callLogsAvailable: true,
          approvedServices: [CallService.booking],
          spaces: [
            CallSpace(
              id: 'court1',
              name: 'Court 1',
              businessId: 'arena',
              businessName: 'Arena',
              ready: true,
              enabled: true,
            ),
          ],
          version: 1,
        );
      await pump(
        tester,
        const AgentServiceScreen(),
        repo,
        TestSaver(),
        width: width,
      );
      final toggle = find.byKey(const ValueKey('call-service-enabled'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(repo.value.enabled, isTrue);
      expect(find.text('Service enabled'), findsOneWidget);
      expect(find.text('Call logs'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'desktop calls select details and close without losing the list',
    (tester) async {
      final repo = TestAgentCalls();
      await pump(
        tester,
        const CallLogsScreen(),
        repo,
        TestSaver(),
        width: 1440,
      );
      expect(find.text('Select a call'), findsOneWidget);
      final row = find.byKey(
        const ValueKey('call-row-20260920/a71c352f-11:03:08-e6013eb8'),
      );
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.text('Call summary'), findsOneWidget);
      expect(find.text('Book a court for 8 PM.'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Close'));
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Select a call'), findsOneWidget);
      expect(row, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
