import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:eden_booking/design_system/design_system.dart';
import 'package:eden_booking/modules/auth/cubit/auth_cubit.dart';
import 'package:eden_booking/modules/auth/models/app_user.dart';
import 'package:eden_booking/modules/auth/repositories/auth_repository_interface.dart';
import 'package:eden_booking/modules/auth/screens/auth_screen.dart';
import 'package:eden_booking/modules/auth/widgets/google_sign_in_button.dart';
import 'google_sign_in_flow_test.dart'
    show GoogleAuthFake, MemoryContinuationRepository, invitationToken;

class LegacyAuth extends Fake implements AuthRepository {
  @override
  Stream<AppUser?> get changes => Stream.value(null);
  @override
  AppUser? get currentUser => null;
}

Future<void> mountAuth(
  WidgetTester tester,
  AuthCubit auth, {
  bool register = false,
  bool invitation = false,
  Size size = const Size(390, 844),
  bool light = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    BlocProvider.value(
      value: auth,
      child: ScreenUtilInit(
        designSize: size.width < 600 ? const Size(390, 844) : size,
        builder: (context, child) {
          var theme = light ? lightTheme() : darkTheme();
          if (const bool.fromEnvironment('AUTH_PREVIEWS')) {
            const textStyle = WidgetStatePropertyAll(
              TextStyle(
                fontFamily: 'Roboto',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            );
            theme = theme.copyWith(
              textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
              filledButtonTheme: FilledButtonThemeData(
                style: theme.filledButtonTheme.style?.copyWith(
                  textStyle: textStyle,
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: theme.outlinedButtonTheme.style?.copyWith(
                  textStyle: textStyle,
                ),
              ),
              textButtonTheme: TextButtonThemeData(
                style: theme.textButtonTheme.style?.copyWith(
                  textStyle: textStyle,
                ),
              ),
            );
          }
          return MaterialApp(
            theme: theme,
            home: RepaintBoundary(
              key: const ValueKey('auth-preview'),
              child: AuthSplitLayout(
                child: AuthScreen(
                  register: register,
                  invitationToken: invitation ? invitationToken : null,
                  returnTo: '/profile',
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (find.byType(GoogleSignInButton).evaluate().isNotEmpty) {
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/auth/google-g.png'),
        tester.element(find.byType(GoogleSignInButton)),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  setUpAll(() async {
    if (!const bool.fromEnvironment('AUTH_PREVIEWS')) return;
    for (final font in {
      'Roboto': 'Roboto-Regular.ttf',
      'MaterialIcons': 'MaterialIcons-Regular.otf',
    }.entries) {
      final bytes = await File(
        '/tmp/home-preview-fonts/${font.value}',
      ).readAsBytes();
      await (FontLoader(
        font.key,
      )..addFont(Future.value(ByteData.sublistView(bytes)))).load();
    }
  });
  for (final config in [
    (390.0, false, false),
    (1440.0, true, false),
    (320.0, true, true),
  ]) {
    testWidgets(
      'Google works without email fields at ${config.$1}px, register ${config.$2}, invitation ${config.$3}',
      (tester) async {
        final source = GoogleAuthFake()..launching = Completer<void>();
        final store = MemoryContinuationRepository();
        final auth = AuthCubit(source, continuations: store);
        addTearDown(auth.close);
        addTearDown(source.events.close);
        await mountAuth(
          tester,
          auth,
          register: config.$2,
          invitation: config.$3,
          size: Size(config.$1, 1000),
          light: config.$1 == 1440,
        );
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(tester.takeException(), isNull);
        if (config.$3) {
          expect(find.text('Join your team.'), findsOneWidget);
          expect(find.text('Your full name'), findsOneWidget);
          expect(find.text('Owner’s full name'), findsNothing);
        }
        if (const bool.fromEnvironment('AUTH_PREVIEWS')) {
          await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('auth-preview')),
            );
            final image = await boundary.toImage(pixelRatio: 1);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File(
              '/tmp/google-auth-${config.$1.toInt()}.png',
            ).writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.ensureVisible(find.byType(GoogleSignInButton));
        await tester.tap(find.text('Continue with Google'));
        await tester.pump();
        expect(source.launches, 1);
        expect(find.text('Opening Google…'), findsOneWidget);
        expect(find.text('Enter your email address.'), findsNothing);
        expect(store.value!.returnTo, '/profile');
        expect(
          store.value!.invitationToken,
          config.$3 ? invitationToken : null,
        );
        expect(
          tester
              .widget<GoogleSignInButton>(find.byType(GoogleSignInButton))
              .busy,
          isTrue,
        );
        source.launching!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Continue with Google'), findsOneWidget);
        expect(find.textContaining('Complete Google sign-in'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'legacy email authentication does not advertise unsupported Google sign-in',
    (tester) async {
      final auth = AuthCubit(LegacyAuth());
      addTearDown(auth.close);
      await mountAuth(tester, auth, register: true);
      expect(find.byType(GoogleSignInButton), findsNothing);
      expect(find.textContaining('Continue with Google'), findsNothing);
      expect(find.text('Create account'), findsOneWidget);
    },
  );
}
