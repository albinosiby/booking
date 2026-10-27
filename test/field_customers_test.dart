// Field-value tests for lib/modules/customers: phone search input, debounce,
// loading/empty/error states and small-screen / large-text rendering.
import 'dart:async';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/customers/cubit/customer_cubits.dart';
import 'package:eden_booking/modules/customers/models/customer_models.dart';
import 'package:eden_booking/modules/customers/repositories/customer_repository.dart';
import 'package:eden_booking/modules/customers/screens/customer_detail_screen.dart';
import 'package:eden_booking/modules/customers/screens/customers_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/repositories/workspace_session.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'booking_module_test.dart' show BookingSource;

class Repo implements CustomerRepository {
  final queries = <String>[];
  Object? failure;
  Completer<CustomerPage>? gate;
  List<CustomerSummary> items = const [
    CustomerSummary(id: 'c1', name: 'Alex', phone: '9876543210'),
  ];
  String? next;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  void invalidate() {}
  @override
  Future<CustomerPage> search({String query = '', String? after}) async {
    queries.add(query);
    if (failure != null) throw failure!;
    if (gate != null) return gate!.future;
    return CustomerPage(items, next);
  }

  @override
  Future<CustomerHistoryPage> history(String id, {String? cursor}) async {
    if (failure != null) throw failure!;
    return CustomerHistoryPage(
      customer: items.first,
      currency: 'INR',
      items: const [],
    );
  }
}

