import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'booking_module_test.dart' show BookingSource;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/coaching/cubit/coach_classes_cubit.dart';
import 'package:eden_booking/modules/coaching/models/coach_class.dart';
import 'package:eden_booking/modules/coaching/repositories/coach_api.dart';
import 'package:eden_booking/modules/coaching/screens/coach_classes_screen.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';

CoachStudent student(String id, {bool markable = true}) => CoachStudent(
  admissionId: 'a-$id',
  visitId: 'v-$id',
  version: 1,
  name: 'Student $id',
  attendance: 'unmarked',
  markable: markable,
);

/// Classes keyed by date; marks change the attendance of a visit.
class FakeClasses extends Fake implements CoachApi {
  final days = <String, List<CoachClass>>{};
  final marks = <String, String>{};
  String? failOn;
  @override
  Future<CoachRoster> classes(String date) async => CoachRoster(
    classes: [
      for (final c in days[date] ?? const <CoachClass>[])
        CoachClass(
          key: c.key,
          businessName: c.businessName,
          planName: c.planName,
          spaceName: c.spaceName,
          localStart: c.localStart,
          localEnd: c.localEnd,
          students: [
            for (final s in c.students)
              marks.containsKey(s.visitId)
                  ? CoachStudent(
                      admissionId: s.admissionId,
                      visitId: s.visitId,
                      version: s.version + 1,
                      name: s.name,
                      attendance: marks[s.visitId]!,
                      markable: false,
                    )
                  : s,
          ],
        ),
    ],
  );
  @override
  Future<void> mark(CoachStudent student, String attendance) async {
    if (student.visitId == failOn) {
      throw const AppException('Attendance changed. Refresh and retry.');
    }
    marks[student.visitId] = attendance;
  }
}

CoachClass batch(Iterable<CoachStudent> students) => CoachClass(
  key: 'k',
  businessName: 'Eden Swimming',
  planName: 'Beginner coaching',
  spaceName: 'Pool A',
  localStart: '2030-06-04T17:00',
  localEnd: '2030-06-04T18:00',
  students: students,
);

void main() {
  tearDown(() => getIt.reset());
  test('My classes loads a day and marks students', () async {
    final api = FakeClasses()
      ..days['2030-06-04'] = [
        batch([student('1'), student('2'), student('3', markable: false)]),
      ];
    final c = CoachClassesCubit(api, today: DateTime(2030, 6, 4));
    addTearDown(c.close);
    await c.load();
    expect(c.state.classes.single.students, hasLength(3));
    await c.mark(c.state.classes.single.students.first, 'absent');
    expect(api.marks, {'v-1': 'absent'});
    await c.markAll(c.state.classes.single);
    expect(api.marks, {'v-1': 'absent', 'v-2': 'present'});
    expect(c.state.classes.single.count('present'), 1);
    await c.show(DateTime(2030, 6, 5));
    expect(c.state.date, '2030-06-05');
    expect(c.state.classes, isEmpty);
  });

  test('A failed mark stops the batch and shows the error', () async {
    final api = FakeClasses()
      ..days['2030-06-04'] = [
        batch([student('1'), student('2'), student('3')]),
      ]
      ..failOn = 'v-2';
    final c = CoachClassesCubit(api, today: DateTime(2030, 6, 4));
    addTearDown(c.close);
    await c.load();
    await c.markAll(c.state.classes.single);
    expect(api.marks, {'v-1': 'present'});
    expect(c.state.error, contains('Attendance changed'));
    expect(c.state.busy, isFalse);
  });

  testWidgets('My classes shows a roster and marks all present at 320px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeClasses()
      ..days['2030-06-04'] = [
        batch([student('1'), student('2')]),
      ];
    getIt.registerFactoryParam<CoachClassesCubit, WorkspaceSession, void>(
      (session, _) =>
          CoachClassesCubit(api, session: session, today: DateTime(2030, 6, 4)),
    );
    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (_, _) => MaterialApp(
          theme: AppTheme.build(Brightness.light),
          home: BlocProvider(
            create: (_) => WorkspaceCubit(BookingSource()),
            child: const CoachClassesScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Beginner coaching'), findsOneWidget);
    expect(find.text('17:00–18:00 · Pool A · Eden Swimming'), findsOneWidget);
    expect(find.text('Student 1'), findsOneWidget);
    await tester.ensureVisible(find.text('Mark 2 present'));
    await tester.tap(find.text('Mark 2 present'));
    await tester.pumpAndSettle();
    expect(api.marks, {'v-1': 'present', 'v-2': 'present'});
    expect(find.text('Present'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Next day'));
    await tester.pumpAndSettle();
    expect(find.text('No classes on this day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
