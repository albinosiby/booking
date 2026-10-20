import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'booking_module_test.dart' show FakeBookingRepository;
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/dashboard/screens/home_screen.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/helpers/validation.dart';

class TestRepository extends Fake implements WorkspaceRepository {
  Workspace data = const Workspace();
  Completer<Workspace>? pending;
  bool fail = false;
  @override
  Future<Workspace> load() async {
    if (pending != null) return pending!.future;
    if (fail) throw const AppException('Server unreachable');
    return data;
  }
}

void main() {
  tearDown(() async {
    await getIt.reset();
  });
  test('money parsing is exact and rejects invalid precision', () {
    expect(Validation.priceMinor('1500.25'), 150025);
    expect(Validation.priceMinor('0.01'), 1);
    expect(Validation.priceMinor('12.345'), isNull);
    expect(Validation.priceMinor('-1'), isNull);
    expect(Validation.priceMinor('9' * 200), isNull);
    expect(Validation.priceMinor('1000000.01'), isNull);
  });
  test('a failed write clears busy and keeps workspace', () async {
    final repo = TestRepository();
    final cubit = WorkspaceCubit(repo);
    await cubit.load();
    expect(
      await cubit.perform((_) async {
        throw const AppException('Conflict');
      }),
      false,
    );
    expect(cubit.state.busy, false);
    expect(cubit.state.error, 'Conflict');
    expect(cubit.state.status, LoadStatus.ready);
    await cubit.close();
  });
  test(
    'a lost write response refreshes committed server data without repeating the write',
    () async {
      final repository = TestRepository();
      final cubit = WorkspaceCubit(repository);
      await cubit.load();
      var writes = 0;
      final confirmed = await cubit.perform((_) async {
        writes++;
        repository.data = const Workspace(
          organization: Organization(
            id: 'saved',
            name: 'Saved organization',
            phone: '123456789',
            currency: 'INR',
          ),
        );
        throw const AppException('Timeout', code: 'NETWORK');
      });
      expect(confirmed, false);
      expect(writes, 1);
      expect(cubit.state.data.organization?.id, 'saved');
      expect(cubit.state.busy, false);
      expect(cubit.state.error, contains('latest data'));
      await cubit.close();
    },
  );
  test('sign out invalidates an in-flight workspace load', () async {
    final repo = TestRepository()..pending = Completer<Workspace>();
    final cubit = WorkspaceCubit(repo);
    final loading = cubit.load();
    cubit.clear();
    repo.pending!.complete(
      const Workspace(
        organization: Organization(
          id: '1',
          name: 'Must not return',
          phone: '123456',
          currency: 'INR',
        ),
      ),
    );
    await loading;
    expect(cubit.state.status, LoadStatus.initial);
    expect(cubit.state.data.organization, isNull);
    await cubit.close();
  });
  testWidgets(
    'Home distinguishes ready and draft businesses at small width and large text',
    (tester) async {
      tester.view.physicalSize = const Size(320, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = TestRepository()
        ..data = const Workspace(
          organization: Organization(
            id: '1',
            name: 'Eden’s Area',
            phone: '123456789',
            currency: 'INR',
          ),
          membership: {'role': 'owner', 'permissions': []},
          businesses: [
            Business(
              id: 'turf',
              name: 'Eden Turf',
              type: BusinessType.turf,
              status: 'ready',
              locationId: 'l',
              version: 1,
              resources: [],
            ),
            Business(
              id: 'pool',
              name: 'Eden Swimming',
              type: BusinessType.pool,
              status: 'draft',
              locationId: 'l',
              version: 1,
              resources: [],
            ),
          ],
        );
      getIt.registerSingleton<WorkspaceRepository>(repo);
      registerFeatureDependencies(getIt);
      await getIt.unregister<HomeCubit>();
      final bookings = FakeBookingRepository();
      addTearDown(bookings.events.close);
      getIt.registerFactoryParam<HomeCubit, WorkspaceSession, void>(
        (session, _) =>
            HomeCubit(SessionDashboardRepository(session), bookings),
      );
      final cubit = WorkspaceCubit(repo);
      await cubit.load();
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (context, child) => MaterialApp(
              theme: darkTheme(),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(1.6)),
                child: child!,
              ),
              home: const HomeScreen(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Collected today'), findsOneWidget);
      expect(find.text('Configure'), findsOneWidget);
      expect(find.text('No bookings yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await cubit.close();
    },
  );
  testWidgets(
    'bottom navigation has all five accessible destinations at 320px',
    (tester) async {
      tester.view.physicalSize = const Size(320, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            bottomNavigationBar: AppBottomNavBar(index: 0, onTap: (_) {}),
          ),
        ),
      );
      for (final label in [
        'Home',
        'Calendar',
        'Bookings',
        'Accounts',
        'Profile',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(tester.takeException(), isNull);
    },
  );
}