Future<void> settle([CustomerListCubit? c]) async {
  await Future<void>.delayed(const Duration(milliseconds: 400));
  for (var i = 0; c != null && c.state.loading && i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  group('customer list cubit', () {
    Future<(WorkspaceCubit, Repo, CustomerListCubit)> make() async {
      final w = WorkspaceCubit(BookingSource());
      await w.load();
      final r = Repo();
      final c = CustomerListCubit(w, r);
      return (w, r, c);
    }

    test(
      'rapid typing is debounced into one request with the last value',
      () async {
        final (w, r, c) = await make();
        for (final q in ['9', '98', '987', '9876']) {
          c.search(q);
        }
        await settle(c);
        expect(r.queries, ['9876']);
        expect(c.state.items, hasLength(1));
        await c.close();
        await w.close();
      },
    );

    test('odd queries are trimmed before they reach the API', () async {
      final (w, r, c) = await make();
      for (final q in [
        '',
        '   ',
        ' 98 ',
        '+91 98765',
        '😀',
        'x' * 500,
        "'; DROP TABLE--",
        '٩٨٧',
      ]) {
        c.search(q);
        await settle(c);
        expect(c.state.loading, isFalse, reason: q);
        expect(r.queries.last, q.trim(), reason: q);
        expect(c.state.error, isNull);
      }
      await c.close();
      await w.close();
    });

    test(
      'BUG-16 an over-long query is clamped before the request',
      () async {
        final (w, r, c) = await make();
        c.search('9' * 500);
        await settle(c);
        expect(r.queries.last.length, lessThanOrEqualTo(50));
        await c.close();
        await w.close();
      },
      skip:
          'BUG-16: cubit.search() forwards the raw query; the 50 char limit exists only on the text field (paste/restore paths bypass it)',
    );

    test(
      'failure shows a message, retry succeeds, non-AppException is generic',
      () async {
        final (w, r, c) = await make();
        r.failure = const AppException('Server down');
        await c.load();
        expect(c.state.error, 'Server down');
        r.failure = StateError('x');
        await c.load();
        expect(c.state.error, 'Could not load customers. Please try again.');
        r.failure = null;
        await c.load();
        expect(c.state.error, isNull);
        expect(c.state.items, isNotEmpty);
        await c.close();
        await w.close();
      },
    );

    test(
      'load more with no cursor is ignored and double load-more sends one request',
      () async {
        final (w, r, c) = await make();
        r.next = 'n1';
        await c.load();
        final before = r.queries.length;
        r.gate = Completer<CustomerPage>();
        unawaited(c.load(more: true));
        unawaited(c.load(more: true));
        await Future<void>.delayed(Duration.zero);
        expect(r.queries.length, before + 1);
        r.gate!.complete(
          CustomerPage(const [
            CustomerSummary(id: 'c2', name: 'B', phone: '1'),
          ], null),
        );
        await Future<void>.delayed(Duration.zero);
        expect(c.state.items, hasLength(2));
        final after = r.queries.length;
        await c.load(more: true);
        expect(r.queries.length, after, reason: 'no next cursor');
        await c.close();
        await w.close();
      },
    );
  });

  group('screens', () {
    Future<Repo> open(
      WidgetTester tester,
      Repo r, {
      String location = '/',
      Size size = const Size(320, 568),
      double scale = 1,
    }) async {
      await getIt.reset();
      final w = WorkspaceCubit(BookingSource());
      await tester.runAsync(w.load);
      getIt.registerFactoryParam<CustomerListCubit, WorkspaceSession, void>(
        (s, _) => CustomerListCubit(s, r),
      );
      getIt.registerFactoryParam<CustomerDetailCubit, WorkspaceSession, String>(
        (s, id) => CustomerDetailCubit(s, r, id),
      );
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final router = GoRouter(
        initialLocation: location,
        routes: [
          GoRoute(path: '/', builder: (_, _) => const CustomersScreen()),
          GoRoute(
            path: '/customers/:id',
            builder: (_, s) =>
                CustomerDetailScreen(id: s.pathParameters['id']!),
          ),
        ],
      );
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await getIt.reset();
        await w.close();
      });
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp.router(
              routerConfig: router,
              theme: AppTheme.build(Brightness.light),
              builder: (context, app) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: app!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return r;
    }

    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'list with long / emoji / RTL names at 320x568 scale $scale',
        (tester) async {
          final r = Repo()
            ..items = [
              CustomerSummary(
                id: 'a',
                name: 'Long ${'N' * 150} 😀',
                phone: '+91 98765 43210 ${'1' * 20}',
              ),
              const CustomerSummary(
                id: 'b',
                name: 'مرحبا بالعالم',
                phone: '٩٨٧٦٥٤٣٢١٠',
                recordCount: 12,
              ),
              const CustomerSummary(id: 'c', name: '', phone: ''),
            ];
          await open(tester, r, scale: scale);
          expect(find.text('No customers yet'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }

    testWidgets(
      'search box clamps to 50 characters, accepts emoji, clear resets',
      (tester) async {
        final r = Repo();
        await open(tester, r);
        final field = find.byType(TextField).first;
        await tester.enterText(field, '9' * 80);
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.widget<TextField>(field).controller!.text.length, 50);
        await tester.enterText(field, '😀📞');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(
          find.text('No matching phone numbers'),
          findsNothing,
          reason: 'fake repo ignores query',
        );
        await tester.tap(find.byTooltip('Clear search'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, '');
        expect(r.queries.last, '');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('empty list: no customers vs no matches', (tester) async {
      final r = Repo()..items = const [];
      await open(tester, r, scale: 2);
      expect(find.text('No customers yet'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '000');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(find.text('No matching phone numbers'), findsOneWidget);
    });

    group(
      'BUG-24',
      () {
        testWidgets('whitespace-only search is treated as no search', (
          tester,
        ) async {
          final r = Repo()..items = const [];
          await open(tester, r, scale: 2);
          await tester.enterText(find.byType(TextField).first, '   ');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();
          expect(
            find.text('No customers yet'),
            findsOneWidget,
            reason: 'whitespace is not a search',
          );
        });
      },
      skip:
          'BUG-24: a whitespace-only query is stored untrimmed so the empty state says "No matching phone numbers" instead of "No customers yet"',
    );

    testWidgets('error state shows the message without overflow', (
      tester,
    ) async {
      final r = Repo()
        ..failure = AppException('Could not reach the server. ${'x' * 200}');
      await open(tester, r, scale: 2);
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('loading state while the first page is pending', (
      tester,
    ) async {
      final r = Repo()..gate = Completer<CustomerPage>();
      await getIt.reset();
      final w = WorkspaceCubit(BookingSource());
      await tester.runAsync(w.load);
      getIt.registerFactoryParam<CustomerListCubit, WorkspaceSession, void>(
        (s, _) => CustomerListCubit(s, r),
      );
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(() async {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        await tester.pumpWidget(const SizedBox());
        await getIt.reset();
        await w.close();
      });
      await tester.pumpWidget(
        BlocProvider.value(
          value: w,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp(
              theme: AppTheme.build(Brightness.light),
              home: const CustomersScreen(),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(AppLoadingState), findsOneWidget);
      expect(find.text('No customers yet'), findsNothing);
    });

    testWidgets('detail: empty history and long name at 320px scale 2', (
      tester,
    ) async {
      final r = Repo()
        ..items = [
          CustomerSummary(
            id: 'c1',
            name: 'Name ${'W' * 200}',
            phone: '+91 98765 43210',
            recordCount: 3,
          ),
        ];
      await open(tester, r, location: '/customers/c1', scale: 2);
      expect(find.text('No bookings yet'), findsOneWidget);
      expect(find.textContaining('Multiple customer records'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('detail: error state', (tester) async {
      final r = Repo()..failure = const AppException('History unavailable');
      await open(tester, r, location: '/customers/c1', scale: 2);
      expect(find.text('History unavailable'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
