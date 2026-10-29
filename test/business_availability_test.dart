import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/businesses/cubit/business_management_cubit.dart';
import 'package:eden_booking/modules/businesses/models/business_availability_action.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/businesses/screens/business_management_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'business_management_test.dart' show ManagementSource;

class AvailabilitySource extends ManagementSource {
  int attempts = 0;
  Completer<void>? wait;
  @override
  Future<void> setBusinessBookingEnabled(
    String id,
    bool enabled,
    int version,
  ) async {
    attempts++;
    await wait?.future;
    if (this.fail) {
      throw const AppException('Could not change business status.');
    }
    businesses = [
      for (final b in businesses)
        if (b.id != id)
          b
        else
          Business(
            id: b.id,
            name: b.name,
            type: b.type,
            status: enabled ? 'ready' : 'paused',
            locationId: b.locationId,
            version: b.version + 1,
            resources: b.resources,
            configuration: b.configuration,
          ),
    ];
  }
}

void main() {
  tearDown(() => getIt.reset());
  test(
    'toggle retains spaces and prevents duplicates and stale confirmations',
    () async {
      final source = AvailabilitySource();
      final active = WorkspaceCubit(source);
      await active.load();
      final cubit = BusinessManagementCubit(
        active,
        LocalApiBusinessRepository(source),
      );
      final action = BusinessAvailabilityAction.forBusiness(
        cubit.state.businesses.first,
      )!;
      source.wait = Completer<void>();
      final first = cubit.setBookingEnabled(action);
      expect(await cubit.setBookingEnabled(action), isFalse);
      expect(source.attempts, 1);
      source.wait!.complete();
      expect(await first, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.businesses.first.status, 'paused');
      expect(cubit.state.businesses.first.resources.single.id, 'ground');
      expect(await cubit.setBookingEnabled(action), isFalse);
      final on = BusinessAvailabilityAction.forBusiness(
        cubit.state.businesses.first,
      )!;
      expect(on.enabled, isTrue);
      expect(await cubit.setBookingEnabled(on), isTrue);
      expect(source.businesses.first.ready, isTrue);
      await cubit.close();
      await active.close();
    },
  );

  test(
    'failed toggle retains last status, and staff and draft business cannot toggle',
    () async {
      final source = AvailabilitySource();
      final active = WorkspaceCubit(source);
      await active.load();
      final cubit = BusinessManagementCubit(
        active,
        LocalApiBusinessRepository(source),
      );
      expect(
        BusinessAvailabilityAction.forBusiness(cubit.state.businesses.last),
        isNull,
      );
      source.fail = true;
      final action = BusinessAvailabilityAction.forBusiness(
        cubit.state.businesses.first,
      )!;
      expect(await cubit.setBookingEnabled(action), isFalse);
      expect(source.businesses.first.ready, isTrue);
      source.owner = false;
      await active.load();
      await Future<void>.delayed(Duration.zero);
      expect(await cubit.setBookingEnabled(action), isFalse);
      expect(source.attempts, 1);
      await cubit.close();
      await active.close();
    },
  );

  for (final width in [390.0, 1200.0]) {
    testWidgets('business menu confirms off and on at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 1000);
      addTearDown(tester.view.reset);
      final source = AvailabilitySource();
      getIt.registerSingleton<WorkspaceRepository>(source);
      registerFeatureDependencies(getIt);
      final session = WorkspaceCubit(source);
      await session.load();
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const BusinessManagementScreen(),
          ),
        ],
      );
      await tester.pumpWidget(
        BlocProvider.value(
          value: session,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final menu = find.byKey(const ValueKey('business-menu-turf'));
      expect(menu, findsOneWidget);
      expect(find.byKey(const ValueKey('business-menu-pool')), findsNothing);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off business'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(source.attempts, 0);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off business'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(source.attempts, 1);
      expect(source.businesses.first.status, 'paused');
      expect(find.textContaining('Off'), findsWidgets);
      await tester.tap(menu);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on business'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(source.businesses.first.ready, isTrue);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      await session.close();
    });
  }
}
