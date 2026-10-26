import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/booking_website/cubit/booking_website_link_cubit.dart';
import 'package:eden_booking/modules/booking_website/models/booking_website_link.dart';
import 'package:eden_booking/modules/booking_website/repositories/booking_website_link_repository.dart';
import 'package:eden_booking/modules/booking_website/repositories/website_link_actions.dart';
import 'package:eden_booking/modules/booking_website/widgets/booking_website_link_sheet.dart';
import 'package:eden_booking/modules/dashboard/cubit/home_cubit.dart';
import 'package:eden_booking/modules/dashboard/repositories/dashboard_repository.dart';
import 'package:eden_booking/modules/dashboard/screens/home_screen.dart';
import 'package:eden_booking/modules/workspace/cubit/workspace_cubit.dart';
import 'package:eden_booking/modules/workspace/models/workspace.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:eden_booking/utils/services/rest_api_service.dart';
import 'booking_module_test.dart' show BookingSource;

const published = BookingWebsiteLink(
  status: 'published',
  url: 'https://eden-sports.bookingos.online',
  canManage: true,
);

class LinkRepository implements BookingWebsiteLinkRepository {
  BookingWebsiteLink value = published;
  int reads = 0;
  final opened = <String>[], copied = <String>[];
  Object? error, actionError;
  Completer<BookingWebsiteLink>? pending;
  @override
  Future<BookingWebsiteLink> load() async {
    reads++;
    if (error != null) throw error!;
    return pending == null ? value : pending!.future;
  }

  @override
  Future<void> open(String url) async {
    if (actionError != null) throw actionError!;
    opened.add(url);
  }

  @override
  Future<void> copy(String url) async {
    if (actionError != null) throw actionError!;
    copied.add(url);
  }
}

class LinkApi extends Fake implements RestApiService {
  final calls = <String>[];
  @override
  Future<dynamic> request(
    String path, {
    String method = 'GET',
    Object? data,
    bool readOnly = false,
  }) async {
    calls.add('$method $path');
    return {'status': 'paused', 'url': published.url, 'can_manage': false};
  }
}

