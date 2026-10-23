import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/constants/asset_path.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/auth/widgets/google_sign_in_button.dart';
import 'package:eden_booking/utils/exceptions/app_exception.dart';
import 'auth_google_ui_test.dart' show mountAuth, loadAuthPreviewFonts;
import 'google_sign_in_flow_test.dart' show GoogleAuthFake;

class _LoginSource extends GoogleAuthFake {
  String? submittedEmail, submittedPassword, resetEmail, registeredName;
  Completer<void>? saving;
  bool fail = false;

  @override
  Future<void> signIn(String email, String password) async {
    passwordSignIns++;
    submittedEmail = email;
    submittedPassword = password;
    await saving?.future;
    if (fail) throw const AppException('Email or password is incorrect.');
  }

  @override
  Future<void> resetPassword(String email) async {
    resetEmail = email;
  }

  @override
  Future<void> register(String name, String email, String password) async {
    registeredName = name;
    submittedEmail = email;
    submittedPassword = password;
  }
}

Future<void> savePreview(WidgetTester tester, String name) async {
  if (!const bool.fromEnvironment('AUTH_PREVIEWS')) return;
  await tester.runAsync(() async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('auth-preview')),
    );
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File(
      '/tmp/login-redesign-$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  setUpAll(loadAuthPreviewFonts);
  for (final config in [
    (
      name: 'phone-dark',
      size: const Size(390, 844),
      light: false,
      scale: 1.0,
      inset: 0.0,
    ),
    (
      name: 'phone-light',
      size: const Size(390, 844),
      light: true,
      scale: 1.0,
      inset: 0.0,
    ),
    (
      name: 'desktop-dark',
      size: const Size(1440, 1000),
      light: false,
      scale: 1.0,
      inset: 0.0,
    ),
    (
      name: 'desktop-light',
      size: const Size(1440, 1000),
      light: true,
      scale: 1.0,
      inset: 0.0,
    ),
    (
      name: 'tablet',
      size: const Size(768, 1024),
      light: true,
      scale: 1.0,
      inset: 0.0,
    ),
    (
      name: 'landscape',
      size: const Size(844, 390),
      light: false,
      scale: 1.0,
      inset: 0.0,
    ),
    (
      name: 'large-text-keyboard',
      size: const Size(320, 720),
      light: false,
      scale: 1.8,
      inset: 260.0,
    ),
  ]) {
    testWidgets('login layout and actions remain reachable on ${config.name}', (
      tester,
    ) async {
      final source = _LoginSource();
      final auth = AuthCubit(source);
      addTearDown(auth.close);
      addTearDown(source.events.close);
      await mountAuth(
        tester,
        auth,
        size: config.size,
        light: config.light,
        textScale: config.scale,
        keyboardInset: config.inset,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(BookingBrand), findsOneWidget);
      final logo = tester.widget<Image>(
        find.descendant(
          of: find.byType(BookingBrand),
          matching: find.byType(Image),
        ),
      );
      expect((logo.image as AssetImage).assetName, AssetPath.bookingLogo);
      final desktop = config.size.width >= AuthLayout.desktopBreakpoint;
      expect(
        find.byKey(const ValueKey('auth-brand-panel')),
        desktop ? findsOneWidget : findsNothing,
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('auth-form-card'))).width,
        lessThanOrEqualTo(AuthLayout.formWidth),
      );
      expect(
        tester.getTopLeft(find.text('Sign in')).dy,
        lessThan(tester.getTopLeft(find.byType(GoogleSignInButton)).dy),
      );
      await savePreview(tester, config.name);
      await tester.ensureVisible(find.byType(GoogleSignInButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue with Google'));
      await tester.pumpAndSettle();
      expect(source.launches, 1);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('email keyboard moves to password and submits once while busy', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final source = _LoginSource()..saving = Completer<void>();
    final auth = AuthCubit(source);
    addTearDown(auth.close);
    addTearDown(source.events.close);
    await mountAuth(tester, auth);
    expect(
      tester.getSemantics(find.byType(EditableText).first).label,
      contains('Email address'),
    );
    semantics.dispose();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'owner@example.com');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();
    final password = tester.widget<EditableText>(
      find.descendant(of: fields.at(1), matching: find.byType(EditableText)),
    );
    expect(password.focusNode.hasFocus, isTrue);
    await tester.enterText(fields.at(1), 'private-test-password');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(source.submittedEmail, 'owner@example.com');
    expect(source.submittedPassword, 'private-test-password');
    expect(source.passwordSignIns, 1);
    expect(tester.widget<TextFormField>(fields.first).enabled, isFalse);
    expect(
      tester
          .widget<GoogleSignInButton>(find.byType(GoogleSignInButton))
          .onPressed,
      isNull,
    );
    source.saving!.complete();
    await tester.pumpAndSettle();
    expect(tester.widget<TextFormField>(fields.first).enabled, isTrue);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'invalid input and failed sign-in keep editable values and show feedback',
    (tester) async {
      final source = _LoginSource()..fail = true;
      final auth = AuthCubit(source);
      addTearDown(auth.close);
      addTearDown(source.events.close);
      await mountAuth(tester, auth);
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(source.passwordSignIns, 0);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'owner@example.com');
      await tester.enterText(fields.at(1), 'private-test-password');
      await tester.ensureVisible(find.text('Sign in'));
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Email or password is incorrect.'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(fields.first).controller!.text,
        'owner@example.com',
      );
      expect(
        tester.widget<TextFormField>(fields.at(1)).controller!.text,
        'private-test-password',
      );
      await tester.tap(find.byTooltip('Show password'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: fields.at(1),
                matching: find.byType(EditableText),
              ),
            )
            .obscureText,
        isFalse,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'inline password recovery validates email and calls existing reset',
    (tester) async {
      final source = _LoginSource();
      final auth = AuthCubit(source);
      final repository = auth.repository as _LoginSource;
      addTearDown(auth.close);
      addTearDown(repository.events.close);
      await mountAuth(tester, auth);
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(repository.resetEmail, isNull);
      expect(find.text('Enter your email address first.'), findsOneWidget);
      await tester.enterText(
        find.byType(TextFormField).first,
        'owner@example.com',
      );
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();
      expect(repository.resetEmail, 'owner@example.com');
      expect(
        find.text('If an account exists, a reset email has been requested.'),
        findsOneWidget,
      );
    },
  );
  testWidgets(
    'registration uses the same form and keeps name/email/password behavior',
    (tester) async {
      final source = _LoginSource();
      final auth = AuthCubit(source);
      final repository = auth.repository as _LoginSource;
      addTearDown(auth.close);
      addTearDown(repository.events.close);
      await mountAuth(tester, auth, register: true);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Alex Owner');
      await tester.enterText(fields.at(1), 'owner@example.com');
      await tester.enterText(fields.at(2), 'private-test-password');
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(repository.registeredName, 'Alex Owner');
      expect(repository.submittedEmail, 'owner@example.com');
      expect(repository.submittedPassword, 'private-test-password');
      expect(tester.takeException(), isNull);
    },
  );
}
