import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/coaching/cubit/coach_classes_cubit.dart';
import 'package:eden_booking/modules/coaching/models/coach_class.dart';
import 'package:eden_booking/modules/coaching/repositories/coach_api.dart';
import 'package:eden_booking/modules/coaching/screens/coach_classes_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'booking_module_test.dart' show BookingSource;
import 'coach_classes_test.dart' show batch;
import 'home_students_test.dart'
    show HomeClasses, pumpHome, loadHomeStudentPreviewFonts;
import 'cached_transport_test.dart' show TestAdapter, TestAuth;

FlexibleCoachStudent flexible(
  String id, {
  String action = 'start',
  int version = 1,
}) => FlexibleCoachStudent(
  admissionId: id,
  version: version,
  name: 'Flexible $id',
  planName: 'Beginner coaching',
  businessName: 'Eden Swimming',
  spaceName: 'Pool A',
  today: '2030-06-04',
  remaining: 5,
  durationMinutes: 60,
  action: action,
  localStart: '2030-06-04T12:10',
  localEnd: '2030-06-04T13:10',
  localMarkedAt: action == 'present' ? '2030-06-04T12:10' : null,
  reason: action == 'unavailable' ? 'Attendance permission is required.' : null,
);

class FlexibleClasses extends HomeClasses {
  final flex = <String, FlexibleCoachStudent>{
    'one': flexible('one'),
    'two': flexible('two'),
  };
  final calls = <(String, String, bool)>[];
  final saved = <String, FlexibleAttendanceResult>{};
  Completer<void>? gate;
  bool loseResponse = false, conflict = false;

  @override
  Future<CoachRoster> classes(String date) async {
    final roster = await super.classes(date);
    return CoachRoster(
      classes: roster.classes,
      flexibleStudents: date == '2030-06-04' ? flex.values : [],
    );
  }

  @override
  Future<FlexibleAttendanceResult> checkIn(
    FlexibleCoachStudent student, {
    required String commandKey,
    required bool startClass,
  }) async {
    calls.add((student.admissionId, commandKey, startClass));
    await gate?.future;
    if (conflict) {
      throw const AppException(
        'This coaching class is full.',
        code: 'CONFLICT',
      );
    }
    if (saved.containsKey(commandKey)) return saved[commandKey]!;
    final result = FlexibleAttendanceResult(
      started: startClass,
      localMarkedAt: '2030-06-04T12:10',
      localStart: '2030-06-04T12:10',
      localEnd: '2030-06-04T13:10',
    );
    saved[commandKey] = result;
    flex[student.admissionId] = flexible(
      student.admissionId,
      action: 'present',
      version: 2,
    );
    for (final id in flex.keys.toList()) {
      if (flex[id]!.action == 'start') flex[id] = flexible(id, action: 'join');
    }
    // The server also returns the created session: it must not render twice.
    days['2030-06-04'] = [
      batch([
        CoachStudent(
          admissionId: student.admissionId,
          visitId: 'visit-${student.admissionId}',
          version: 1,
          name: student.name,
          attendance: 'present',
          markable: false,
        ),
      ]),
    ];
    if (loseResponse) {
      loseResponse = false;
      throw const AppException('Response lost.', code: 'NETWORK');
    }
    return result;
  }
}

