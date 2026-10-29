import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/di/feature_injection.dart';
import 'package:eden_booking/modules/businesses/cubit/business_management_cubit.dart';
import 'package:eden_booking/modules/businesses/models/business_removal_action.dart';
import 'package:eden_booking/modules/businesses/repositories/business_repository.dart';
import 'package:eden_booking/modules/businesses/screens/business_management_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_repository_interface.dart';
import 'package:eden_booking/modules/workspace/repositories/rest_workspace_repository.dart';
import 'package:eden_booking/modules/bookings/repositories/rest_booking_repository.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'package:eden_booking/utils/services/retained_read_cache.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'business_management_test.dart' show ManagementSource;
import 'business_order_sync_test.dart' show OrderAdapter;
import 'cached_transport_test.dart' show TestAuth;
import 'repository_cache_test.dart' show MemorySnapshotStore;

class RemovalSource extends ManagementSource {
  int attempts = 0;
  Completer<void>? wait;
  @override
  Future<void> removeBusiness(String id, int version) async {
    attempts++;
    await wait?.future;
    if (this.fail) {
      throw const AppException(
        'Resolve upcoming bookings before removing this business.',
      );
    }
    businesses = businesses.where((b) => b.id != id).toList();
    revision++;
  }
}

class RemovalAdapter extends OrderAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (options.method != 'DELETE') {
      return super.fetch(options, requestStream, cancelFuture);
    }
    expect(options.path, '/businesses/turf');
    final data = Map<String, dynamic>.from(
      options.data is String ? jsonDecode(options.data) : options.data,
    );
    expect(data, {'version': 1});
    writes.add(data);
    order.remove('turf');
    revision++;
    return ResponseBody.fromString(
      '{"id":"turf"}',
      200,
      headers: {
        'content-type': ['application/json'],
      },
    );
  }
}

void main() {
  tearDown(() => getIt.reset());

  test(
    'removal rejects duplicate submissions, staff, stale confirmations and reorder mode',
    () async {
      final source = RemovalSource();
      final active = WorkspaceCubit(source);
      await active.load();
      final cubit = BusinessManagementCubit(
        active,
        LocalApiBusinessRepository(source),
      );
      final action = BusinessRemovalAction.fromBusiness(
        cubit.state.businesses.first,
      );
      cubit.startReorder();
      expect(await cubit.removeBusiness(action), isFalse);
      cubit.cancelReorder();
      source.wait = Completer<void>();
      final first = cubit.removeBusiness(action);
      expect(await cubit.removeBusiness(action), isFalse);
      expect(source.attempts, 1);
      source.wait!.complete();
      expect(await first, isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(cubit.state.businesses.map((b) => b.id), ['pool']);
      expect(await cubit.removeBusiness(action), isFalse);
      expect(cubit.state.message, contains('changed'));
      source.owner = false;
      await active.load();
      await Future<void>.delayed(Duration.zero);
      expect(
        await cubit.removeBusiness(
          BusinessRemovalAction.fromBusiness(source.businesses.single),
        ),
        isFalse,
      );
      expect(source.attempts, 1);
      await cubit.close();
      await active.close();
    },
  );

  test(
    'blocked removal keeps the business and surfaces the server message',
    () async {
      final source = RemovalSource()..fail = true;
      final active = WorkspaceCubit(source);
      await active.load();
      final cubit = BusinessManagementCubit(
        active,
        LocalApiBusinessRepository(source),
      );
      expect(
        await cubit.removeBusiness(
          BusinessRemovalAction.fromBusiness(cubit.state.businesses.first),
        ),
        isFalse,
      );
      expect(source.businesses.length, 2);
      expect(active.state.error, contains('Resolve upcoming bookings'));
      await cubit.close();
      await active.close();
    },
  );

  test(
    'DELETE sends the confirmed version and invalidates retained booking catalogs',
    () async {
      final auth = TestAuth(), adapter = RemovalAdapter();
      final cache = RetainedReadCache(
        store: MemorySnapshotStore(),
        identity: () => auth.currentUser?.id,
      );
      final api = RestApiService(
        auth,
        readCache: cache,
        dio: Dio(BaseOptions(baseUrl: 'https://example.test'))
          ..httpClientAdapter = adapter,
      );
      final source = RestWorkspaceRepository(api),
          booking = RestBookingRepository(api);
      final active = WorkspaceCubit(source);
      await active.load();
      expect((await booking.catalog()).businesses.length, 2);
      final cubit = BusinessManagementCubit(
        active,
        LocalApiBusinessRepository(source),
      );
      expect(
        await cubit.removeBusiness(
          BusinessRemovalAction.fromBusiness(cubit.state.businesses.first),
        ),
        isTrue,
      );
      expect(adapter.writes, [
        {'version': 1},
      ]);
      expect((await booking.catalog()).businesses.map((b) => b.id), ['pool']);
      expect(cubit.state.businesses.map((b) => b.id), ['pool']);
      expect(adapter.reads.where((p) => p.endsWith('/catalog')).length, 2);
      await cubit.close();
      await active.close();
      await api.dispose();
      await auth.events.close();
    },
  );

  for (final width in [320.0, 390.0, 1200.0]) {
    testWidgets(
      'remove a configured or draft business with confirmation at width $width',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 1100);
        addTearDown(tester.view.reset);
        final source = RemovalSource();
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
              builder: (_, _) => MaterialApp.router(
                routerConfig: router,
                theme: width == 390 ? ThemeData.dark() : ThemeData.light(),
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(width == 320 ? 1.3 : 1),
                  ),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final id in ['turf', 'pool']) {
          final menu = find.byKey(ValueKey('business-menu-$id'));
          await tester.ensureVisible(menu);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Remove business'));
          await tester.pumpAndSettle();
          expect(
            find.textContaining('Past bookings, payments and reports'),
            findsOneWidget,
          );
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(source.attempts, id == 'turf' ? 0 : 1);
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Remove business'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Remove'));
          await tester.pumpAndSettle();
          expect(find.byKey(ValueKey('business-menu-$id')), findsNothing);
          expect(tester.takeException(), isNull);
        }
        expect(source.businesses, isEmpty);
        expect(find.text('No businesses yet'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        router.dispose();
        await session.close();
      },
    );
  }
}
