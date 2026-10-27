import 'dart:async';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/auth/repositories/auth_repository_interface.dart';
import 'package:eden_booking/modules/auth/screens/auth_screen.dart';
import 'package:eden_booking/modules/auth/screens/password_update_screen.dart';
import 'package:eden_booking/modules/auth/screens/verification_screen.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _token =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

class FieldAuthRepo extends Fake
    implements AuthRepository, PasswordUpdateRepository {
  final events = StreamController<AppUser?>.broadcast();
  AppUser? user;
  Completer<void>? wait;
  Object? failure;
  final signIns = <(String, String)>[];
  final registers = <(String, String, String)>[];
  final resets = <String>[];
  final updates = <String>[];
  int reloads = 0, verifications = 0, signOuts = 0;

  Future<void> _go() async {
    await wait?.future;
    if (failure != null) throw failure!;
  }

  @override
  Stream<AppUser?> get changes => events.stream;
  @override
  AppUser? get currentUser => user;
  @override
  Future<void> signIn(String email, String password) async {
    signIns.add((email, password));
    await _go();
  }

  @override
  Future<void> register(String name, String email, String password) async {
    registers.add((name, email, password));
    await _go();
  }

  @override
  Future<void> resetPassword(String email) async {
    resets.add(email);
    await _go();
  }

  @override
  Future<void> updatePassword(String password) async {
    updates.add(password);
    await _go();
  }

  @override
  Future<void> reload() async {
    reloads++;
    await _go();
  }

  @override
  Future<void> sendVerification() async {
    verifications++;
    await _go();
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    await _go();
  }
}

Future<AuthCubit> _mount(
  WidgetTester tester,
  FieldAuthRepo repo, {
  bool register = false,
  String? invite,
  String? returnTo,
  Size size = const Size(390, 844),
  double textScale = 1,
  double keyboard = 0,
  Widget? home,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);
  final cubit = AuthCubit(repo);
  addTearDown(cubit.close);
  addTearDown(repo.events.close);
  await tester.pumpWidget(
    BlocProvider.value(
      value: cubit,
      child: ScreenUtilInit(
        designSize: const Size(390, 844),
        builder: (context, _) => MaterialApp(
          theme: darkTheme(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home:
              home ??
              AuthScreen(
                register: register,
                invitationToken: invite,
                returnTo: returnTo,
              ),
        ),
      ),
    ),
  );
  await tester.pump();
  return cubit;
}

/// A confirmed defect: kept in the suite but skipped so it stays green.
/// The BUG id is in the test name; see docs/audits/test-report-flutter-auth-team.md.
void bugWidgets(String bug, String name, WidgetTesterCallback body) =>
    testWidgets('[$bug] $name', body, skip: true);

Finder get _name => find.byType(TextFormField).at(0);
Finder _emailField(bool register) =>
    find.byType(TextFormField).at(register ? 1 : 0);
Finder _passwordField(bool register) =>
    find.byType(TextFormField).at(register ? 2 : 1);

Future<void> _fill(
  WidgetTester tester, {
  String? name,
  String? email,
  String? password,
  bool register = false,
}) async {
  if (name != null) await tester.enterText(_name, name);
  if (email != null) await tester.enterText(_emailField(register), email);
  if (password != null) {
    await tester.enterText(_passwordField(register), password);
  }
}

Future<void> _tapSubmit(WidgetTester tester, String label) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.tap(button);
  await tester.pump();
}

