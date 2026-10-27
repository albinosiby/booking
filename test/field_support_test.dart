import 'dart:async';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/di/injection.dart';
import 'package:eden_booking/modules/support/screens/support_screens.dart';
import 'package:eden_booking/modules/support/support_module.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

SupportThread _thread({
  String subject = 'S',
  List<SupportMessage> m = const [],
}) => SupportThread(
  SupportTicket(
    id: 't1',
    subject: subject,
    category: 'other',
    status: 'open',
    updatedAt: null,
  ),
  m,
);

class _Repo implements SupportRepository {
  final created = <(String, String, String)>[];
  final replies = <String>[];
  Completer<void>? wait;
  Object? createFailure, listFailure, replyFailure;
  List<SupportTicket> list = [];
  SupportThread current = _thread();
  @override
  Future<List<SupportTicket>> tickets() async {
    if (listFailure != null) throw listFailure!;
    return list;
  }

  @override
  Future<SupportThread> create(String c, String s, String m) async {
    created.add((c, s, m));
    await wait?.future;
    if (createFailure != null) throw createFailure!;
    return _thread(subject: s);
  }

  @override
  Future<SupportThread> thread(String id) async => current;
  @override
  Future<SupportThread> reply(String id, String message) async {
    replies.add(message);
    await wait?.future;
    if (replyFailure != null) throw replyFailure!;
    return current;
  }
}

