import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/admissions/cubit/admission_cubit.dart';
import 'package:eden_booking/modules/admissions/models/admission_models.dart';
import 'package:eden_booking/modules/admissions/repositories/rest_admission_repository.dart';
import 'package:eden_booking/modules/admissions/screens/admission_detail_screen.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'admissions_test.dart' show AdmissionsFake, example, workspace;
import 'booking_module_test.dart' show FakeBookingRepository;

class AttendanceFake extends AdmissionsFake {
  bool failRead = false, loseResponse = false;
  int reads = 0;
  Completer<void>? saving;
  final writes = <({String id, int version, String key})>[];
  final marks = <({String id, String attendance})>[];
  @override
  Future<Admission> detail(String id) {
    reads++;
    if (failRead) throw const AppException('Offline', code: 'NETWORK_ERROR');
    return super.detail(id);
  }

  @override
  Future<void> checkIn(Admission a, String key) async {
    writes.add((id: a.id, version: a.version, key: key));
    if (saving != null) await saving!.future;
    if (loseResponse) {
      throw const AppException('Connection lost', code: 'NETWORK_ERROR');
    }
  }

  @override
  Future<void> attendance(
    Admission a,
    AdmissionVisit v,
    String attendance,
    String reason,
    String key,
  ) async {
    marks.add((id: v.id, attendance: attendance));
  }
}

class AttendanceApi extends Fake implements RestApiService {
  Object? body;
  String? path;
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool readOnly = false,
  }) async {
    this.path = path;
    body = data;
    return {'id': 'admission'};
  }
}

void main() {
  tearDown(() => getIt.reset());

  test('automatic check-in sends no client date, time, or duration', () async {
    final api = AttendanceApi();
    final repository = RestAdmissionRepository(api, FakeBookingRepository());
    await repository.checkIn(example(), 'command');
    expect(api.path, '/admissions/admission/check-ins');
    expect(api.body, {'command_key': 'command', 'version': 1});
  });

  test(
    'check-in refreshes the version and uncertain retries retain the same command',
    () async {
      final session = await workspace(), repository = AttendanceFake();
      final c = AdmissionCubit(session, repository);
      await c.loadDetail('admission');
      repository.record = example(version: 7);
      repository.loseResponse = true;
      await c.checkIn();
      expect(repository.writes.single.version, 7);
      expect(c.state.locked, isTrue);
      final key = repository.writes.single.key;
      repository.record = example(version: 8);
      repository.loseResponse = false;
      await c.retry();
      expect(repository.writes.map((v) => v.version), [7, 7]);
      expect(repository.writes.map((v) => v.key), [key, key]);
      expect(c.state.locked, isFalse);
      await c.close();
      await session.close();
    },
  );

  test('failed refresh and a revoked session never write attendance', () async {
    final session = await workspace(), repository = AttendanceFake();
    final c = AdmissionCubit(session, repository);
    await c.loadDetail('admission');
    repository.failRead = true;
    await c.checkIn();
    expect(repository.writes, isEmpty);
    expect(c.state.error, 'Offline');
    repository.failRead = false;
    repository.delayed = Completer<Admission>();
    final checking = c.checkIn();
    session.clear();
    repository.delayed!.complete(example());
    await checking;
    expect(repository.writes, isEmpty);
    await c.close();
    await session.close();
  });

  test(
    'repeated taps while refreshing or saving do not duplicate check-ins',
    () async {
      final session = await workspace(), repository = AttendanceFake();
      final c = AdmissionCubit(session, repository);
      await c.loadDetail('admission');
      repository.delayed = Completer<Admission>();
      repository.saving = Completer<void>();
      final first = c.checkIn();
      await c.checkIn();
      expect(repository.writes, isEmpty);
      repository.delayed!.complete(example());
      await Future<void>.delayed(Duration.zero);
      expect(repository.writes.length, 1);
      await c.checkIn();
      expect(repository.writes.length, 1);
      repository.saving!.complete();
      await first;
      await c.close();
      await session.close();
    },
  );

  for (final fixed in [false, true]) {
    for (final width in [320.0, 1440.0]) {
      testWidgets(
        '${fixed ? 'Scheduled coaching' : 'Flexible plan'} marks present without a time picker at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1000);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final session = await workspace(), repository = AttendanceFake();
          addTearDown(session.close);
          final start = DateTime.now().toUtc().subtract(
            const Duration(minutes: 15),
          );
          final end = start.add(const Duration(hours: 1));
          if (fixed) {
            repository.record = example(
              kind: 'coaching',
              mode: 'fixed',
              visits: [
                AdmissionVisit(
                  id: 'scheduled',
                  start: start.toIso8601String().substring(0, 16),
                  end: end.toIso8601String().substring(0, 16),
                  startsAt: start.toIso8601String(),
                  endsAt: end.toIso8601String(),
                  status: 'scheduled',
                  attendance: 'unmarked',
                  version: 1,
                ),
              ],
            );
          }
          getIt.registerFactoryParam<AdmissionCubit, WorkspaceSession, void>(
            (s, _) => AdmissionCubit(s, repository),
          );
          await tester.pumpWidget(
            ScreenUtilInit(
              designSize: const Size(390, 844),
              builder: (_, _) => BlocProvider.value(
                value: session,
                child: MaterialApp(
                  theme: AppTheme.build(Brightness.light),
                  home: const AdmissionDetailScreen(id: 'admission'),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          addTearDown(() => tester.pumpWidget(const SizedBox()));
          final target = find.text(fixed ? 'Present' : 'Mark present');
          await tester.ensureVisible(target);
          await tester.pumpAndSettle();
          await tester.tap(target);
          await tester.pumpAndSettle();
          expect(find.byType(TimePickerDialog), findsNothing);
          expect(
            find.text('Visit start time (must include now)'),
            findsNothing,
          );
          if (fixed) {
            expect(repository.marks, [
              (id: 'scheduled', attendance: 'present'),
            ]);
            expect(repository.writes, isEmpty);
          } else {
            expect(repository.writes.length, 1);
            expect(repository.reads, greaterThanOrEqualTo(3));
          }
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
