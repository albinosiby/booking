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
import 'package:eden_booking/modules/agent_calls/screens/agent_service_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource;

class TestAgentCalls implements AgentCallRepository {
  AgentServiceStatus value = const AgentServiceStatus();
  final requests = <String>[];
  AppException? failure;
  @override
  Future<AgentServiceStatus> status() async => value;
  @override
  Future<AgentServiceStatus> request(String note) async {
    if (failure != null) throw failure!;
    requests.add(note);
    return value = const AgentServiceStatus(status: 'requested');
  }

  @override
  Future<AgentServiceStatus> setEnabled(bool enabled) async => value =
      AgentServiceStatus(status: 'active', ready: true, enabled: enabled);
  @override
  Future<AgentCallPage> calls(DateTime start, DateTime end) async =>
      AgentCallPage.fromJson({
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
      ..value = const AgentServiceStatus(status: 'active', ready: true);
    final cubit = AgentServiceCubit(await workspace(), repo);
    await cubit.load();
    await cubit.setEnabled(true);
    expect(cubit.state.status.enabled, isTrue);
    repo.failure = const AppException('Not allowed.');
    await cubit.request('x');
    expect(cubit.state.error, 'Not allowed.');
    await cubit.close();
  });

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
    TestSaver saver,
  ) async {
    final w = await workspace();
    registerFeatureDependencies(getIt);
    await getIt.unregister<AgentCallRepository>();
    getIt.registerSingleton<AgentCallRepository>(repo);
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

  testWidgets('request screen shows the request form without provider names', (
    tester,
  ) async {
    final repo = TestAgentCalls();
    await pump(tester, const AgentServiceScreen(), repo, TestSaver());
    expect(tester.takeException(), isNull);
    expect(find.text('Request service'), findsOneWidget);
    expect(find.textContaining('Sarvam'), findsNothing);
    await tester.tap(find.text('Request service'));
    await tester.pumpAndSettle();
    expect(repo.requests, hasLength(1));
    expect(find.text('Under review'), findsOneWidget);
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
