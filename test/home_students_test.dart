import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/coaching/cubit/coach_classes_cubit.dart';
import 'package:eden_booking/modules/coaching/models/coach_class.dart';
import 'package:eden_booking/modules/coaching/widgets/today_students_section.dart';
import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/modules/dashboard/screens/home_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/refreshable_reads.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'booking_module_test.dart' show BookingSource;
import 'coach_classes_test.dart' show FakeClasses, batch, student;

class HomeClasses extends FakeClasses implements RetainedReadEvents {
  final events = StreamController<void>.broadcast();
  final requests = <String>[];
  Completer<void>? marking;
  bool failLoad = false;
  @override
  Stream<void> get readChanges => events.stream;
  @override
  void revalidateReads() => events.add(null);
  @override
  Future<List<CoachClass>> classes(String date) async {
    requests.add(date);
    if (failLoad) throw const AppException('Could not reach the server.');
    return super.classes(date);
  }

  @override
  Future<void> mark(CoachStudent student, String attendance) async {
    await marking?.future;
    return super.mark(student, attendance);
  }
}

Future<(WorkspaceCubit, GoRouter)> pumpHome(
  WidgetTester tester,
  HomeClasses api, {
  Size size = const Size(390, 1000),
  double scale = 1,
  Brightness brightness = Brightness.light,
  GlobalKey? boundary,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final source = BookingSource();
  source.value = Workspace(
    organization: source.value.organization,
    businesses: source.value.businesses,
    membership: const {
      'role': 'staff',
      'permissions': ['coach', 'mark_attendance'],
    },
  );
  final workspace = WorkspaceCubit(source);
  await workspace.load();
  getIt.registerFactoryParam<HomeCubit, WorkspaceSession, void>(
    (session, _) => HomeCubit(SessionDashboardRepository(session)),
  );
  getIt.registerFactoryParam<CoachClassesCubit, WorkspaceSession, void>(
    (session, _) => CoachClassesCubit(
      api,
      session: session,
      now: () => DateTime(2030, 6, 4),
    ),
  );
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(
        path: '/coaching/classes',
        builder: (_, _) => const Scaffold(body: Text('All classes')),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(workspace.close);
  addTearDown(api.events.close);
  await tester.pumpWidget(
    BlocProvider.value(
      value: workspace,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp.router(
          theme: AppTheme.build(brightness).copyWith(
            textTheme: AppTheme.build(
              brightness,
            ).textTheme.apply(fontFamily: 'Roboto'),
            filledButtonTheme: FilledButtonThemeData(
              style: AppTheme.build(brightness).filledButtonTheme.style
                  ?.copyWith(
                    textStyle: const WidgetStatePropertyAll(
                      TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
            ),
          ),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: RepaintBoundary(key: boundary, child: child!),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (workspace, router);
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('HOME_STUDENT_PREVIEWS')) return;
    final fontDir = Platform.environment['REVIEW_FONT_DIR']!;
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File('$fontDir/${font.value}').readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  tearDown(() => getIt.reset());

  for (final (size, scale, brightness) in [
    (const Size(390, 1100), 1.0, Brightness.light),
    (const Size(1440, 1100), 1.0, Brightness.dark),
    (const Size(320, 900), 1.8, Brightness.light),
  ]) {
    testWidgets('Home marks today’s students at ${size.width}, text $scale', (
      tester,
    ) async {
      final api = HomeClasses()
        ..days['2030-06-04'] = [
          batch([
            student('1'),
            student('2'),
            student('read-only', markable: false),
          ]),
        ]
        ..days['2030-06-05'] = [
          batch([student('tomorrow')]),
        ];
      final boundary = GlobalKey();
      await pumpHome(
        tester,
        api,
        size: size,
        scale: scale,
        brightness: brightness,
        boundary: boundary,
      );
      expect(find.text('Today’s students'), findsOneWidget);
      expect(find.text('Student 1'), findsOneWidget);
      expect(find.text('Student tomorrow'), findsNothing);
      expect(find.text('5:00 PM – 6:00 PM'), findsNWidgets(3));
      expect(find.text('Beginner coaching'), findsNWidgets(3));
      expect(find.text('Pool A · Eden Swimming'), findsNWidgets(3));
      expect(find.byKey(const ValueKey('present-v-read-only')), findsNothing);
      if (scale == 1 && const bool.fromEnvironment('HOME_STUDENT_PREVIEWS')) {
        await tester.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()!
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File(
            '/tmp/home-students-${size.width.toInt()}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final present = find.byKey(const ValueKey('present-v-1'));
      await tester.ensureVisible(present);
      await tester.tap(present);
      await tester.pumpAndSettle();
      expect(api.marks, {'v-1': 'present'});
      expect(present, findsNothing);
      final absent = find.byKey(const ValueKey('absent-v-2'));
      await tester.ensureVisible(absent);
      await tester.tap(absent);
      await tester.pumpAndSettle();
      expect(api.marks, {'v-1': 'present', 'v-2': 'absent'});
      expect(find.text('3 scheduled · 1 present · 1 absent'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Home refresh, empty state, failed save and busy controls', (
    tester,
  ) async {
    final api = HomeClasses();
    final (workspace, router) = await pumpHome(tester, api);
    expect(find.text('No students scheduled today'), findsOneWidget);
    api.days['2030-06-04'] = [
      batch([student('1')]),
    ];
    api.failLoad = true;
    await tester.tap(find.byTooltip('Refresh today’s students'));
    await tester.pumpAndSettle();
    expect(find.text('Could not reach the server.'), findsOneWidget);
    api.failLoad = false;
    api.revalidateReads();
    await tester.pumpAndSettle();
    final mark = find.byKey(const ValueKey('present-v-1'));
    await tester.ensureVisible(mark);
    api.failOn = 'v-1';
    await tester.tap(mark);
    await tester.pumpAndSettle();
    expect(api.marks, isEmpty);
    expect(find.text('Attendance changed. Refresh and retry.'), findsOneWidget);
    api.failOn = null;
    api.revalidateReads();
    await tester.pumpAndSettle();
    api.marking = Completer<void>();
    await tester.ensureVisible(mark);
    await tester.tap(mark);
    await tester.pump();
    expect(tester.widget<FilledButton>(mark).onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.refresh))
          .onPressed,
      isNull,
    );
    expect(find.text('Saving attendance…'), findsOneWidget);
    api.marking!.complete();
    await tester.pumpAndSettle();
    expect(api.marks, {'v-1': 'present'});
    await tester.ensureVisible(find.text('My classes'));
    await tester.tap(find.text('My classes'));
    await tester.pumpAndSettle();
    expect(find.text('All classes'), findsOneWidget);
    api.days['2030-06-04'] = [];
    router.pop();
    await tester.pumpAndSettle();
    expect(find.text('No students scheduled today'), findsOneWidget);
    workspace.clear();
    await tester.pumpAndSettle();
    expect(find.byType(TodayStudentsSection), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'today roster rolls over before an old attendance mark can be sent',
    () async {
      var now = DateTime(2030, 6, 4, 23, 59);
      final api = HomeClasses()
        ..days['2030-06-04'] = [
          batch([student('old')]),
        ]
        ..days['2030-06-05'] = [
          batch([student('new')]),
        ];
      final cubit = CoachClassesCubit(api, now: () => now);
      await cubit.refreshToday(force: true);
      final old = cubit.state.classes.single.students.single;
      now = DateTime(2030, 6, 5);
      await cubit.mark(old, 'present');
      expect(api.marks, isEmpty);
      expect(cubit.state.date, '2030-06-05');
      expect(cubit.state.classes.single.students.single.name, 'Student new');
      final reads = api.requests.length;
      await cubit.refreshToday();
      expect(api.requests.length, reads);
      await cubit.close();
      api.revalidateReads();
      await Future<void>.delayed(Duration.zero);
      expect(api.requests.length, reads);
      await api.events.close();
    },
  );
}