void main() {
  setUpAll(loadHomeStudentPreviewFonts);
  tearDown(() => getIt.reset());
  test(
    'coach transport reads unscheduled enrolments and sends a replayable command without a client clock',
    () async {
      final auth = TestAuth(), adapter = TestAdapter();
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      final api = RestApiService(auth, dio: dio);
      // Share one transport so both the roster and its write use the same contract.
      final source = RestCoachApi(api);
      void reply(Map<String, dynamic> data) {
        adapter.pending = Completer<ResponseBody>()
          ..complete(
            ResponseBody.fromString(
              jsonEncode(data),
              200,
              headers: {
                'content-type': ['application/json'],
              },
            ),
          );
      }

      reply({
        'classes': [],
        'flexible_students': [
          {
            'admission_id': 'one',
            'version': 3,
            'name': 'Flexible one',
            'plan_name': 'Coaching',
            'business_name': 'Academy',
            'space_name': 'Pool A',
            'today': '2030-06-04',
            'remaining': 4,
            'duration_minutes': 60,
            'action': 'start',
          },
        ],
      });
      final roster = await source.classes('2030-06-04');
      expect(roster.classes, isEmpty);
      expect(roster.flexibleStudents.single.canMark, true);
      reply({'class_started': true, 'local_marked_at': '2030-06-04T12:10'});
      final saved = await source.checkIn(
        roster.flexibleStudents.single,
        commandKey: 'same-command',
        startClass: true,
      );
      expect(saved.localMarkedAt, '2030-06-04T12:10');
      final body = adapter.lastOptions!.data;
      expect(body is String ? jsonDecode(body) : body, {
        'command_key': 'same-command',
        'version': 3,
        'start_class': true,
      });
      expect(adapter.lastOptions!.path, '/admissions/one/check-ins');
      await api.dispose();
      await auth.events.close();
    },
  );
  for (final size in [
    const Size(320, 1000),
    const Size(390, 1100),
    const Size(1440, 1100),
  ]) {
    testWidgets('flexible Home students start and join at ${size.width}', (
      tester,
    ) async {
      final api = FlexibleClasses();
      final boundary = GlobalKey();
      await pumpHome(
        tester,
        api,
        size: size,
        scale: size.width == 320 ? 1.6 : 1,
        boundary: boundary,
      );
      expect(find.text('Flexible students'), findsOneWidget);
      expect(find.text('No students scheduled today'), findsNothing);
      final first = find.byKey(const ValueKey('flexible-present-one'));
      await tester.ensureVisible(first);
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('HOME_STUDENT_PREVIEWS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/flexible-home-${size.width.toInt()}.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      api.gate = Completer<void>();
      await tester.tap(first);
      await tester.pump();
      expect(tester.widget<FilledButton>(first).onPressed, isNull);
      expect(find.text('Saving attendance…'), findsOneWidget);
      api.gate!.complete();
      await tester.pumpAndSettle();
      expect(api.calls.single.$3, true);
      expect(
        find.text('Flexible one'),
        findsOneWidget,
        reason: 'created visit is not a duplicate tile',
      );
      expect(find.text('Present at 12:10 PM'), findsOneWidget);
      expect(find.text('Class 12:10 PM – 1:10 PM'), findsNWidgets(2));
      final second = find.byKey(const ValueKey('flexible-present-two'));
      expect(find.text('Mark present'), findsOneWidget);
      await tester.ensureVisible(second);
      await tester.tap(second);
      await tester.pumpAndSettle();
      expect(api.calls.last.$3, false);
      expect(find.text('Present at 12:10 PM'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'My classes shows flexible students without reserved visits and hides them on another date',
    (tester) async {
      final api = FlexibleClasses();
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      getIt.registerFactoryParam<CoachClassesCubit, WorkspaceSession, void>(
        (session, _) => CoachClassesCubit(
          api,
          session: session,
          now: () => DateTime(2030, 6, 4),
        ),
      );
      await tester.pumpWidget(
        ScreenUtilInit(
          designSize: const Size(390, 844),
          builder: (_, _) => MaterialApp(
            theme: darkTheme(),
            home: BlocProvider.value(
              value: workspace,
              child: const CoachClassesScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Flexible one'), findsOneWidget);
      expect(find.text('No classes on this day'), findsNothing);
      final mark = find.byKey(const ValueKey('flexible-present-one'));
      await tester.ensureVisible(mark);
      await tester.tap(mark);
      await tester.pumpAndSettle();
      expect(find.text('Present at 12:10 PM'), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('Next day'));
      await tester.tap(find.byTooltip('Next day'));
      await tester.pumpAndSettle();
      expect(find.text('Flexible one'), findsNothing);
      expect(find.text('No classes on this day'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await workspace.close();
      await api.events.close();
    },
  );

  test(
    'lost flexible response retries the exact key, version and start intent',
    () async {
      final api = FlexibleClasses()..loseResponse = true;
      final cubit = CoachClassesCubit(api, now: () => DateTime(2030, 6, 4));
      await cubit.refreshToday(force: true);
      final student = cubit.state.flexibleStudents.first;
      await cubit.checkIn(student);
      expect(cubit.state.pendingCheckIn, true);
      expect(cubit.state.error, 'Response lost.');
      await cubit.checkIn(cubit.state.flexibleStudents.last);
      await cubit.show(DateTime(2030, 6, 5));
      expect(api.calls, hasLength(1));
      expect(cubit.state.date, '2030-06-04');
      await cubit.retryCheckIn();
      expect(api.calls[0], api.calls[1]);
      expect(api.saved, hasLength(1));
      expect(cubit.state.pendingCheckIn, false);
      expect(cubit.state.flexibleStudents.first.present, true);
      expect(
        cubit.state.notice,
        contains('marked present at 2030-06-04 12:10'),
      );
      await cubit.close();
      await api.events.close();
    },
  );

  test(
    'read-only flexible students cannot mark; full class reloads without creating attendance',
    () async {
      final api = FlexibleClasses();
      api.flex['one'] = flexible('one', action: 'unavailable');
      final cubit = CoachClassesCubit(api, now: () => DateTime(2030, 6, 4));
      await cubit.refreshToday(force: true);
      await cubit.checkIn(cubit.state.flexibleStudents.first);
      expect(api.calls, isEmpty);
      api.conflict = true;
      await cubit.checkIn(cubit.state.flexibleStudents.last);
      expect(cubit.state.error, 'This coaching class is full.');
      expect(cubit.state.pendingCheckIn, false);
      expect(api.saved, isEmpty);
      await cubit.close();
      await api.events.close();
    },
  );
}