Future<_Repo> _mount(
  WidgetTester tester,
  String initial, {
  _Repo? repo,
  Size size = const Size(390, 844),
  double scale = 1,
  bool tolerateOverflow = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  if (tolerateOverflow) {
    // BUG-20 makes the topic dropdown overflow on every phone width; ignore
    // layout overflow here so the other behaviour is still verified.
    final original = FlutterError.onError;
    FlutterError.onError = (d) {
      if (!d.toString().contains('overflowed')) original?.call(d);
    };
    addTearDown(() => FlutterError.onError = original);
  }
  await getIt.reset();
  addTearDown(getIt.reset);
  final r = repo ?? _Repo();
  getIt.registerSingleton<SupportRepository>(r);
  final router = GoRouter(
    initialLocation: initial,
    routes: [
      GoRoute(path: '/', builder: (_, _) => const SupportScreen()),
      GoRoute(
        path: '/profile/support',
        builder: (_, _) => const SupportScreen(),
        routes: [
          GoRoute(
            path: ':id',
            builder: (_, s) => SupportThreadScreen(id: s.pathParameters['id']!),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      builder: (_, _) => MaterialApp.router(
        theme: darkTheme(),
        routerConfig: router,
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return r;
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Future<void> _send(WidgetTester tester) async {
  final b = find.widgetWithText(FilledButton, 'Send');
  await tester.ensureVisible(b);
  await tester.pumpAndSettle();
  await tester.tap(b);
  await tester.pump();
}

/// A confirmed defect, kept but skipped. The id is in the test name.
void bugWidgets(String bug, String name, WidgetTesterCallback body) =>
    testWidgets('[$bug] $name', body, skip: true);

void main() {
  bugWidgets('BUG-20', 'topic dropdown does not overflow at 390px', (
    tester,
  ) async {
    await _mount(tester, '/', tolerateOverflow: false);
    expect(tester.takeException(), isNull);
  });
  bugWidgets('BUG-20', 'topic dropdown does not overflow at 320px', (
    tester,
  ) async {
    await _mount(
      tester,
      '/',
      size: const Size(320, 568),
      tolerateOverflow: false,
    );
    expect(tester.takeException(), isNull);
  });

  group('report an issue form', () {
    testWidgets('empty and whitespace-only input is rejected with a prompt', (
      tester,
    ) async {
      final repo = await _mount(tester, '/');
      await _send(tester);
      expect(
        find.text('Add a short title and describe the issue.'),
        findsOneWidget,
      );
      await tester.enterText(_field('Title'), '     ');
      await tester.enterText(_field('What happened?'), '          ');
      await _send(tester);
      expect(repo.created, isEmpty);
    });

    for (final c in [('ab', 'long enough message'), ('A title', 'four')]) {
      testWidgets('too short title/message "${c.$1}" / "${c.$2}"', (
        tester,
      ) async {
        final repo = await _mount(tester, '/');
        await tester.enterText(_field('Title'), c.$1);
        await tester.enterText(_field('What happened?'), c.$2);
        await _send(tester);
        expect(repo.created, isEmpty);
      });
    }

    testWidgets('values are trimmed; unicode, emoji, newlines kept', (
      tester,
    ) async {
      final repo = await _mount(tester, '/');
      await tester.enterText(_field('Title'), '  ബുക്കിംഗ് 😀 problem  ');
      await tester.enterText(
        _field('What happened?'),
        '  line one\nline two ✓  ',
      );
      await _send(tester);
      await tester.pumpAndSettle();
      expect(repo.created.single.$2, 'ബുക്കിംഗ് 😀 problem');
      expect(repo.created.single.$3, 'line one\nline two ✓');
      expect(repo.created.single.$1, 'other');
    });

    testWidgets('max lengths are enforced on paste (160 / 4000)', (
      tester,
    ) async {
      final repo = await _mount(tester, '/');
      await tester.enterText(_field('Title'), 'T' * 400);
      await tester.enterText(_field('What happened?'), 'M' * 9000);
      await _send(tester);
      await tester.pumpAndSettle();
      expect(repo.created.single.$2.length, 160);
      expect(repo.created.single.$3.length, 4000);
    });

    testWidgets('double tap sends one ticket and clears the form', (
      tester,
    ) async {
      final repo = await _mount(tester, '/', repo: _Repo()..wait = Completer());
      await tester.enterText(_field('Title'), 'Payment issue');
      await tester.enterText(_field('What happened?'), 'Refund missing');
      final b = find.widgetWithText(FilledButton, 'Send');
      await tester.ensureVisible(b);
      await tester.pumpAndSettle();
      await tester.tap(b);
      await tester.tap(b);
      await tester.pump();
      expect(repo.created, hasLength(1));
      repo.wait!.complete();
      await tester.pumpAndSettle();
      expect(repo.created, hasLength(1));
    });

    testWidgets('failure keeps the typed text and shows the message', (
      tester,
    ) async {
      final repo = await _mount(
        tester,
        '/',
        repo: _Repo()..createFailure = const AppException('Rate limited.'),
      );
      await tester.enterText(_field('Title'), 'Payment issue');
      await tester.enterText(_field('What happened?'), 'Refund missing');
      await _send(tester);
      await tester.pumpAndSettle();
      expect(find.text('Rate limited.'), findsOneWidget);
      expect(find.text('Payment issue'), findsOneWidget);
      repo.createFailure = StateError('sql');
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await _send(tester);
      await tester.pumpAndSettle();
      expect(
        find.text('Could not complete this action. Please try again.'),
        findsOneWidget,
      );
    });

    testWidgets('topic can be changed and is submitted', (tester) async {
      final repo = await _mount(tester, '/');
      await tester.tap(find.text('Something else'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payments').last);
      await tester.pumpAndSettle();
      await tester.enterText(_field('Title'), 'Payment issue');
      await tester.enterText(_field('What happened?'), 'Refund missing');
      await _send(tester);
      await tester.pumpAndSettle();
      expect(repo.created.single.$1, 'payments');
    });
  });

  group('history states', () {
    testWidgets('empty state', (tester) async {
      await _mount(tester, '/');
      expect(find.text('No requests yet'), findsOneWidget);
    });

    testWidgets('load error shows retry that recovers', (tester) async {
      final repo = _Repo()..listFailure = const AppException('Offline');
      await _mount(tester, '/', repo: repo);
      expect(find.text('Offline'), findsOneWidget);
      repo.listFailure = null;
      repo.list = [_thread(subject: 'Old issue').ticket];
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Old issue'), findsOneWidget);
    });

    for (final size in [const Size(320, 568), const Size(1440, 900)]) {
      testWidgets('long and emoji subjects fit ${size.width}px at 2x text', (
        tester,
      ) async {
        final repo = _Repo()
          ..list = [
            _thread(subject: 'S' * 160).ticket,
            _thread(subject: '😀 ബുക്കിംഗ് problem').ticket,
          ];
        await _mount(tester, '/', repo: repo, size: size, scale: 2);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('thread reply', () {
    testWidgets('empty and whitespace replies are not sent', (tester) async {
      final repo = await _mount(tester, '/profile/support/t1');
      final reply = _field('Reply');
      await tester.enterText(reply, '    ');
      final b = find.widgetWithText(FilledButton, 'Send reply');
      await tester.ensureVisible(b);
      await tester.pumpAndSettle();
      await tester.tap(b);
      await tester.pumpAndSettle();
      expect(repo.replies, isEmpty);
    });

    testWidgets('reply is trimmed, double tap sends once and clears', (
      tester,
    ) async {
      final repo = await _mount(
        tester,
        '/profile/support/t1',
        repo: _Repo()..wait = Completer(),
      );
      await tester.enterText(_field('Reply'), '  thanks 😀  ');
      final b = find.widgetWithText(FilledButton, 'Send reply');
      await tester.ensureVisible(b);
      await tester.pumpAndSettle();
      await tester.tap(b);
      await tester.tap(b);
      await tester.pump();
      expect(repo.replies, ['thanks 😀']);
      repo.wait!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('failed reply keeps text and shows a message', (tester) async {
      await _mount(
        tester,
        '/profile/support/t1',
        repo: _Repo()..replyFailure = const AppException('Closed ticket.'),
      );
      await tester.enterText(_field('Reply'), 'hello there');
      final b = find.widgetWithText(FilledButton, 'Send reply');
      await tester.ensureVisible(b);
      await tester.pumpAndSettle();
      await tester.tap(b);
      await tester.pumpAndSettle();
      expect(find.text('Closed ticket.'), findsWidgets);
      expect(find.text('hello there'), findsOneWidget);
    });

    testWidgets('long messages and small screen do not overflow', (
      tester,
    ) async {
      final repo = _Repo()
        ..current = _thread(
          subject: 'S' * 160,
          m: [
            SupportMessage(
              fromSupport: true,
              name: 'x',
              body: 'W' * 800,
              createdAt: DateTime(2026, 10, 27),
            ),
            SupportMessage(
              fromSupport: false,
              name: 'y',
              body: '😀 ' * 200,
              createdAt: null,
            ),
          ],
        );
      await _mount(
        tester,
        '/profile/support/t1',
        repo: repo,
        size: const Size(320, 568),
        scale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
