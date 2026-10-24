import 'package:dio/dio.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:eden_booking/modules/coaching/cubit/coach_classes_cubit.dart';
import 'package:eden_booking/modules/coaching/models/coach_class.dart';
import 'cached_transport_test.dart' show TestAdapter, TestAuth;
import 'coach_classes_test.dart' show FakeClasses, batch, student;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/components/app_bottom_nav_bar.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/models/workspace_navigation.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/config/routes/route_guard.dart';
import 'route_guard_test.dart' show signedIn;

Workspace staff(List<String> permissions) => Workspace(
  organization: const Organization(
    id: 'org',
    name: 'Eden',
    phone: '',
    currency: 'INR',
  ),
  membership: {'id': 'member', 'role': 'staff', 'permissions': permissions},
);

class AccessRepository extends Fake
    implements WorkspaceRepository, WorkspaceAccessRecovery {
  Workspace next = staff(['coach', 'mark_attendance']);
  Completer<Workspace>? pending;
  Object? failure;
  int reads = 0;
  Future<void> Function()? recovery;
  @override
  void setAccessRecovery(Future<void> Function()? recover) =>
      recovery = recover;
  @override
  Future<Workspace> load() async {
    reads++;
    if (failure != null) throw failure!;
    return pending?.future ?? next;
  }
}

class PendingClasses extends FakeClasses {
  final result = Completer<List<CoachClass>>();
  @override
  Future<CoachRoster> classes(String date) async =>
      CoachRoster(classes: await result.future);
}

void main() {
  test(
    'access denied waits for recovery and workspace failures cannot recurse',
    () async {
      final auth = TestAuth();
      final adapter = TestAdapter()..status = 403;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
        ..httpClientAdapter = adapter;
      final api = RestApiService(auth, dio: dio);
      var recoveries = 0;
      final gate = Completer<void>();
      final entered = Completer<void>();
      api.recoverAccess = () {
        recoveries++;
        if (!entered.isCompleted) entered.complete();
        return gate.future;
      };
      var finished = false;
      final requests = [api.request('/bookings')]
          .map(
            (f) => f.then<void>(
              (_) {},
              onError: (Object e) {
                expect(accessFailure(e), isTrue);
                finished = true;
              },
            ),
          )
          .toList();
      await entered.future.timeout(const Duration(seconds: 5));
      expect(recoveries, 1);
      expect(finished, isFalse);
      gate.complete();
      await Future.wait(requests);
      expect(finished, isTrue);
      await expectLater(
        api.request('/workspace/session', method: 'POST', readOnly: true),
        throwsA(predicate(accessFailure)),
      );
      expect(recoveries, 1);
      await api.dispose();
      await auth.events.close();
    },
  );
  test(
    'coach revocation discards an in-flight class response without an error',
    () async {
      final repository = AccessRepository();
      final session = WorkspaceCubit(repository);
      await session.load();
      final api = PendingClasses();
      final coach = CoachClassesCubit(api, session: session);
      final loading = coach.load();
      repository.next = staff([]);
      await session.refreshAccess();
      await Future<void>.delayed(Duration.zero);
      api.result.complete([
        batch([student('old')]),
      ]);
      await loading;
      expect(coach.state.classes, isEmpty);
      expect(coach.state.loading, isFalse);
      expect(coach.state.error, isNull);
      await coach.close();
      await session.close();
    },
  );
  test(
    'coach-only visibility and routes follow permissions, not assignment alone',
    () {
      final coach = WorkspaceNavigation(staff(['coach', 'mark_attendance']));
      expect(coach.branches, [0, 5, 4]);
      expect(coach.allows('/coaching/classes'), isTrue);
      for (final path in [
        '/payments',
        '/accounts/settings',
        '/income',
        '/customers',
        '/admissions',
        '/team',
        '/booking/new',
        '/calendar',
      ]) {
        expect(coach.allows(path), isFalse, reason: path);
      }
      expect(WorkspaceNavigation(staff([])).branches, [0, 4]);
      final collector = WorkspaceNavigation(staff(['collect_payments']));
      expect(collector.branches, [0, 1, 2, 4]);
      expect(collector.finance, isFalse);
      expect(collector.customers, isTrue);
      expect(collector.admissions, isTrue);
      final finance = WorkspaceNavigation(staff(['view_finance']));
      expect(finance.branches, [0, 3, 4]);
      expect(finance.allows('/accounts/reports'), isTrue);
      expect(finance.allows('/accounts/bank/new'), isFalse);
    },
  );
  test(
    'refresh coalesces, stays visible, applies revocation and protects direct routes',
    () async {
      final repository = AccessRepository();
      final cubit = WorkspaceCubit(repository);
      await cubit.load();
      final events = <WorkspaceState>[];
      final sub = cubit.stream.listen(events.add);
      repository.pending = Completer();
      final first = cubit.refreshAccess();
      final second = cubit.refreshAccess();
      expect(repository.reads, 2);
      expect(cubit.state.status, LoadStatus.ready);
      expect(cubit.state.data.isCoach, isTrue);
      repository.pending!.complete(staff([]));
      await Future.wait([first, second]);
      await Future<void>.delayed(Duration.zero);
      expect(
        events.every((e) => e.status == LoadStatus.ready && e.error == null),
        isTrue,
      );
      expect(cubit.state.data.isCoach, isFalse);
      expect(
        routeRedirect(
          signedIn,
          cubit.state,
          Uri.parse('/coaching/classes'),
          requireVerification: false,
        ),
        '/home',
      );
      expect(
        WorkspaceNavigation(cubit.state.data).reducedFrom(staff(['coach'])),
        isTrue,
      );
      expect(repository.recovery, isNotNull);
      await sub.cancel();
      await cubit.close();
      expect(repository.recovery, isNull);
    },
  );
  test(
    'network errors keep UI; revoked membership clears it; logout ignores late data',
    () async {
      final repository = AccessRepository(),
          cubit = WorkspaceCubit(AccessRepository());
      await cubit.close();
      final c = WorkspaceCubit(repository);
      await c.load();
      repository.failure = const AppException('offline', code: 'NETWORK');
      await c.refreshAccess();
      expect(c.state.data.isCoach, isTrue);
      expect(c.state.error, isNull);
      repository.failure = const AppException('revoked', code: 'FORBIDDEN');
      await c.refreshAccess();
      expect(c.state.data.organization, isNull);
      repository.failure = null;
      await c.load();
      repository.pending = Completer();
      final pending = c.refreshAccess();
      c.clear();
      repository.pending!.complete(staff(['view_finance']));
      await pending;
      expect(c.state.data.organization, isNull);
      await c.close();
    },
  );
  testWidgets(
    'filtered bar maps taps to router branches and updates on grants',
    (tester) async {
      int? selected;
      Future<void> show(List<String> permissions, int branch) =>
          tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                bottomNavigationBar: AppBottomNavBar(
                  index: branch,
                  branches: WorkspaceNavigation(staff(permissions)).branches,
                  onTap: (i) => selected = i,
                ),
              ),
            ),
          );
      await show(['coach', 'mark_attendance'], 5);
      expect(find.text('Accounts'), findsNothing);
      expect(find.text('My classes'), findsOneWidget);
      await tester.tap(find.text('Profile'));
      expect(selected, 4);
      await show(['coach', 'view_finance'], 3);
      expect(find.text('Accounts'), findsOneWidget);
      await tester.tap(find.text('My classes'));
      expect(selected, 5);
      expect(tester.takeException(), isNull);
    },
  );
}