void main() {
  tearDown(() => getIt.reset());
  test('link repository uses only the lightweight endpoint', () async {
    final api = LinkApi();
    final result = await RestBookingWebsiteLinkRepository(api).load();
    expect(api.calls, ['GET /booking-website/link']);
    expect(result.status, 'paused');
    expect(result.available, isTrue);
    expect(result.canManage, isFalse);
  });

  test(
    'link actions accept public and local URLs and reject unsafe schemes',
    () {
      for (final url in [
        published.url!,
        'http://localhost:3000/eden',
        'http://eden.localhost:3000',
      ]) {
        expect(websiteLinkUri(url).hasAuthority, isTrue);
      }
      for (final url in [
        'javascript:alert(1)',
        '/relative',
        'http://example.com',
        'https:///',
      ]) {
        expect(() => websiteLinkUri(url), throwsA(isA<AppException>()));
      }
    },
  );

  test(
    'load and action errors recover; unpublished links cannot be opened',
    () async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = LinkRepository()..error = const AppException('Offline');
      final cubit = BookingWebsiteLinkCubit(workspace, repo);
      expect(repo.reads, 0);
      await cubit.load();
      expect(cubit.state.error, 'Offline');
      repo.error = null;
      await cubit.load();
      repo.actionError = const AppException('Clipboard blocked.');
      await cubit.copy();
      expect(cubit.state.error, 'Clipboard blocked.');
      repo.actionError = null;
      await cubit.copy();
      expect(cubit.state.message, 'Website link copied.');
      repo.value = const BookingWebsiteLink(status: 'unpublished');
      await cubit.load();
      await cubit.open();
      expect(repo.opened, isEmpty);
      await cubit.close();
      await workspace.close();
    },
  );

  test(
    'access failures clear the link and workspace changes discard late loads',
    () async {
      final source = BookingSource(), repo = LinkRepository();
      final workspace = WorkspaceCubit(source);
      await workspace.load();
      final cubit = BookingWebsiteLinkCubit(workspace, repo);
      await cubit.load();
      repo.error = const AppException('Access revoked', code: 'FORBIDDEN');
      await cubit.load();
      expect(cubit.state.link, isNull);
      repo.error = null;
      final gate = Completer<BookingWebsiteLink>();
      repo.pending = gate;
      final loading = cubit.load();
      source.value = Workspace(
        organization: source.value.organization,
        membership: const {
          'role': 'staff',
          'permissions': ['view_bookings'],
        },
        businesses: source.value.businesses,
      );
      await workspace.load();
      gate.complete(published);
      await loading;
      expect(cubit.state.link, isNull);
      expect(cubit.state.error, contains('workspace changed'));
      await cubit.copy();
      expect(repo.copied, isEmpty);
      await cubit.close();
      await workspace.close();
    },
  );

  testWidgets(
    'website link panel shows loading and errors without retry actions',
    (tester) async {
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final gate = Completer<BookingWebsiteLink>();
      final repo = LinkRepository()..pending = gate;
      final cubit = BookingWebsiteLinkCubit(workspace, repo);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        await cubit.close();
        await workspace.close();
      });
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(body: BookingWebsiteLinkSheet(onConfigure: () {})),
          ),
        ),
      );
      final loading = cubit.load();
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.text('Copy link'), findsNothing);
      gate.completeError(const AppException('Could not reach the server.'));
      await loading;
      await tester.pumpAndSettle();
      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(repo.reads, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (width, status, canManage) in [
    (320.0, 'published', true),
    (1280.0, 'paused', false),
    (390.0, 'unpublished', true),
  ]) {
    testWidgets('Home website link at $width pixels: $status', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final workspace = WorkspaceCubit(BookingSource());
      await workspace.load();
      final repo = LinkRepository()
        ..value = BookingWebsiteLink(
          status: status,
          url: status == 'unpublished' ? null : published.url,
          canManage: canManage,
        );
      getIt.registerFactoryParam<HomeCubit, WorkspaceCubit, void>(
        (session, _) => HomeCubit(SessionDashboardRepository(session)),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => HomeScreen(websiteLinks: () => repo),
          ),
          GoRoute(
            path: '/profile/booking-website',
            builder: (_, _) =>
                const Scaffold(body: Text('Website editor destination')),
          ),
        ],
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox());
        router.dispose();
        await workspace.close();
      });
      await tester.pumpWidget(
        BlocProvider.value(
          value: workspace,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) => MaterialApp.router(
              routerConfig: router,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(width == 320 ? 1.6 : 1),
                ),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.reads, 0);
      await tester.tap(find.byKey(const ValueKey('home-booking-website')));
      await tester.pumpAndSettle();
      expect(repo.reads, 1);
      final open = find.widgetWithText(FilledButton, 'Open website');
      if (status == 'unpublished') {
        expect(
          find.text('Your booking website is unpublished.'),
          findsOneWidget,
        );
        expect(tester.widget<FilledButton>(open).onPressed, isNull);
        expect(
          find.byKey(const ValueKey('home-booking-website-url')),
          findsNothing,
        );
      } else {
        expect(
          find.byKey(const ValueKey('home-booking-website-url')),
          findsOneWidget,
        );
        await tester.ensureVisible(find.text('Copy link'));
        await tester.tap(find.text('Copy link'));
        await tester.pumpAndSettle();
        expect(repo.copied, [published.url]);
        expect(find.text('Website link copied.'), findsOneWidget);
        await tester.tap(open);
        await tester.pumpAndSettle();
        expect(repo.opened, [published.url]);
        if (status == 'paused') {
          expect(
            find.textContaining('Online bookings are paused.'),
            findsOneWidget,
          );
        }
      }
      expect(tester.takeException(), isNull);
      if (canManage) {
        await tester.ensureVisible(find.text('Design website'));
        await tester.tap(find.text('Design website'));
        await tester.pumpAndSettle();
        expect(find.text('Website editor destination'), findsOneWidget);
      } else {
        expect(find.text('Design website'), findsNothing);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(find.text('Copy link'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