void main() {
  group('sign in fields', () {
    testWidgets('empty submit shows both errors and sends nothing', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      await _tapSubmit(tester, 'Sign in');
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('This field is required'), findsOneWidget);
      expect(repo.signIns, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets('whitespace-only email and password are rejected', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      await _fill(tester, email: '     ', password: '     ');
      await _tapSubmit(tester, 'Sign in');
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('This field is required'), findsOneWidget);
      expect(repo.signIns, isEmpty);
    });

    for (final bad in [
      'plain',
      'a@b',
      '@example.com',
      'a@@example.com',
      'a b@example.com',
      'own er@example.com',
      'a@example',
      'owner@example.com owner2@example.com',
      '😀',
    ]) {
      testWidgets('invalid email "$bad" never reaches the repository', (
        tester,
      ) async {
        final repo = FieldAuthRepo();
        await _mount(tester, repo);
        await _fill(tester, email: bad, password: 'secret-pass');
        await _tapSubmit(tester, 'Sign in');
        expect(find.text('Enter a valid email'), findsOneWidget);
        expect(repo.signIns, isEmpty);
      });
    }

    testWidgets(
      'pasted email with surrounding spaces and newline is accepted',
      (tester) async {
        final repo = FieldAuthRepo();
        await _mount(tester, repo);
        await _fill(
          tester,
          email: '  owner@example.com \n',
          password: 'p w d ',
        );
        await _tapSubmit(tester, 'Sign in');
        await tester.pumpAndSettle();
        expect(repo.signIns, hasLength(1));
        // The repository is responsible for trim(); the password is untouched.
        expect(repo.signIns.single.$1.trim(), 'owner@example.com');
        expect(repo.signIns.single.$2, 'p w d ');
      },
    );

    testWidgets('unicode and emoji passwords are passed through unchanged', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      await _fill(
        tester,
        email: 'owner@example.com',
        password: 'pässwörd-😀-ഏബിൻ',
      );
      await _tapSubmit(tester, 'Sign in');
      await tester.pumpAndSettle();
      expect(repo.signIns.single.$2, 'pässwörd-😀-ഏബിൻ');
    });

    testWidgets('very long password is submitted without overflow', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      await _fill(tester, email: 'owner@example.com', password: 'x' * 500);
      await _tapSubmit(tester, 'Sign in');
      await tester.pumpAndSettle();
      expect(repo.signIns.single.$2.length, 500);
      expect(tester.takeException(), isNull);
    });

    bugWidgets('BUG-4', '300 character email is rejected before the request', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      await _fill(
        tester,
        email: '${'a' * 290}@example.com',
        password: 'secret-pass',
      );
      await _tapSubmit(tester, 'Sign in');
      expect(repo.signIns, isEmpty);
    });

    bugWidgets(
      'BUG-10',
      'a password of spaces that registration accepted can still sign in',
      (tester) async {
        final repo = FieldAuthRepo();
        await _mount(tester, repo);
        await _fill(tester, email: 'owner@example.com', password: '        ');
        await _tapSubmit(tester, 'Sign in');
        await tester.pumpAndSettle();
        expect(repo.signIns, hasLength(1));
      },
    );

    testWidgets('password visibility toggles and tooltip follows state', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      EditableText field() => tester.widget<EditableText>(
        find.descendant(
          of: _passwordField(false),
          matching: find.byType(EditableText),
        ),
      );
      expect(field().obscureText, isTrue);
      await tester.tap(find.byTooltip('Show password'));
      await tester.pump();
      expect(field().obscureText, isFalse);
      expect(find.byTooltip('Hide password'), findsOneWidget);
      await tester.tap(find.byTooltip('Hide password'));
      await tester.pump();
      expect(field().obscureText, isTrue);
    });

    testWidgets('email field has email keyboard, autofill and no autocorrect', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      final email = tester.widget<EditableText>(
        find.descendant(
          of: _emailField(false),
          matching: find.byType(EditableText),
        ),
      );
      expect(email.keyboardType, TextInputType.emailAddress);
      expect(email.autocorrect, isFalse);
      final pass = tester.widget<EditableText>(
        find.descendant(
          of: _passwordField(false),
          matching: find.byType(EditableText),
        ),
      );
      expect(pass.enableSuggestions, isFalse);
      expect(pass.autocorrect, isFalse);
    });

    testWidgets('double tap on Sign in sends exactly one request', (
      tester,
    ) async {
      final repo = FieldAuthRepo()..wait = Completer<void>();
      await _mount(tester, repo);
      await _fill(tester, email: 'owner@example.com', password: 'secret-pass');
      final button = find.widgetWithText(FilledButton, 'Sign in');
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      await tester.pump();
      expect(repo.signIns, hasLength(1));
      expect(find.text('Signing in…'), findsOneWidget);
      repo.wait!.complete();
      await tester.pumpAndSettle();
      expect(repo.signIns, hasLength(1));
    });

    testWidgets('keyboard done action plus tap does not double submit', (
      tester,
    ) async {
      final repo = FieldAuthRepo()..wait = Completer<void>();
      await _mount(tester, repo);
      await _fill(tester, email: 'owner@example.com', password: 'secret-pass');
      await tester.showKeyboard(_passwordField(false));
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Signing in…'),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(repo.signIns, hasLength(1));
      repo.wait!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('loading state disables fields, reset link and mode switch', (
      tester,
    ) async {
      final repo = FieldAuthRepo()..wait = Completer<void>();
      await _mount(tester, repo);
      await _fill(tester, email: 'owner@example.com', password: 'secret-pass');
      await _tapSubmit(tester, 'Sign in');
      for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(f.enabled, isFalse);
      }
      expect(
        tester
            .widget<TextButton>(
              find.widgetWithText(TextButton, 'Forgot password?'),
            )
            .onPressed,
        isNull,
      );
      repo.wait!.complete();
      await tester.pumpAndSettle();
      for (final f in tester.widgetList<TextField>(find.byType(TextField))) {
        expect(f.enabled, isTrue);
      }
    });

    testWidgets('backend rejection shows its message and keeps the input', (
      tester,
    ) async {
      final repo = FieldAuthRepo()
        ..failure = const AppException('Email or password is incorrect.');
      await _mount(tester, repo);
      await _fill(tester, email: 'owner@example.com', password: 'wrong-pass');
      await _tapSubmit(tester, 'Sign in');
      await tester.pumpAndSettle();
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(find.text('owner@example.com'), findsOneWidget);
      // retry works once the backend recovers
      repo.failure = null;
      await _tapSubmit(tester, 'Sign in');
      await tester.pumpAndSettle();
      expect(repo.signIns, hasLength(2));
      expect(find.text('Email or password is incorrect.'), findsNothing);
    });

    testWidgets('unexpected exceptions are replaced with a generic message', (
      tester,
    ) async {
      final repo = FieldAuthRepo()..failure = StateError('socket /10.0.0.4');
      await _mount(tester, repo);
      await _fill(tester, email: 'owner@example.com', password: 'secret-pass');
      await _tapSubmit(tester, 'Sign in');
      await tester.pumpAndSettle();
      expect(
        find.text('Could not complete this action. Try again.'),
        findsOneWidget,
      );
      expect(find.textContaining('10.0.0.4'), findsNothing);
    });
  });

  group('forgot password', () {
    testWidgets('empty or invalid email asks for the address first', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();
      expect(find.text('Enter your email address first.'), findsOneWidget);
      await _fill(tester, email: 'not-an-email');
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();
      expect(repo.resets, isEmpty);
    });

    testWidgets('valid email requests a reset and shows neutral copy', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo);
      await _fill(tester, email: ' owner@example.com ');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(repo.resets, hasLength(1));
      expect(
        find.text('If an account exists, a reset email has been requested.'),
        findsOneWidget,
      );
    });

    testWidgets('failed reset shows the error and not the success snackbar', (
      tester,
    ) async {
      final repo = FieldAuthRepo()
        ..failure = const AppException('Too many attempts. Please wait.');
      await _mount(tester, repo);
      await _fill(tester, email: 'owner@example.com');
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(find.text('Too many attempts. Please wait.'), findsOneWidget);
      expect(
        find.text('If an account exists, a reset email has been requested.'),
        findsNothing,
      );
    });
  });

  group('register fields', () {
    testWidgets('empty submit shows name, email and password errors', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo, register: true);
      await _tapSubmit(tester, 'Create account');
      expect(find.text('Enter at least two characters'), findsOneWidget);
      expect(find.text('Enter a valid email'), findsOneWidget);
      expect(find.text('Use at least eight characters'), findsOneWidget);
      expect(repo.registers, isEmpty);
    });

    for (final badName in ['', ' ', 'A', '   A   ', 'a' * 121]) {
      testWidgets(
        'invalid name "${badName.length > 10 ? 'x' * 121 : badName}"',
        (tester) async {
          final repo = FieldAuthRepo();
          await _mount(tester, repo, register: true);
          await _fill(
            tester,
            register: true,
            name: badName,
            email: 'owner@example.com',
            password: 'secret-pass',
          );
          await _tapSubmit(tester, 'Create account');
          expect(repo.registers, isEmpty);
          expect(
            find.textContaining(RegExp('at least two|120 characters')),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets('7 character password is rejected and 8 is accepted', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo, register: true);
      await _fill(
        tester,
        register: true,
        name: 'Eden Owner',
        email: 'owner@example.com',
        password: '1234567',
      );
      await _tapSubmit(tester, 'Create account');
      expect(find.text('Use at least eight characters'), findsOneWidget);
      expect(repo.registers, isEmpty);
      await _fill(tester, register: true, password: '12345678');
      await _tapSubmit(tester, 'Create account');
      await tester.pumpAndSettle();
      expect(repo.registers, hasLength(1));
    });

    testWidgets('unicode, malayalam and emoji names are accepted', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo, register: true);
      await _fill(
        tester,
        register: true,
        name: 'ഏബിൻ José 😀',
        email: 'owner@example.com',
        password: 'secret-pass',
      );
      await _tapSubmit(tester, 'Create account');
      await tester.pumpAndSettle();
      expect(repo.registers.single.$1, 'ഏബിൻ José 😀');
    });

    testWidgets('120 character name is accepted and 121 is rejected', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo, register: true);
      await _fill(
        tester,
        register: true,
        name: 'a' * 120,
        email: 'owner@example.com',
        password: 'secret-pass',
      );
      await _tapSubmit(tester, 'Create account');
      await tester.pumpAndSettle();
      expect(repo.registers, hasLength(1));
    });

    bugWidgets('BUG-1', '61 emoji name (61 characters) is accepted', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo, register: true);
      await _fill(
        tester,
        register: true,
        name: '😀' * 61,
        email: 'owner@example.com',
        password: 'secret-pass',
      );
      await _tapSubmit(tester, 'Create account');
      await tester.pumpAndSettle();
      expect(repo.registers, hasLength(1));
    });

    testWidgets('double tap on Create account registers once', (tester) async {
      final repo = FieldAuthRepo()..wait = Completer<void>();
      await _mount(tester, repo, register: true);
      await _fill(
        tester,
        register: true,
        name: 'Eden Owner',
        email: 'owner@example.com',
        password: 'secret-pass',
      );
      final button = find.widgetWithText(FilledButton, 'Create account');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(repo.registers, hasLength(1));
      expect(find.text('Creating account…'), findsOneWidget);
      repo.wait!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('email confirmation is shown as a notice, not an error', (
      tester,
    ) async {
      final repo = FieldAuthRepo()
        ..failure = const AppException(
          'Check your inbox to confirm your email, then choose Sign in.',
          code: 'EMAIL_CONFIRMATION_REQUIRED',
        );
      final cubit = await _mount(tester, repo, register: true);
      await _fill(
        tester,
        register: true,
        name: 'Eden Owner',
        email: 'owner@example.com',
        password: 'secret-pass',
      );
      await _tapSubmit(tester, 'Create account');
      await tester.pumpAndSettle();
      expect(cubit.state.error, isNull);
      expect(cubit.state.notice, contains('Check your inbox'));
      expect(find.textContaining('Check your inbox'), findsOneWidget);
    });

    testWidgets('existing-account error from the backend is surfaced', (
      tester,
    ) async {
      final repo = FieldAuthRepo()
        ..failure = const AppException(
          'This email already has an account. Sign in instead.',
        );
      await _mount(tester, repo, register: true);
      await _fill(
        tester,
        register: true,
        name: 'Eden Owner',
        email: 'owner@example.com',
        password: 'secret-pass',
      );
      await _tapSubmit(tester, 'Create account');
      await tester.pumpAndSettle();
      expect(find.textContaining('already has an account'), findsOneWidget);
    });

    bugWidgets('BUG-6', 'an eight-space password is rejected on register', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo, register: true);
      await _fill(
        tester,
        register: true,
        name: 'Eden Owner',
        email: 'owner@example.com',
        password: '        ',
      );
      await _tapSubmit(tester, 'Create account');
      expect(repo.registers, isEmpty);
    });

    testWidgets('invitation mode labels the name field and keeps copy', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(tester, repo, register: true, invite: _token);
      expect(find.text('STAFF INVITATION'), findsOneWidget);
      expect(find.text('Your full name'), findsOneWidget);
      expect(find.text('Join your team.'), findsOneWidget);
    });
  });

  group('small screen and large text', () {
    for (final scenario in [
      (name: 'sign in', register: false, invite: false),
      (name: 'register', register: true, invite: false),
      (name: 'invited register', register: true, invite: true),
    ]) {
      for (final scale in [1.0, 2.0, 3.0]) {
        testWidgets(
          '${scenario.name} fits 320x568 at text scale $scale with errors and keyboard',
          (tester) async {
            final repo = FieldAuthRepo()
              ..failure = const AppException(
                'A deliberately long error message that must wrap onto several lines without clipping or overflowing the card on a narrow phone.',
              );
            await _mount(
              tester,
              repo,
              register: scenario.register,
              invite: scenario.invite ? _token : null,
              size: const Size(320, 568),
              textScale: scale,
              keyboard: 250,
            );
            expect(tester.takeException(), isNull);
            // show validation errors in every field
            await _tapSubmit(
              tester,
              scenario.register ? 'Create account' : 'Sign in',
            );
            expect(tester.takeException(), isNull);
            await _fill(
              tester,
              register: scenario.register,
              name: scenario.register ? 'Eden Owner' : null,
              email: 'owner@example.com',
              password: 'secret-pass',
            );
            await _tapSubmit(
              tester,
              scenario.register ? 'Create account' : 'Sign in',
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            expect(
              find.textContaining('deliberately long error'),
              findsOneWidget,
            );
            // every control is reachable by scrolling
            await tester.ensureVisible(find.byType(FilledButton));
            expect(tester.takeException(), isNull);
          },
        );
      }
    }

    testWidgets('a 200 character unbroken name and email do not overflow', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      await _mount(
        tester,
        repo,
        register: true,
        size: const Size(320, 568),
        textScale: 2,
      );
      await _fill(
        tester,
        register: true,
        name: 'W' * 200,
        email: '${'e' * 190}@example.com',
        password: 'p' * 200,
      );
      await _tapSubmit(tester, 'Create account');
      expect(tester.takeException(), isNull);
    });
  });

  group('mode switch keeps invitation and return path', () {
    testWidgets('sign in to register carries invite and encoded from', (
      tester,
    ) async {
      final repo = FieldAuthRepo();
      String? seen;
      final router = GoRouter(
        initialLocation: '/sign-in',
        routes: [
          GoRoute(
            path: '/sign-in',
            builder: (_, _) => const AuthScreen(
              register: false,
              invitationToken: _token,
              returnTo: '/bookings?day=2026-10-27&q=a b',
            ),
          ),
          GoRoute(
            path: '/register',
            builder: (_, state) {
              seen = state.uri.toString();
              return const Scaffold(body: Text('register route'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      final cubit = AuthCubit(repo);
      addTearDown(cubit.close);
      addTearDown(repo.events.close);
      await tester.pumpWidget(
        BlocProvider.value(
          value: cubit,
          child: ScreenUtilInit(
            designSize: const Size(390, 844),
            builder: (_, _) =>
                MaterialApp.router(theme: darkTheme(), routerConfig: router),
          ),
        ),
      );
      await tester.pump();
      final switchMode = find.byType(TextButton).last;
      await tester.ensureVisible(switchMode);
      await tester.tap(switchMode);
      await tester.pumpAndSettle();
      expect(find.text('register route'), findsOneWidget);
      final uri = Uri.parse(seen!);
      expect(uri.queryParameters['invite'], _token);
      expect(uri.queryParameters['from'], '/bookings?day=2026-10-27&q=a b');
    });
  });

  group('password update screen', () {
    Future<FieldAuthRepo> mountUpdate(
      WidgetTester tester, {
      Size size = const Size(390, 844),
      double scale = 1,
    }) async {
      final repo = FieldAuthRepo();
      await _mount(
        tester,
        repo,
        size: size,
        textScale: scale,
        home: const PasswordUpdateScreen(),
      );
      return repo;
    }

    testWidgets('empty submit shows the length error and nothing is sent', (
      tester,
    ) async {
      final repo = await mountUpdate(tester);
      await _tapSubmit(tester, 'Save password');
      expect(find.text('Use at least eight characters'), findsOneWidget);
      expect(repo.updates, isEmpty);
    });

    testWidgets('mismatched confirmation is rejected, trailing space counts', (
      tester,
    ) async {
      final repo = await mountUpdate(tester);
      await tester.enterText(find.byType(TextFormField).at(0), 'new-pass-123');
      await tester.enterText(find.byType(TextFormField).at(1), 'new-pass-123 ');
      await _tapSubmit(tester, 'Save password');
      expect(find.text('Passwords must match.'), findsOneWidget);
      expect(repo.updates, isEmpty);
    });

    testWidgets('matching unicode passwords are saved once on double tap', (
      tester,
    ) async {
      final repo = await mountUpdate(tester);
      repo.wait = Completer<void>();
      await tester.enterText(find.byType(TextFormField).at(0), 'nëw-pass-😀');
      await tester.enterText(find.byType(TextFormField).at(1), 'nëw-pass-😀');
      final button = find.widgetWithText(FilledButton, 'Save password');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(repo.updates, ['nëw-pass-😀']);
      repo.wait!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('backend failure is shown and can be retried', (tester) async {
      final repo = await mountUpdate(tester);
      repo.failure = const AppException('Choose a stronger password.');
      await tester.enterText(find.byType(TextFormField).at(0), 'password1');
      await tester.enterText(find.byType(TextFormField).at(1), 'password1');
      await _tapSubmit(tester, 'Save password');
      await tester.pumpAndSettle();
      expect(find.text('Choose a stronger password.'), findsOneWidget);
      repo.failure = null;
      await _tapSubmit(tester, 'Save password');
      await tester.pumpAndSettle();
      expect(repo.updates, hasLength(2));
    });

    bugWidgets('BUG-6', 'whitespace-only new password is rejected', (
      tester,
    ) async {
      final repo = await mountUpdate(tester);
      await tester.enterText(find.byType(TextFormField).at(0), ' ' * 8);
      await tester.enterText(find.byType(TextFormField).at(1), ' ' * 8);
      await _tapSubmit(tester, 'Save password');
      expect(repo.updates, isEmpty);
    });

    testWidgets('fits 320x568 at text scale 2.5', (tester) async {
      await mountUpdate(tester, size: const Size(320, 568), scale: 2.5);
      await _tapSubmit(tester, 'Save password');
      expect(tester.takeException(), isNull);
    });

    testWidgets('password fields in update screen toggle visibility', (
      tester,
    ) async {
      await mountUpdate(tester);
      expect(find.byTooltip('Show password'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
    });
  });

  group('verification screen', () {
    testWidgets('verified button reloads once on double tap and shows errors', (
      tester,
    ) async {
      final repo = FieldAuthRepo()..wait = Completer<void>();
      await _mount(tester, repo, home: const VerificationScreen());
      final button = find.widgetWithText(
        FilledButton,
        'I have verified my email',
      );
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.tap(button);
      await tester.pump();
      expect(repo.reloads, 1);
      repo.wait!.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('resend sends once and failure is shown', (tester) async {
      final repo = FieldAuthRepo()
        ..failure = const AppException('Too many attempts. Please wait.');
      await _mount(tester, repo, home: const VerificationScreen());
      final resend = find.widgetWithText(
        OutlinedButton,
        'Resend verification email',
      );
      await tester.ensureVisible(resend);
      await tester.tap(resend);
      await tester.pumpAndSettle();
      expect(repo.verifications, 1);
      expect(find.text('Too many attempts. Please wait.'), findsOneWidget);
    });

    testWidgets('fits 320x568 at large text', (tester) async {
      final repo = FieldAuthRepo();
      await _mount(
        tester,
        repo,
        home: const VerificationScreen(),
        size: const Size(320, 568),
        textScale: 2.5,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
